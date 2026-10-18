import Foundation
import GRDB
import Application
import Domain

/// After-workout feedback in the app database (table workout_feedback,
/// migration v6_workout_feedback). One row per Health workout; saving replaces it.
public struct GRDBWorkoutFeedbackRepository: WorkoutFeedbackRepository {
    private let database: DatabaseProvider

    public init(database: DatabaseProvider) {
        self.database = database
    }

    public func save(_ feedback: WorkoutFeedback) async throws {
        let areas = String(decoding: try JSONEncoder().encode(feedback.areas), as: UTF8.self)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO workout_feedback (workoutId, workoutKind, localDate, status, areas, note, recordedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    feedback.workoutId, feedback.workoutKind.rawValue, feedback.localDate.description, feedback.status.rawValue, areas,
                    feedback.note, GRDBPlanRepository.timestamp(feedback.recordedAt),
                ]
            )
        }
    }

    public func feedback(workoutId: String) async throws -> WorkoutFeedback? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM workout_feedback WHERE workoutId = ?", arguments: [workoutId]).flatMap(Self.feedback)
        }
    }

    public func feedback(since from: LocalDate) async throws -> [WorkoutFeedback] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workout_feedback WHERE localDate >= ?", arguments: [from.description])
                .compactMap(Self.feedback)
        }
    }

    /// Nil for a row this build cannot read.
    private static func feedback(_ row: Row) -> WorkoutFeedback? {
        let areasText: String = row["areas"]
        guard
            let kind = FeedbackWorkoutKind(rawValue: row["workoutKind"]),
            let date = LocalDate(row["localDate"] as String),
            let status = WorkoutFeedback.Status(rawValue: row["status"]),
            let recordedAt = GRDBPlanRepository.date(row["recordedAt"]),
            let areas = try? JSONDecoder().decode([AreaReport].self, from: Data(areasText.utf8))
        else { return nil }
        return WorkoutFeedback(
            workoutId: row["workoutId"], workoutKind: kind, localDate: date, status: status, areas: areas, note: row["note"],
            recordedAt: recordedAt
        )
    }
}

/// Suggested plan changes (table plan_adjustment, migration v7_plan_adjustment).
/// Apply and undo rewrite the window's runs and strength sessions in one
/// transaction, after checking the window still holds what the suggestion expects.
public struct GRDBPlanAdjustmentRepository: PlanAdjustmentRepository {
    private let database: DatabaseProvider
    private let clock: any Clock

    public init(database: DatabaseProvider, clock: any Clock) {
        self.database = database
        self.clock = clock
    }

    public func savePending(planId: String, adjustment: PlanAdjustment) async throws -> StoredAdjustment {
        let payload = try Self.encode(adjustment)
        let now = clock.now()
        let stamp = GRDBPlanRepository.timestamp(now)
        let id = try await database.writer.write { db -> Int64 in
            try db.execute(
                sql: "UPDATE plan_adjustment SET status = 'dismissed', decidedAt = ? WHERE planId = ? AND status = 'pending'",
                arguments: [stamp, planId]
            )
            try db.execute(
                sql: "INSERT INTO plan_adjustment (planId, createdAt, status, payload, decidedAt) VALUES (?, ?, 'pending', ?, NULL)",
                arguments: [planId, stamp, payload]
            )
            return db.lastInsertedRowID
        }
        return StoredAdjustment(id: id, planId: planId, createdAt: now, status: .pending, adjustment: adjustment)
    }

    public func pending(planId: String) async throws -> StoredAdjustment? {
        try await database.writer.read { db in
            try Row.fetchOne(
                db, sql: "SELECT * FROM plan_adjustment WHERE planId = ? AND status = 'pending' ORDER BY id DESC LIMIT 1",
                arguments: [planId]
            ).flatMap(Self.stored)
        }
    }

