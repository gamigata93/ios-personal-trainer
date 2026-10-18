import Foundation
import GRDB
import Application
import Domain

/// The plan and its edit log in the app database. Rows are mapped to and from
/// the Domain structs here; GRDB types never leave this file's module.
/// Nothing is ever logged.
public struct GRDBPlanRepository: PlanRepository {
    private let database: DatabaseProvider
    private let clock: any Clock

    public init(database: DatabaseProvider, clock: any Clock) {
        self.database = database
        self.clock = clock
    }

    private var writer: any DatabaseWriter { database.writer }

    /// A fresh in-memory database holding `plan` as the active plan, ready at
    /// once (written synchronously): DEBUG `-seedPlan`, previews and tests.
    public static func inMemory(seededWith plan: TrainingPlan?, clock: any Clock) throws -> GRDBPlanRepository {
        GRDBPlanRepository(database: try seededDatabase(plan), clock: clock)
    }

    /// A fresh in-memory database holding `plan` as the active plan, so other
    /// repositories (coach notes, analyses) can share it.
    public static func seededDatabase(_ plan: TrainingPlan?) throws -> DatabaseProvider {
        let database = try DatabaseProvider.inMemory()
        if let plan {
            try database.writer.write { db in try insert(plan, db: db) }
        }
        return database
    }

    // MARK: Plan

    public func save(_ plan: TrainingPlan) async throws {
        try await writer.write { db in
            // Older active plans are kept but no longer active; the same id is replaced.
            try db.execute(sql: "DELETE FROM plan WHERE id = ?", arguments: [plan.id])
            try db.execute(sql: "UPDATE plan SET isActive = 0 WHERE isActive = 1")
            try Self.insert(plan, db: db)
        }
    }

    public func loadActive() async -> TrainingPlan? {
        try? await writer.read { db in try Self.fetchActive(db) }
    }

