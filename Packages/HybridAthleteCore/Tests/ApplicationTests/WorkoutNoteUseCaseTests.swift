import Foundation
import Testing
import Application
import Domain

// MARK: Fakes

actor CountingDetailSource: WorkoutDetailSource {
    private(set) var calls = 0
    var error: HealthDataError?
    let series: WorkoutDetailSeries

    init(error: HealthDataError? = nil) {
        self.error = error
        // 5.0 km at 6:00 /km, no heart rate or route.
        series = WorkoutDetailSeries(
            runId: "run-a",
            meta: WorkoutMeta(distanceMeters: 5_000, elapsedSeconds: 1_800, start: .distantPast, sourceLabel: "WorkOutdoors"),
            distance: DistanceTimeline(points: [DistancePoint(t: 0, meters: 0), DistancePoint(t: 1_800, meters: 5_000)], source: .samples)
        )
    }

    func detail(runId: String) async throws -> WorkoutDetailSeries {
        calls += 1
        if let error { throw error }
        return series
    }
}

actor MemoryAnalyses: WorkoutAnalysisRepository {
    private(set) var stored: [String: WorkoutAnalysis] = [:]

    init(_ analyses: [WorkoutAnalysis] = []) {
        stored = Dictionary(analyses.map { ($0.runId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func analysis(runId: String) async throws -> WorkoutAnalysis? { stored[runId] }
    func save(_ analysis: WorkoutAnalysis) async throws { stored[analysis.runId] = analysis }
    func delete(runId: String) async throws { stored[runId] = nil }
}

actor MemoryNotes: CoachNoteRepository {
    private(set) var stored: [String: SavedCoachNote] = [:]

    func note(planId: String, sessionId: String) async throws -> SavedCoachNote? { stored[sessionId] }
    func save(_ note: SavedCoachNote) async throws { stored[note.sessionId] = note }
    func notes(planId: String) async throws -> [SavedCoachNote] { Array(stored.values) }
    func delete(planId: String, sessionId: String) async throws { stored[sessionId] = nil }
}

/// Answers from a script, one entry per attempt, and keeps what it was sent.
actor ScriptedCoaching: CoachingModel {
    enum Answer {
        case note(CoachNote)
        case failure(any Error)
    }

    private var script: [Answer]
    private(set) var prompts: [Prompt] = []
    private(set) var purposes: [LLMCallPurpose] = []
    private(set) var models: [ModelChoice] = []

    init(_ script: [Answer]) {
        self.script = script
    }

    func writeWorkoutNote(_ prompt: Prompt, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        prompts.append(prompt)
        purposes.append(purpose)
        models.append(model)
        let answer = script.isEmpty ? .note(NoteFixture.good) : script.removeFirst()
        switch answer {
        case .note(let note):
            return CoachNoteResult(note: note, usage: LLMUsage(latencyMs: 1), promptText: prompt.fullText, model: model)
        case .failure(let error):
            throw error
        }
    }
}

private struct ScriptedAvailability: ModelAvailabilityChecker {
    var available: Set<ModelChoice> = [.onDevice]
    var needsKey: Set<ModelChoice> = []

    func status(for model: ModelChoice) async -> ModelStatus {
        if needsKey.contains(model) { return ModelStatus(availability: .needsAPIKey) }
        return ModelStatus(availability: available.contains(model) ? .available : .notReady, contextSize: 4_096)
    }
}

private actor SettingsStore: LabSettingsStore {
    var settings: LabSettings

    init(_ preference: CoachModelPreference) {
        settings = LabSettings(coachModelPreference: preference)
    }

    func load() async -> LabSettings { settings }
    func save(_ settings: LabSettings) async { self.settings = settings }
}

private actor StaticSnapshotCache: SnapshotCache {
    let snapshot: CachedSnapshot?
    init(_ snapshot: CachedSnapshot?) { self.snapshot = snapshot }
    func load() async -> CachedSnapshot? { snapshot }
    func save(_ snapshot: CachedSnapshot) async throws {}
}

enum NoteFixture {
    /// No numbers, so it passes the guard for any facts.
    static let good = CoachNote(
        headline: "Steady and controlled", howItWent: "A controlled run.", versusPlan: "The blocks matched the plan.",
        programStatus: "You are following the program.", nextStep: "Keep the next run easy."
    )
    static let invented = CoachNote(
        headline: "Big day", howItWent: "You ran 9.5 km.", versusPlan: "Fine.", programStatus: "Fine.", nextStep: "Rest."
    )

    /// Wed 28 Oct 2026, 09:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_793_178_000)

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// The calendar fixture with the tempo session on Mon 12 Oct.
    static let plan: TrainingPlan = {
        let sessions = CalendarPlanFixture.plan.sessions.map { $0.date == WorkoutNoteFixture.tempoSession.date ? WorkoutNoteFixture.tempoSession : $0 }
        return CalendarPlanFixture.plan.replacingSessions(sessions)
    }()

    static let runs = [WorkoutNoteFixture.tempoRun]
}

/// Everything around GenerateDetailedCoachNote, in memory.
private struct NoteHarness {
    let source: CountingDetailSource
    let analyses: MemoryAnalyses
    let notes = MemoryNotes()
    let coaching: ScriptedCoaching
    let generate: GenerateDetailedCoachNote
    let prepare: PrepareWorkoutNote

    init(
        script: [ScriptedCoaching.Answer] = [],
        preference: CoachModelPreference = .model(.onDevice),
        availability: ScriptedAvailability = ScriptedAvailability(),
        cached: [WorkoutAnalysis] = [WorkoutNoteFixture.tempoAnalysis],
        sourceError: HealthDataError? = nil,
        recovery: CachedRecovery? = nil
    ) {
        source = CountingDetailSource(error: sourceError)
        analyses = MemoryAnalyses(cached)
        coaching = ScriptedCoaching(script)
        let clock = FakeClock(NoteFixture.now)
        prepare = PrepareWorkoutNote(
            analyze: AnalyzeWorkout(source: source, analyses: analyses, clock: clock),
            build: BuildWorkoutNoteRequest(
                profile: { WorkoutNoteFixture.profile },
                sleep: FakeSleepCache(),
                recovery: FakeRecoveryCache(recovery),
                analyses: analyses,
                clock: clock,
                calendar: NoteFixture.utc
            )
        )
        generate = GenerateDetailedCoachNote(
            prepare: prepare,
            write: WriteWorkoutNote(coaching: coaching, availability: availability, settings: SettingsStore(preference)),
            notes: notes,
            clock: clock
        )
    }

    func run(force: Bool = false, sessionId: String = "2026-10-12") async throws -> CoachNoteOutcome {
        try await generate.execute(plan: NoteFixture.plan, runs: NoteFixture.runs, sessionId: sessionId, force: force)
    }
}

private extension CoachNoteOutcome {
    var saved: SavedCoachNote? {
        if case .note(let note) = self { return note }
        return nil
    }
}

// MARK: Tests

@Suite("Coach note chain")
struct CoachNoteChainTests {
    @Test func aModelNoteThatPassesTheGuardIsStored() async throws {
        let harness = NoteHarness(script: [.note(NoteFixture.good)])
        let saved = try #require(try await harness.run().saved)
        #expect(saved.source == .model && saved.modelTag == "onDevice" && saved.provider == .apple)
        #expect(saved.note == NoteFixture.good && saved.factsLevel == 0 && saved.fallback == nil)
        #expect(saved.verdict == .onTrack && saved.runId == "run-a" && saved.analysisVersion == 2)
        #expect(await harness.coaching.purposes == [.workoutNote])
        #expect(await harness.notes.stored["2026-10-12"] == saved)
        #expect(saved.writerName == "Apple on-device")
    }

    @Test func anInvalidNoteIsRetriedOnceWithTheIssues() async throws {
        let harness = NoteHarness(script: [.note(NoteFixture.invented), .note(NoteFixture.good)])
        let saved = try #require(try await harness.run().saved)
        #expect(saved.source == .model)
        let prompts = await harness.coaching.prompts
        #expect(prompts.count == 2)
        #expect(!prompts[0].text.contains("Fix these problems"))
        #expect(prompts[1].text.contains("\n\nFix these problems:\nThese numbers are not in the facts: 9.5."))
        #expect(await harness.coaching.purposes == [.workoutNote, .workoutNote])
    }

    @Test func twoInvalidNotesGiveTheRuleBasedNote() async throws {
        let harness = NoteHarness(script: [.note(NoteFixture.invented), .note(NoteFixture.invented)])
        let saved = try #require(try await harness.run().saved)
        #expect(saved.source == .rules && saved.modelTag == "rules-v1" && saved.provider == nil && saved.factsLevel == nil)
        #expect(saved.fallback == .guardRejected)
        #expect(saved.fallback?.message == "The model's note didn't match your data, so a rule-based note is shown.")
        #expect(saved.note.headline == "Right on plan")
        #expect(await harness.coaching.prompts.count == 2)
    }

    @Test(arguments: [
        (LLMError.unavailable(.notReady), CoachNoteFallback.modelUnavailable),
        (.quotaLimitReached(resetDate: nil), .modelUnavailable),
        (.spendLimit("This run could cost up to $0.30, above your $0.25 per-run limit."), .spendLimit),
        (.unavailable(.needsAPIKey), .claudeNotSetUp),
        (.spendLimit(SpendGate.consentText), .claudeNotSetUp),
        (.networkUnavailable, .modelUnavailable),
        (.timedOut, .modelUnavailable),
        (.guardrailViolation, .modelUnavailable),
        (.billingProblem, .modelUnavailable),
    ])
    func modelErrorsGoStraightToTheRules(error: LLMError, fallback: CoachNoteFallback) async throws {
        let harness = NoteHarness(script: [.failure(error)])
        let saved = try #require(try await harness.run().saved)
        #expect(saved.source == .rules && saved.fallback == fallback)
        #expect(await harness.coaching.prompts.count == 1)
    }

    @Test func messages() {
        #expect(CoachNoteFallback.claudeNotSetUp.message == "Claude isn't set up. Showing a rule-based note.")
        #expect(CoachNoteFallback.spendLimit.message == "Your spend limit is reached. Showing a rule-based note.")
        #expect(CoachNoteFallback.modelUnavailable.message == "The AI model isn't available right now. Showing a rule-based note.")
    }

    @Test func claudeWithoutAKeyIsNeverCalled() async throws {
        let haiku = ModelChoice.anthropic(.haiku55)
        let harness = NoteHarness(preference: .model(haiku), availability: ScriptedAvailability(available: [], needsKey: [haiku]))
        let saved = try #require(try await harness.run().saved)
        #expect(saved.fallback == .claudeNotSetUp)
        #expect(await harness.coaching.prompts.isEmpty)
    }

    @Test func automaticTriesPrivateCloudThenOnDevice() async throws {
        let onDevice = NoteHarness(preference: .automatic, availability: ScriptedAvailability(available: [.onDevice]))
        #expect(try await onDevice.run().saved?.modelTag == "onDevice")
        let cloud = NoteHarness(preference: .automatic, availability: ScriptedAvailability(available: [.privateCloud(reasoning: .light), .onDevice]))
        #expect(try await cloud.run().saved?.modelTag == "pcc.light")
        #expect(try await cloud.run(force: true).saved?.writerName == "Apple Private Cloud")
        // Nothing available: the rules, without an error message.
        let none = NoteHarness(preference: .automatic, availability: ScriptedAvailability(available: []))
        let saved = try #require(try await none.run().saved)
        #expect(saved.source == .rules && saved.fallback == nil)
        #expect(await none.coaching.prompts.isEmpty)
    }

    @Test func rulesPreferenceNeverCallsAModel() async throws {
        let harness = NoteHarness(preference: .ruleBased)
        #expect(try await harness.run().saved?.source == .rules)
        #expect(await harness.coaching.prompts.isEmpty)
    }

    @Test func cancellationSavesNothing() async {
        let harness = NoteHarness(script: [.failure(LLMError.cancelled)])
        await #expect(throws: CancellationError.self) { try await harness.run() }
        #expect(await harness.notes.stored.isEmpty)
    }

    @Test func anUnexpectedErrorPropagates() async {
        struct Boom: Error {}
        let harness = NoteHarness(script: [.failure(Boom())])
        await #expect(throws: Boom.self) { try await harness.run() }
        #expect(await harness.notes.stored.isEmpty)
    }

    @Test func aCurrentNoteIsReusedAndRegenerateReplacesIt() async throws {
        let harness = NoteHarness(script: [.note(NoteFixture.good), .note(NoteFixture.invented), .note(NoteFixture.invented)])
        let first = try #require(try await harness.run().saved)
        #expect(try await harness.run().saved == first)
        #expect(await harness.coaching.prompts.count == 1)
        let replaced = try #require(try await harness.run(force: true).saved)
        #expect(replaced.source == .rules)
        #expect(await harness.notes.stored["2026-10-12"] == replaced)
    }

    @Test func aNoteForAnotherRunIsStale() async throws {
        let harness = NoteHarness()
        let first = try #require(try await harness.run().saved)
        let other = SavedCoachNote(
            planId: first.planId, sessionId: first.sessionId, runId: "older-run", createdAt: first.createdAt, source: .model,
            provider: .apple, modelTag: "onDevice", note: first.note, verdict: first.verdict, inputHash: first.inputHash, factsLevel: 0
        )
        #expect(other.isStale(runId: "run-a", inputHash: first.inputHash))
        #expect(!first.isStale(runId: "run-a", inputHash: first.inputHash))
        try await harness.notes.save(other)
        #expect(try await harness.run().saved?.runId == "run-a")
    }

    @Test func notCompletedSessionsNeverGetANote() async throws {
        let harness = NoteHarness()
        #expect(try await harness.run(sessionId: "2026-10-21") == .notCompleted)
        #expect(try await harness.run(sessionId: "nope") == .notCompleted)
        #expect(await harness.coaching.prompts.isEmpty)
    }
}

@Suite("Workout analysis use cases")
struct AnalyzeWorkoutTests {
    @Test func theAnalysisIsCachedAfterTheFirstRead() async throws {
        let harness = NoteHarness(cached: [])
        _ = try await harness.run()
        _ = try await harness.run(force: true)
        #expect(await harness.source.calls == 1)
        let analysis = try #require(await harness.analyses.stored["run-a"])
        #expect(analysis.totals.distanceKm == 5 && analysis.splits.count == 5 && analysis.sourceLabel == "WorkOutdoors")
    }

    @Test func aLockedReadWaitsAndStoresNothing() async throws {
        let harness = NoteHarness(cached: [], sourceError: .locked)
        #expect(try await harness.run() == .waitingForUnlock)
        #expect(await harness.analyses.stored.isEmpty)
        #expect(await harness.notes.stored.isEmpty)
    }

    @Test func anUnreadableDetailFallsBackToTheRunTotals() async throws {
        let harness = NoteHarness(cached: [], sourceError: .failed)
        let saved = try #require(try await harness.run().saved)
        #expect(saved.verdict == .onTrack)
        // Not cached, so the next refresh tries Health again.
        #expect(await harness.analyses.stored.isEmpty)
    }

    @Test func runsWithoutHeartRateSkipTheHeartRateFindings() async throws {
        let harness = NoteHarness(cached: [])
        guard case .ready(let prepared) = try await harness.prepare.execute(plan: NoteFixture.plan, runs: NoteFixture.runs, sessionId: "2026-10-12") else {
            Issue.record("not ready")
            return
        }
        #expect(!prepared.facts.text.contains("Average heart rate"))
        #expect(!prepared.facts.text.contains("Time in heart rate zones"))
        #expect(prepared.facts.text.contains("F2. Average pace 6:00 /km over 30:00 moving time."))
    }

    @Test func cachedOnlyNeverReadsHealth() async throws {
        let harness = NoteHarness(cached: [])
        let result = try await harness.prepare.execute(plan: NoteFixture.plan, runs: NoteFixture.runs, sessionId: "2026-10-12", cachedOnly: true)
        #expect(result == .waitingForUnlock)
        #expect(await harness.source.calls == 0)
    }

    @Test func recoveryIsTheNightBeforeTheRun() async throws {
        let nights = (5...12).map { HRVNight(wakeDate: WorkoutNoteFixture.day(10, $0), meanMs: $0 == 12 ? 47 : 50, sampleCount: 4, windowKind: .sleep, sourceLabel: "Apple Watch") }
        let recovery = CachedRecovery(generatedAt: NoteFixture.now, hrv: nights, restingHr: [RestingHRDay(date: WorkoutNoteFixture.day(10, 11), bpm: 50, sourceLabel: "Apple Watch")])
        let harness = NoteHarness(recovery: recovery)
        guard case .ready(let prepared) = try await harness.prepare.execute(plan: NoteFixture.plan, runs: NoteFixture.runs, sessionId: "2026-10-12") else {
            Issue.record("not ready")
            return
        }
        #expect(prepared.request.recovery.hrv?.valueMs == 47)
        #expect(prepared.request.recovery.hrv?.deltaPercent == -6)
        // No resting heart rate on the run day: the day before.
        #expect(prepared.request.recovery.restingHr?.bpm == 50)
        #expect(prepared.request.recovery.sleep == nil)
        #expect(prepared.facts.recovery == ["HRV: 47 ms (\u{2212}6% vs last 7 nights)", "Resting heart rate: 50 bpm"])
    }

    @Test func theProgramComesFromThePlan() async throws {
        let harness = NoteHarness()
        guard case .ready(let prepared) = try await harness.prepare.execute(plan: NoteFixture.plan, runs: CalendarPlanFixture.runs.map {
            $0.localDate == WorkoutNoteFixture.day(10, 12) ? WorkoutNoteFixture.tempoRun : $0
        }, sessionId: "2026-10-12") else {
            Issue.record("not ready")
            return
        }
        let program = prepared.request.program
        // 6 of 7 due sessions done (21 Oct has no run); week 3: 26 Oct 6.2 km of 6.0 + 6.5 + 10.0.
        #expect(program.completedCount == 6 && program.dueCount == 7 && program.adherencePercent == 86)
        #expect(program.weekIndex == 3 && program.kmPlannedThisWeek == 22.5 && abs(program.kmDoneThisWeek - 6.2) < 1e-9)
        #expect(program.recent.map(\.date) == [WorkoutNoteFixture.day(10, 26), WorkoutNoteFixture.day(10, 23), WorkoutNoteFixture.day(10, 19)])
        // 23 Oct: 7.0 of 10.0 km, distance only: off plan.
        #expect(program.recent[1].verdict == .offPlan)
        #expect(program.next?.date == WorkoutNoteFixture.day(10, 30))
    }
}

@Suite("Heart-rate profile from the caches")
struct LoadHeartRateProfileTests {
    private func snapshot(observed: Double?, age: Int?, resting: Double?) -> CachedSnapshot {
        let asOf = NoteFixture.now
        return CachedSnapshot(
            generatedAt: asOf,
            profile: CachedSection(value: ProfileSummary(ageYears: age, biologicalSex: nil), asOf: asOf),
            restingHeartRate: resting.map {
                CachedSection(value: RestingHeartRateSummary(latest: HealthSample(value: $0, unit: "bpm", date: asOf, sourceName: "Watch"), average30Days: nil, sampleCount30Days: 1), asOf: asOf)
            },
            workouts: CachedSection(value: WorkoutsSummary(
                totalCount: 0, runCount: 0, runHeartRateAverage: nil, personalRecords: [], volume: .none, observedMaxHr: observed
            ), asOf: asOf)
        )
    }

    @Test func observedMaxAndLatestResting() async {
        let recovery = CachedRecovery(generatedAt: NoteFixture.now, hrv: [], restingHr: [
            RestingHRDay(date: WorkoutNoteFixture.day(10, 26), bpm: 52, sourceLabel: "W"),
            RestingHRDay(date: WorkoutNoteFixture.day(10, 27), bpm: 49, sourceLabel: "W"),
        ])
        let load = LoadHeartRateProfile(snapshots: StaticSnapshotCache(snapshot(observed: 182, age: 32, resting: 55)), recovery: FakeRecoveryCache(recovery))
        #expect(await load.execute() == HeartRateProfile(maxHr: 182, restingHr: 49))
    }

    @Test func ageFallbackAndUnknown() async {
        let fallback = LoadHeartRateProfile(snapshots: StaticSnapshotCache(snapshot(observed: nil, age: 32, resting: 55)), recovery: FakeRecoveryCache())
        #expect(await fallback.execute() == HeartRateProfile(maxHr: 188, restingHr: 55))
        let unknown = LoadHeartRateProfile(snapshots: StaticSnapshotCache(snapshot(observed: nil, age: nil, resting: 55)), recovery: FakeRecoveryCache())
        #expect(await unknown.execute() == nil)
    }
}
