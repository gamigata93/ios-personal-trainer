import Foundation
import Testing
import GRDB
import Application
import Domain
@testable import Infrastructure

@Suite("Coach notes and analyses in GRDB")
struct CoachNotePersistenceTests {
    let provider: DatabaseProvider
    let notes: GRDBCoachNoteRepository
    let analyses: GRDBWorkoutAnalysisRepository
    let plan = SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0))

    init() throws {
        provider = try GRDBPlanRepository.seededDatabase(SeedPlan.plan(createdAt: Date(timeIntervalSince1970: 0)))
        notes = GRDBCoachNoteRepository(database: provider)
        analyses = GRDBWorkoutAnalysisRepository(database: provider)
    }

    private func note(_ headline: String = "Steady and controlled", source: CoachNoteSource = .model, flags: [String] = []) -> SavedCoachNote {
        SavedCoachNote(
            planId: plan.id, sessionId: "2026-10-12", runId: "fake-2026-10-12", createdAt: Date(timeIntervalSince1970: 1_793_178_000),
            source: source, provider: source == .model ? .apple : nil, modelTag: source == .model ? "onDevice" : SavedCoachNote.rulesTag,
            note: CoachNote(headline: headline, howItWent: "How.", versusPlan: "Versus.", programStatus: "Program.", nextStep: "Next."),
            verdict: .watch, flags: flags, inputHash: "abc", factsLevel: source == .model ? 1 : nil
        )
    }

    @Test func noteRoundTripAndReplace() async throws {
        let first = note()
        try await notes.save(first)
        #expect(try await notes.note(planId: plan.id, sessionId: "2026-10-12") == first)
        let replaced = note("Right on plan", source: .rules, flags: [CoachNoteFallback.guardRejected.flag])
        try await notes.save(replaced)
        let loaded = try await notes.note(planId: plan.id, sessionId: "2026-10-12")
        #expect(loaded == replaced && loaded?.fallback == .guardRejected)
        #expect(try await notes.notes(planId: plan.id).count == 1)
        try await notes.delete(planId: plan.id, sessionId: "2026-10-12")
        #expect(try await notes.note(planId: plan.id, sessionId: "2026-10-12") == nil)
    }

    @Test func aNoteNeedsItsSession() async {
        var orphan = note()
        orphan = SavedCoachNote(
            planId: plan.id, sessionId: "2026-01-01", runId: orphan.runId, createdAt: orphan.createdAt, source: .model, provider: .apple,
            modelTag: "onDevice", note: orphan.note, verdict: .onTrack, inputHash: "x", factsLevel: 0
        )
        await #expect(throws: (any Error).self) { try await notes.save(orphan) }
    }

    @Test func analysisRoundTrip() async throws {
        let analysis = WorkoutAnalyzer.analyze(FakeWorkoutDetailSource.series(.tempo, runId: "fake-2026-10-12", start: .distantPast), computedAt: Date(timeIntervalSince1970: 1_793_178_000))
        try await analyses.save(analysis)
        #expect(try await analyses.analysis(runId: "fake-2026-10-12") == analysis)
        try await analyses.delete(runId: "fake-2026-10-12")
        #expect(try await analyses.analysis(runId: "fake-2026-10-12") == nil)
    }

    @Test func deletingThePlanCascadesNotesButKeepsAnalyses() async throws {
        try await notes.save(note())
        let analysis = WorkoutAnalysis.minimal(run: CompletedRun(id: "r1", localDate: LocalDate(year: 2026, month: 10, day: 12), distanceKm: 5, durationSeconds: 1_800), computedAt: .distantPast)
        try await analyses.save(analysis)
        try await GRDBPlanRepository(database: provider, clock: SystemClock()).deleteActive()
        #expect(try await notes.notes(planId: plan.id).isEmpty)
        #expect(try await analyses.analysis(runId: "r1") == analysis)
    }

    @Test func noPromptColumnsAndNoCoordinates() async throws {
        let columns = try await provider.writer.read { db in try db.columns(in: "coach_note").map(\.name) }
        #expect(columns == [
            "planId", "sessionId", "runId", "createdAt", "source", "provider", "modelTag", "headline", "observation", "versusPlan",
            "programStatus", "nextStep", "verdict", "flags", "inputHash", "analysisVersion", "factsLevel",
        ])
        #expect(!columns.contains { $0.localizedCaseInsensitiveContains("prompt") || $0.localizedCaseInsensitiveContains("output") })
        let analysisColumns = try await provider.writer.read { db in try db.columns(in: "workout_analysis").map(\.name) }
        #expect(analysisColumns == ["runId", "computedAt", "schemaVersion", "json"])

        // Every key of the stored JSON: no coordinates and no sample timestamps.
        for scenario in FakeWorkoutDetailScenario.allCases {
            let analysis = WorkoutAnalyzer.analyze(FakeWorkoutDetailSource.series(scenario, runId: "run-\(scenario)", start: .distantPast), computedAt: .distantPast)
            try await analyses.save(analysis)
            let json = try #require(try await provider.writer.read { db in
                try String.fetchOne(db, sql: "SELECT json FROM workout_analysis WHERE runId = ?", arguments: ["run-\(scenario)"])
            })
            let keys = Self.keys(in: try JSONSerialization.jsonObject(with: Data(json.utf8)))
            for banned in ["latitude", "longitude", "coordinate", "location", "timestamp", "t", "samples", "route", "start", "end", "date"] {
                #expect(!keys.contains(banned), "\(banned) in \(scenario)")
            }
        }
    }

    @Test func migrationsRunOnceAndLeaveEarlierTablesAlone() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("db-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try DatabaseProvider.onDisk(directory: directory)
        try await GRDBPlanRepository(database: first, clock: SystemClock()).save(plan)
        try await GRDBCoachNoteRepository(database: first).save(note())
        let second = try DatabaseProvider.onDisk(directory: directory)
        let applied = try await second.writer.read { db in try PlanDatabaseMigrations.migrator.appliedMigrations(db) }
        #expect(applied == ["v1_plan", "v2_llm_usage", "v3_coach_note", "v4_workout_analysis"])
        #expect(try await GRDBCoachNoteRepository(database: second).note(planId: plan.id, sessionId: "2026-10-12") == note())
        #expect(await GRDBPlanRepository(database: second, clock: SystemClock()).loadActive() == plan)
        let tables = try await second.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb%' AND name NOT LIKE 'sqlite%' ORDER BY name")
        }
        #expect(tables == ["coach_note", "llm_usage", "plan", "plan_edit", "plan_segment", "plan_session", "plan_week", "workout_analysis"])
    }

    private static func keys(in object: Any) -> Set<String> {
        if let dictionary = object as? [String: Any] {
            return Set(dictionary.keys).union(dictionary.values.flatMap { keys(in: $0) })
        }
        if let array = object as? [Any] { return Set(array.flatMap { keys(in: $0) }) }
        return []
    }
}