    public func apply(id: Int64) async throws {
        let stamp = GRDBPlanRepository.timestamp(clock.now())
        try await database.writer.write { db in
            guard let stored = try Self.fetch(id: id, db: db), stored.status == .pending else { throw PlanAdjustmentError.notFound }
            let change = stored.adjustment
            try Self.replace(
                planId: stored.planId, window: change.window, expectRuns: change.beforeRuns, expectStrength: change.beforeStrength,
                newRuns: change.afterRuns, newStrength: change.afterStrength, db: db
            )
            try db.execute(sql: "UPDATE plan_adjustment SET status = 'applied', decidedAt = ? WHERE id = ?", arguments: [stamp, id])
        }
    }

    public func dismiss(id: Int64) async throws {
        let stamp = GRDBPlanRepository.timestamp(clock.now())
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE plan_adjustment SET status = 'dismissed', decidedAt = ? WHERE id = ? AND status = 'pending'",
                arguments: [stamp, id]
            )
        }
    }

    public func undo(id: Int64) async throws {
        let stamp = GRDBPlanRepository.timestamp(clock.now())
        try await database.writer.write { db in
            guard let stored = try Self.fetch(id: id, db: db), stored.status == .applied else { throw PlanAdjustmentError.notFound }
            let change = stored.adjustment
            try Self.replace(
                planId: stored.planId, window: change.window, expectRuns: change.afterRuns, expectStrength: change.afterStrength,
                newRuns: change.beforeRuns, newStrength: change.beforeStrength, db: db
            )
            try db.execute(sql: "UPDATE plan_adjustment SET status = 'undone', decidedAt = ? WHERE id = ?", arguments: [stamp, id])
        }
    }

    // MARK: Helpers

    /// Checks the window holds exactly `expectRuns` and `expectStrength` (by id and
    /// date), then swaps them for the new ones.
    private static func replace(
        planId: String, window: AdjustmentWindow, expectRuns: [PlannedSession], expectStrength: [StrengthSession],
        newRuns: [PlannedSession], newStrength: [StrengthSession], db: Database
    ) throws {
        let range: [any DatabaseValueConvertible] = [planId, window.start.description, window.end.description]
        let runRows = try Row.fetchAll(db, sql: "SELECT id, date FROM plan_session WHERE planId = ? AND date >= ? AND date <= ?", arguments: StatementArguments(range))
        let strengthRows = try Row.fetchAll(db, sql: "SELECT id, date FROM plan_strength WHERE planId = ? AND date >= ? AND date <= ?", arguments: StatementArguments(range))
        let currentRuns = Set(runRows.map { "\($0["id"] as String)@\($0["date"] as String)" })
        let currentStrength = Set(strengthRows.map { "\($0["id"] as String)@\($0["date"] as String)" })
        guard
            currentRuns == Set(expectRuns.map { "\($0.id)@\($0.date)" }),
            currentStrength == Set(expectStrength.map { "\($0.id)@\($0.date)" })
        else { throw PlanAdjustmentError.stale }
        for run in expectRuns { try GRDBPlanRepository.deleteRun(id: run.id, planId: planId, db: db) }
        for item in expectStrength { try GRDBPlanRepository.deleteStrength(id: item.id, planId: planId, db: db) }
        for run in newRuns { try GRDBPlanRepository.insertRun(run, planId: planId, db: db) }
        for item in newStrength { try GRDBPlanRepository.insertStrength(item, planId: planId, db: db) }
    }

    private static func fetch(id: Int64, db: Database) throws -> StoredAdjustment? {
        try Row.fetchOne(db, sql: "SELECT * FROM plan_adjustment WHERE id = ?", arguments: [id]).flatMap(stored)
    }

    private static func stored(_ row: Row) -> StoredAdjustment? {
        let payload: String = row["payload"]
        guard
            let status = StoredAdjustment.Status(rawValue: row["status"]),
            let createdAt = GRDBPlanRepository.date(row["createdAt"]),
            let adjustment = try? JSONDecoder().decode(PlanAdjustment.self, from: Data(payload.utf8))
        else { return nil }
        return StoredAdjustment(id: row["id"], planId: row["planId"], createdAt: createdAt, status: status, adjustment: adjustment)
    }

    private static func encode(_ adjustment: PlanAdjustment) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(adjustment), as: UTF8.self)
    }
}