    public func hasActivePlan() async -> Bool {
        (try? await writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM plan WHERE isActive = 1)") ?? false
        }) ?? false
    }

    /// Removes the active plan with its weeks, sessions, segments and edits (cascade).
    public func deleteActive() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM plan WHERE isActive = 1")
        }
    }

    // MARK: Edits

    public func applyEdit(planId: String, edit: PlanEdit) async throws -> EditReceipt {
        let now = Self.timestamp(clock.now())
        return try await writer.write { db in
            guard try Self.planExists(planId, db: db) else { throw PlanRepositoryError.noActivePlan }
            let current = try Self.placements(planId: planId, ids: edit.sessionIds, db: db)
            guard let change = PlanChange.make(edit, current: current) else { throw PlanRepositoryError.stalePlan }
            do {
                try Self.write(change.after, planId: planId, db: db)
            } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                // Another session already holds the target day.
                throw PlanRepositoryError.stalePlan
            }
            try db.execute(
                sql: "INSERT INTO plan_edit (planId, createdAt, kind, payload, undoneAt) VALUES (?, ?, ?, ?, NULL)",
                arguments: [planId, now, edit.kind, try Self.encodePayload(EditPayload(edit: edit, before: change.before, after: change.after))]
            )
            return EditReceipt(editId: db.lastInsertedRowID)
        }
    }

    public func undoEdit(planId: String, editId: Int64) async throws {
        let now = Self.timestamp(clock.now())
        try await writer.write { db in
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT payload, undoneAt FROM plan_edit WHERE id = ? AND planId = ?", arguments: [editId, planId]
                ),
                (row["undoneAt"] as String?) == nil,
                let payload = try? Self.decodePayload(row["payload"])
            else { throw PlanRepositoryError.cannotUndo }
            let current = try Self.placements(planId: planId, ids: payload.after.map(\.sessionId), db: db)
            guard payload.after.allSatisfy({ current[$0.sessionId] == $0 }) else { throw PlanRepositoryError.cannotUndo }
            do {
                try Self.write(payload.before, planId: planId, db: db)
            } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                throw PlanRepositoryError.cannotUndo
            }
            try db.execute(sql: "UPDATE plan_edit SET undoneAt = ? WHERE id = ?", arguments: [now, editId])
        }
    }

    public func recentEdits(planId: String, limit: Int) async throws -> [PlanEditRecord] {
        try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, createdAt, payload, undoneAt FROM plan_edit WHERE planId = ? ORDER BY id DESC LIMIT ?",
                arguments: [planId, limit]
            ).compactMap { row in
                guard
                    let payload = try? Self.decodePayload(row["payload"]),
                    let createdAt = Self.date(row["createdAt"])
                else { return nil }
                return PlanEditRecord(
                    id: row["id"],
                    createdAt: createdAt,
                    edit: payload.edit,
                    change: PlanChange(before: payload.before, after: payload.after),
                    undoneAt: (row["undoneAt"] as String?).flatMap(Self.date)
                )
            }
        }
    }

    // MARK: Writing

    private static func insert(_ plan: TrainingPlan, db: Database) throws {
        let days = Weekday.allCases.filter(plan.race.trainingDays.contains).map(\.rawValue)
        let daysJSON = String(decoding: try JSONEncoder().encode(days), as: UTF8.self)
        try db.execute(
            sql: """
                INSERT INTO plan (id, schemaVersion, createdAt, generatedBy, planKind, raceDistanceKm, raceElevationM,
                                  raceDate, planStart, trainingDays, isActive)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                """,
            arguments: [
                plan.id, plan.schemaVersion, timestamp(plan.createdAt), plan.generatedBy, plan.planKind.rawValue,
                plan.race.distanceKm, plan.race.elevationGainM, plan.race.raceDate.description, plan.planStart.description, daysJSON,
            ]
        )
        for week in plan.weeks {
            try db.execute(
                sql: "INSERT INTO plan_week (planId, idx, phase, startDate, targetKm) VALUES (?, ?, ?, ?, ?)",
                arguments: [plan.id, week.index, week.phase.rawValue, week.startDate.description, week.targetKm]
            )
        }
        for session in plan.sessions {
            try insertRun(session, planId: plan.id, db: db)
        }
        for item in plan.strengthSessions {
            try insertStrength(item, planId: plan.id, db: db)
        }
    }

    static func insertRun(_ session: PlannedSession, planId: String, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO plan_session (planId, id, originalDate, date, type, name, distanceKm, estimatedMinutes,
                                          effort, note, isMissed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                planId, session.id, session.originalDate.description, session.date.description, session.type.rawValue,
                session.name, session.distanceKm, session.estimatedMinutes, session.effort, session.note, session.isMissed,
            ]
        )
        for (position, segment) in session.segments.enumerated() {
            try db.execute(
                sql: "INSERT INTO plan_segment (planId, sessionId, position, label, detail, distanceKm) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [planId, session.id, position, segment.label, segment.detail, segment.distanceKm]
            )
        }
    }

    static func deleteRun(id: String, planId: String, db: Database) throws {
        try db.execute(sql: "DELETE FROM plan_segment WHERE planId = ? AND sessionId = ?", arguments: [planId, id])
        try db.execute(sql: "DELETE FROM plan_session WHERE planId = ? AND id = ?", arguments: [planId, id])
    }

    static func insertStrength(_ item: StrengthSession, planId: String, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO plan_strength (planId, id, originalDate, date, focus, variant, minutes, effort, isMissed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                planId, item.id, item.originalDate.description, item.date.description, item.focus.rawValue, item.variant.rawValue,
                item.minutes, item.effort, item.isMissed,
            ]
        )
        for (position, exercise) in item.exercises.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO plan_strength_exercise (planId, strengthId, position, name, sets, reps, seconds, perSide, equipment, howTo)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    planId, item.id, position, exercise.name, exercise.sets, exercise.reps, exercise.seconds, exercise.perSide,
                    exercise.equipment.rawValue, exercise.howTo,
                ]
            )
        }
    }

    static func deleteStrength(id: String, planId: String, db: Database) throws {
        try db.execute(sql: "DELETE FROM plan_strength_exercise WHERE planId = ? AND strengthId = ?", arguments: [planId, id])
        try db.execute(sql: "DELETE FROM plan_strength WHERE planId = ? AND id = ?", arguments: [planId, id])
    }

    /// Writes new dates and flags. Every touched session first moves to a
    /// placeholder date ("~" + id, never a real day), so UNIQUE(planId, date) never
    /// fails half-way through a swap. Runs inside the caller's transaction.
    private static func write(_ placements: [SessionPlacement], planId: String, db: Database) throws {
        for placement in placements {
            try db.execute(
                sql: "UPDATE plan_session SET date = '~' || id WHERE planId = ? AND id = ?",
                arguments: [planId, placement.sessionId]
            )
        }
        for placement in placements {
            try db.execute(
                sql: "UPDATE plan_session SET date = ?, isMissed = ? WHERE planId = ? AND id = ?",
                arguments: [placement.date.description, placement.isMissed, planId, placement.sessionId]
            )
        }
    }

    // MARK: Reading

    private static func planExists(_ planId: String, db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM plan WHERE id = ? AND isActive = 1)", arguments: [planId]) ?? false
    }

    private static func placements(planId: String, ids: [String], db: Database) throws -> [String: SessionPlacement] {
        var result: [String: SessionPlacement] = [:]
        for id in ids {
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT date, isMissed FROM plan_session WHERE planId = ? AND id = ?", arguments: [planId, id]
                ),
                let date = LocalDate(row["date"] as String)
            else { continue }
            result[id] = SessionPlacement(sessionId: id, date: date, isMissed: row["isMissed"])
        }
        return result
    }

    /// Nil when there is no active plan or a row cannot be read.
    private static func fetchActive(_ db: Database) throws -> TrainingPlan? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM plan WHERE isActive = 1 LIMIT 1") else { return nil }
        let planId: String = row["id"]
        let daysText: String = row["trainingDays"]
        guard
            let createdAt = date(row["createdAt"]),
            let planKind = PlanKind(rawValue: row["planKind"]),
            let raceDate = LocalDate(row["raceDate"] as String),
            let planStart = LocalDate(row["planStart"] as String),
            let dayNames = try? JSONDecoder().decode([String].self, from: Data(daysText.utf8))
        else { return nil }
        let trainingDays = dayNames.compactMap(Weekday.init(rawValue:))
        guard trainingDays.count == dayNames.count else { return nil }

        var segments: [String: [Segment]] = [:]
        for segment in try Row.fetchAll(
            db, sql: "SELECT * FROM plan_segment WHERE planId = ? ORDER BY sessionId, position", arguments: [planId]
        ) {
            segments[segment["sessionId"], default: []].append(
                Segment(label: segment["label"], detail: segment["detail"], distanceKm: segment["distanceKm"])
            )
        }

        var sessions: [PlannedSession] = []
        for session in try Row.fetchAll(db, sql: "SELECT * FROM plan_session WHERE planId = ? ORDER BY date", arguments: [planId]) {
            let id: String = session["id"]
            guard
                let originalDate = LocalDate(session["originalDate"] as String),
                let date = LocalDate(session["date"] as String),
                let type = SessionType(rawValue: session["type"])
            else { return nil }
            sessions.append(PlannedSession(
                id: id,
                originalDate: originalDate,
                date: date,
                type: type,
                name: session["name"],
                distanceKm: session["distanceKm"],
                estimatedMinutes: session["estimatedMinutes"],
                effort: session["effort"],
                segments: segments[id] ?? [],
                note: session["note"],
                isMissed: session["isMissed"]
            ))
        }

        var exercises: [String: [StrengthExercise]] = [:]
        for row in try Row.fetchAll(
            db, sql: "SELECT * FROM plan_strength_exercise WHERE planId = ? ORDER BY strengthId, position", arguments: [planId]
        ) {
            guard let equipment = StrengthEquipment(rawValue: row["equipment"]) else { return nil }
            exercises[row["strengthId"], default: []].append(StrengthExercise(
                name: row["name"], sets: row["sets"], reps: row["reps"], seconds: row["seconds"], perSide: row["perSide"],
                equipment: equipment, howTo: row["howTo"]
            ))
        }
        var strength: [StrengthSession] = []
        for row in try Row.fetchAll(db, sql: "SELECT * FROM plan_strength WHERE planId = ? ORDER BY date", arguments: [planId]) {
            let id: String = row["id"]
            guard
                let originalDate = LocalDate(row["originalDate"] as String),
                let date = LocalDate(row["date"] as String),
                let focus = StrengthFocus(rawValue: row["focus"]),
                let variant = StrengthVariant(rawValue: row["variant"])
            else { return nil }
            strength.append(StrengthSession(
                id: id, originalDate: originalDate, date: date, focus: focus, variant: variant, minutes: row["minutes"],
                effort: row["effort"], exercises: exercises[id] ?? [], isMissed: row["isMissed"]
            ))
        }

        var weeks: [PlanWeek] = []
        for week in try Row.fetchAll(db, sql: "SELECT * FROM plan_week WHERE planId = ? ORDER BY idx", arguments: [planId]) {
            guard let start = LocalDate(week["startDate"] as String), let phase = PlanPhase(rawValue: week["phase"]) else { return nil }
            weeks.append(PlanWeek(index: week["idx"], startDate: start, phase: phase, targetKm: week["targetKm"], sessions: []))
        }

        return TrainingPlan(
            schemaVersion: row["schemaVersion"],
            id: planId,
            createdAt: createdAt,
            generatedBy: row["generatedBy"],
            planKind: planKind,
            race: RaceSetup(
                distanceKm: row["raceDistanceKm"],
                elevationGainM: row["raceElevationM"],
                raceDate: raceDate,
                trainingDays: Set(trainingDays)
            ),
            planStart: planStart,
            weeks: weeks
        ).replacing(sessions: sessions, strength: strength)
    }

    // MARK: Encoding

    /// What the edit log stores: the edit and the placements before and after it.
    struct EditPayload: Codable, Equatable {
        let edit: PlanEdit
        let before: [SessionPlacement]
        let after: [SessionPlacement]
    }

    private static func encodePayload(_ payload: EditPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    private static func decodePayload(_ text: String) throws -> EditPayload {
        try JSONDecoder().decode(EditPayload.self, from: Data(text.utf8))
    }

    /// ISO-8601 in UTC with milliseconds: "2026-10-28T07:00:00.000Z".
    static func timestamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    static func date(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}