@Suite("Fake workout detail")
struct FakeWorkoutDetailTests {
    @Test func tempoMatchesScenarioA() throws {
        let analysis = WorkoutAnalyzer.analyze(FakeWorkoutDetailSource.series(.tempo, runId: "r", start: .distantPast), computedAt: .distantPast)
        #expect(abs(analysis.totals.movingSeconds - 1_716) < 1e-6 && analysis.totals.distanceKm == 5)
        #expect(analysis.splits.map { whole($0.paceSecPerKm) } == [390, 312, 308, 306, 400])
        #expect(analysis.splits.map { whole($0.avgHr ?? 0) } == [135, 158, 164, 166, 142])
        #expect(analysis.maxHr == 170)
        #expect(whole(try #require(analysis.avgHr)) == 152)
        #expect((analysis.elevationGainM ?? 0) > 0 && (analysis.elevationLossM ?? 0) > 0)
    }

    @Test func scenarios() throws {
        func analyze(_ scenario: FakeWorkoutDetailScenario) -> WorkoutAnalysis {
            WorkoutAnalyzer.analyze(FakeWorkoutDetailSource.series(scenario, runId: "r", start: .distantPast), computedAt: .distantPast)
        }
        #expect(analyze(.noHr).avgHr == nil && analyze(.noHr).hrHistogram.isEmpty)
        let paused = analyze(.paused)
        #expect(paused.totals.pauseCount == 2 && abs(paused.totals.pausedSeconds - 95) < 1e-6 && abs(paused.totals.movingSeconds - 1_716) < 1e-6)
        #expect(analyze(.laps).laps.count == 5)
        let drift = analyze(.easyDrift)
        #expect(drift.totals.distanceKm == 8 && drift.elevationGainM == nil)
        #expect(HeartRateDrift.measure(drift, type: .easy)?.band == .high)
    }

