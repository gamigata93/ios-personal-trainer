import Foundation
import Testing
import GRDB
import Application
import Domain
@testable import Infrastructure

private typealias F = EditPlanFixture

private struct TestClock: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) } // Wed 28 Oct 2026, 09:00 UTC
}

/// The plan repository against an in-memory database.
@Suite("GRDB plan repository")
struct GRDBPlanRepositoryTests {
    let provider: DatabaseProvider
    let repository: GRDBPlanRepository

    init() throws {
        provider = try DatabaseProvider.inMemory()
        repository = GRDBPlanRepository(database: provider, clock: TestClock())
    }

    private func moveEdit(_ d: Int, to: LocalDate) -> PlanEdit {
        .move(sessionId: F.id(10, d), from: F.day(10, d), to: to)
    }

    private var swapEdit: PlanEdit {
        .swap(sessionIdA: F.id(10, 28), sessionIdB: F.id(10, 30), dateA: F.day(10, 28), dateB: F.day(10, 30))
    }

    private func count(_ table: String) async throws -> Int {
        try await provider.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1 }
    }

    @Test func roundTripEqualsTheOriginal() async throws {
        try await repository.save(F.base)
        let loaded = try #require(await repository.loadActive())
        #expect(loaded == F.base)
        #expect(loaded.session(id: F.id(10, 23))?.note == "Rolling hills.")
        #expect(loaded.session(id: F.id(10, 16))?.segments.map(\.label) == ["Warm-up", "Main"])
        let days = try await provider.writer.read { db in try String.fetchOne(db, sql: "SELECT trainingDays FROM plan") }
        #expect(days == #"["monday","wednesday","friday"]"#)
        #expect(await repository.hasActivePlan())
    }

    @Test func saveReplacesTheActivePlan() async throws {
        try await repository.save(F.base)
        let other = F.base.stamped(id: "second", createdAt: F.base.createdAt)
        try await repository.save(other)
        #expect(await repository.loadActive()?.id == "second")
        #expect(try await count("plan WHERE isActive = 1") == 1)
    }

    @Test func moveUpdatesTheDateAndLogsOneEdit() async throws {
        try await repository.save(F.base)
        let receipt = try await repository.applyEdit(planId: F.base.id, edit: moveEdit(28, to: F.day(10, 29)))
        let plan = try #require(await repository.loadActive())
        #expect(plan.session(id: F.id(10, 28))?.date == F.day(10, 29))
        #expect(plan.session(id: F.id(10, 28))?.originalDate == F.day(10, 28))
        #expect(try await count("plan_edit") == 1)
        let edits = try await repository.recentEdits(planId: F.base.id, limit: 10)
        #expect(edits.map(\.id) == [receipt.editId])
        #expect(edits.first?.edit == moveEdit(28, to: F.day(10, 29)))
        #expect(edits.first?.undoneAt == nil)
    }

    @Test func uniqueDateRejectsTwoSessionsOnOneDay() async throws {
        try await repository.save(F.base)
        await #expect(throws: DatabaseError.self) {
            try await provider.writer.write { db in
                try db.execute(sql: "UPDATE plan_session SET date = '2026-10-30' WHERE id = '2026-10-28'")
            }
        }
        // Through the repository the same move is a stale edit, and nothing changes.
        await #expect(throws: PlanRepositoryError.stalePlan) {
            try await repository.applyEdit(planId: F.base.id, edit: moveEdit(28, to: F.day(10, 30)))
        }
        #expect(await repository.loadActive() == F.base)
        #expect(try await count("plan_edit") == 0)
    }

    @Test func swapRunsInOneTransaction() async throws {
        try await repository.save(F.base)
        _ = try await repository.applyEdit(planId: F.base.id, edit: swapEdit)
        let plan = try #require(await repository.loadActive())
        #expect(plan.session(id: F.id(10, 28))?.date == F.day(10, 30))
        #expect(plan.session(id: F.id(10, 30))?.date == F.day(10, 28))
    }

    @Test func aFailureMidSwapRollsBackBothDates() async throws {
        try await repository.save(F.base)
        // Fails on the last step: the long run (30 Oct) landing on 28 Oct.
        try await provider.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_swap BEFORE UPDATE OF date ON plan_session
                WHEN NEW.id = '2026-10-30' AND NEW.date = '2026-10-28'
                BEGIN SELECT RAISE(ABORT, 'forced'); END
                """)
        }
        await #expect(throws: (any Error).self) { try await repository.applyEdit(planId: F.base.id, edit: swapEdit) }
        #expect(await repository.loadActive() == F.base)
        #expect(try await count("plan_edit") == 0)
    }

    @Test func staleWhenTheSessionIsNotWhereTheEditExpects() async throws {
        try await repository.save(F.base)
        _ = try await repository.applyEdit(planId: F.base.id, edit: moveEdit(28, to: F.day(10, 29)))
        await #expect(throws: PlanRepositoryError.stalePlan) {
            try await repository.applyEdit(planId: F.base.id, edit: moveEdit(28, to: F.day(10, 31)))
        }
        await #expect(throws: PlanRepositoryError.noActivePlan) {
            try await repository.applyEdit(planId: "other", edit: moveEdit(30, to: F.day(10, 31)))
        }
    }

    @Test func undoRestoresMoveSwapAndMissedExactly() async throws {
        try await repository.save(F.base)
        for edit in [moveEdit(28, to: F.day(10, 29)), swapEdit, PlanEdit.markMissed(sessionId: F.id(10, 21))] {
            let receipt = try await repository.applyEdit(planId: F.base.id, edit: edit)
            #expect(await repository.loadActive() != F.base)
            try await repository.undoEdit(planId: F.base.id, editId: receipt.editId)
            #expect(await repository.loadActive() == F.base)
        }
        let edits = try await repository.recentEdits(planId: F.base.id, limit: 10)
        #expect(edits.count == 3)
        #expect(edits.allSatisfy { $0.undoneAt != nil })
        #expect(edits.map(\.edit.kind) == ["markMissed", "swap", "move"])
    }

    @Test func undoRestoresAMissedFlagClearedByAMove() async throws {
        try await repository.save(F.base)
        _ = try await repository.applyEdit(planId: F.base.id, edit: .markMissed(sessionId: F.id(10, 21)))
        let marked = await repository.loadActive()
        let receipt = try await repository.applyEdit(planId: F.base.id, edit: moveEdit(21, to: F.day(10, 29)))
        #expect(await repository.loadActive()?.session(id: F.id(10, 21))?.isMissed == false)
        try await repository.undoEdit(planId: F.base.id, editId: receipt.editId)
        #expect(await repository.loadActive() == marked)
    }

    @Test func cannotUndoTwiceOrAfterAnotherMove() async throws {
        try await repository.save(F.base)
        let first = try await repository.applyEdit(planId: F.base.id, edit: moveEdit(28, to: F.day(10, 29)))
        _ = try await repository.applyEdit(
            planId: F.base.id, edit: .move(sessionId: F.id(10, 28), from: F.day(10, 29), to: F.day(10, 31))
        )
        await #expect(throws: PlanRepositoryError.cannotUndo) { try await repository.undoEdit(planId: F.base.id, editId: first.editId) }

        let missed = try await repository.applyEdit(planId: F.base.id, edit: .markMissed(sessionId: F.id(10, 21)))
        try await repository.undoEdit(planId: F.base.id, editId: missed.editId)
        await #expect(throws: PlanRepositoryError.cannotUndo) { try await repository.undoEdit(planId: F.base.id, editId: missed.editId) }
        await #expect(throws: PlanRepositoryError.cannotUndo) { try await repository.undoEdit(planId: F.base.id, editId: 999) }
    }

    @Test func deleteActiveCascades() async throws {
        try await repository.save(F.base)
        _ = try await repository.applyEdit(planId: F.base.id, edit: moveEdit(28, to: F.day(10, 29)))
        try await repository.deleteActive()
        for table in ["plan", "plan_week", "plan_session", "plan_segment", "plan_edit"] {
            #expect(try await count(table) == 0, "\(table)")
        }
        #expect(await repository.hasActivePlan() == false)
        #expect(await repository.loadActive() == nil)
    }
}

@Suite("Database migrations")
struct DatabaseMigrationTests {
    @Test func v1RunsOnceAndCreatesTheFiveTables() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("db-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try DatabaseProvider.onDisk(directory: directory)
        try await GRDBPlanRepository(database: first, clock: TestClock()).save(F.base)
        let applied = try await first.writer.read { db in try PlanDatabaseMigrations.migrator.appliedMigrations(db) }
        #expect(applied == ["v1_plan", "v2_llm_usage", "v3_coach_note", "v4_workout_analysis"])
        let tables = try await first.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'plan%' ORDER BY name")
        }
        #expect(tables == ["plan", "plan_edit", "plan_segment", "plan_session", "plan_week"])
        let foreignKeys = try await first.writer.read { db in try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") }
        #expect(foreignKeys == true)

        // Reopening keeps the data and does not run v1 again.
        let second = try DatabaseProvider.onDisk(directory: directory)
        #expect(await GRDBPlanRepository(database: second, clock: TestClock()).loadActive() == F.base)
        let completed = try await second.writer.read { db in try PlanDatabaseMigrations.migrator.hasCompletedMigrations(db) }
        #expect(completed)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("trainer.sqlite").path))
    }
}

@Suite("Legacy plan import")
struct LegacyPlanImporterTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
    var legacyURL: URL { directory.appendingPathComponent("TrainingPlan.json") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// The old FilePlanRepository's format: no originalDate or isMissed.
    private func writeLegacy(_ plan: TrainingPlan) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(try JSONSerialization.jsonObject(with: encoder.encode(plan)) as? [String: Any])
        var weeks = try #require(json["weeks"] as? [[String: Any]])
        for index in weeks.indices {
            let sessions = try #require(weeks[index]["sessions"] as? [[String: Any]])
            weeks[index]["sessions"] = sessions.map { session in
                var old = session
                old["originalDate"] = nil
                old["isMissed"] = nil
                return old
            }
        }
        json["weeks"] = weeks
        try JSONSerialization.data(withJSONObject: json).write(to: legacyURL)
    }

    @Test func importsOnceAndRenamesTheFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLegacy(F.base)
        #expect(String(decoding: try Data(contentsOf: legacyURL), as: UTF8.self).contains("originalDate") == false)
        let repository = GRDBPlanRepository(database: try DatabaseProvider.inMemory(), clock: TestClock())
        let importer = LegacyPlanImporter(fileURL: legacyURL, plans: repository, clock: TestClock())

        #expect(await importer.run() == .imported)
        let plan = try #require(await repository.loadActive())
        #expect(plan == F.base)
        #expect(plan.sessions.allSatisfy { $0.originalDate == $0.date && !$0.isMissed && $0.id == $0.date.description })
        #expect(try files() == ["TrainingPlan.json.imported"])

        // A second launch finds no legacy file and imports nothing.
        #expect(await importer.run() == .noLegacyFile)
        #expect(try files() == ["TrainingPlan.json.imported"])
    }

    @Test func corruptFileIsRenamedAndIgnored() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ not json".utf8).write(to: legacyURL)
        let repository = GRDBPlanRepository(database: try DatabaseProvider.inMemory(), clock: TestClock())
        #expect(await LegacyPlanImporter(fileURL: legacyURL, plans: repository, clock: TestClock()).run() == .corrupt)
        #expect(await repository.hasActivePlan() == false)
        #expect(try files() == ["TrainingPlan.json.corrupt-20261028-090000"])
    }

    @Test func aDatabaseWithAPlanLeavesTheFileUntouched() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLegacy(F.base)
        let before = try Data(contentsOf: legacyURL)
        let repository = GRDBPlanRepository(database: try DatabaseProvider.inMemory(), clock: TestClock())
        let existing = F.base.stamped(id: "existing", createdAt: F.base.createdAt)
        try await repository.save(existing)
        #expect(await LegacyPlanImporter(fileURL: legacyURL, plans: repository, clock: TestClock()).run() == .databaseHasPlan)
        #expect(try files() == ["TrainingPlan.json"])
        #expect(try Data(contentsOf: legacyURL) == before)
        #expect(await repository.loadActive()?.id == "existing")
    }

    @Test func aFailedSaveKeepsTheFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLegacy(F.base)
        #expect(await LegacyPlanImporter(fileURL: legacyURL, plans: UnavailablePlanRepository(), clock: TestClock()).run() == .failed)
        #expect(try files() == ["TrainingPlan.json"])
    }
}