    @Test func flatAndTempoVaried() throws {
        func analyze(_ scenario: FakeWorkoutDetailScenario) -> WorkoutAnalysis {
            WorkoutAnalyzer.analyze(FakeWorkoutDetailSource.series(scenario, runId: "r", start: .distantPast), computedAt: .distantPast)
        }
        let flat = analyze(.flat)
        #expect(flat.splits.count == 6 && abs(flat.totals.distanceKm - 5.7) < 1e-6)
        #expect(flat.splits.allSatisfy { Int($0.paceSecPerKm.rounded()) == 360 && Int(($0.avgHr ?? 0).rounded()) == 158 })
        #expect(flat.maxHr == 172)
        #expect(flat.flatSeries)
        #expect(!analyze(.tempoVaried).flatSeries)
        #expect(analyze(.tempoVaried) == analyze(.tempo))

        // The diagnostic never reaches findings, verdicts, facts or the stored analysis.
        let session = PlannedSession(
            date: LocalDate(year: 2026, month: 10, day: 12), type: .tempo, name: "Tempo run", distanceKm: 6.0, estimatedMinutes: 36,
            effort: "Comfortably hard",
            segments: [
                Segment(label: "Warm-up", detail: "Easy jog", distanceKm: 1.5),
                Segment(label: "Tempo", detail: "3 km continuous, comfortably hard", distanceKm: 3.0),
                Segment(label: "Cool-down", detail: "Easy jog", distanceKm: 1.5),
            ],
            note: nil
        )
        let run = CompletedRun(id: "r", localDate: session.date, distanceKm: 5.7, durationSeconds: flat.totals.movingSeconds)
        let review = WorkoutReview(session: session, run: run, analysis: flat, profile: FakeHeartRateProfile.profile)
        #expect(!Findings.make(review).contains { $0.text.lowercased().contains("flat") })
        let stored = String(decoding: try JSONEncoder().encode(flat), as: UTF8.self)
        #expect(!stored.contains("flatSeries"))
        let debug = try #require(WorkoutNoteDebugJSON.analysis(flat))
        #expect(debug.contains("\"flatSeries\" : true"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(WorkoutAnalysis.self, from: Data(debug.utf8)) == flat)
    }

    @Test func withoutAScenarioEachRunGetsAnEvenEffort() async throws {
        let plan = SeedPlan.plan(createdAt: .distantPast)
        let run = RunSummary(id: "fake-2026-10-14", startDate: .distantPast, distanceMeters: 4_275, durationSeconds: 1_539, averageHeartRate: 139, maxHeartRate: 158)
        let source = FakeWorkoutDetailSource(scenario: nil, runs: { [run] }, activePlan: { plan }, highHeartRate: true)
        let analysis = WorkoutAnalyzer.analyze(try await source.detail(runId: run.id), computedAt: .distantPast)
        #expect(abs(analysis.totals.distanceKm - 4.275) < 1e-9)
        #expect(whole(try #require(analysis.avgHr)) == 153)
    }
}

/// Half up, like the analysis texts.
private func whole(_ value: Double) -> Int { Int(value.rounded(.toNearestOrAwayFromZero)) }
