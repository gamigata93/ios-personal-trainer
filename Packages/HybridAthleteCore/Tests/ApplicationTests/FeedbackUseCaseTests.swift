import Foundation
import Testing
import Domain
@testable import Application

/// Fakes for the feedback use cases: memory repositories, an adjusting model
/// with canned answers, and an availability checker.
private actor MemoryFeedback: WorkoutFeedbackRepository {
    var stored: [String: WorkoutFeedback] = [:]

    func save(_ feedback: WorkoutFeedback) async throws { stored[feedback.workoutId] = feedback }
    func feedback(workoutId: String) async throws -> WorkoutFeedback? { stored[workoutId] }
    func feedback(since from: LocalDate) async throws -> [WorkoutFeedback] { stored.values.filter { $0.localDate >= from } }
}

private actor MemoryAdjustments: PlanAdjustmentRepository {
    var saved: [StoredAdjustment] = []

    func savePending(planId: String, adjustment: PlanAdjustment) async throws -> StoredAdjustment {
        saved = saved.map { $0.status == .pending ? StoredAdjustment(id: $0.id, planId: $0.planId, createdAt: $0.createdAt, status: .dismissed, adjustment: $0.adjustment) : $0 }
        let stored = StoredAdjustment(id: Int64(saved.count + 1), planId: planId, createdAt: .distantPast, status: .pending, adjustment: adjustment)
        saved.append(stored)
        return stored
    }

    func pending(planId: String) async throws -> StoredAdjustment? { saved.last { $0.status == .pending } }
    func apply(id: Int64) async throws {}
    func dismiss(id: Int64) async throws {}
    func undo(id: Int64) async throws {}
}

private actor CannedAdjuster: PlanAdjustingModel {
    let answers: [Result<AdjustmentDraft, LLMError>]
    private(set) var calls: [(ModelChoice, Prompt)] = []

    init(_ answers: [Result<AdjustmentDraft, LLMError>]) {
        self.answers = answers
    }

    func adjustPlan(_ prompt: Prompt, model: ModelChoice, purpose: LLMCallPurpose) async throws -> AdjustmentDraftResult {
        calls.append((model, prompt))
        let answer = answers[min(calls.count - 1, answers.count - 1)]
        switch answer {
        case .success(let draft): return AdjustmentDraftResult(draft: draft, usage: LLMUsage(.zero, latencyMs: 1, costMicros: nil), promptText: prompt.fullText)
        case .failure(let error): throw error
        }
    }
}

private struct Availability: ModelAvailabilityChecker {
    let available: Set<ModelChoice>

    func status(for model: ModelChoice) async -> ModelStatus {
        ModelStatus(availability: available.contains(model) ? .available : .notReady)
    }
}

private struct WednesdayClock: Clock {
    /// Wed 28 Oct 2026, 09:00 UTC.
    func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
}

@Suite("Feedback use cases")
struct FeedbackUseCaseTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func day(_ month: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: month, day: day) }

    /// Mon/Wed/Fri plan: easy runs on Wednesdays, with lower body strength on Wed 28 Oct.
    private static let plan: TrainingPlan = {
        let start = day(10, 26)
        let sessions = [(0, SessionType.tempo, 6.0), (2, .easy, 6.5), (4, .long, 10.0), (7, .tempo, 6.0), (9, .easy, 6.0), (11, .long, 11.0)]
            .map { offset, type, km in
                PlannedSession(date: start.adding(days: offset), type: type, name: "\(type.rawValue)", distanceKm: km, estimatedMinutes: Int(km * 6), effort: "x", segments: [], note: nil)
            }
        let strength = [StrengthContentBuilder.session(date: day(10, 28), focus: .lowerBody, minutes: 30, phase: .base, variant: .a)]
        return TrainingPlan(
            id: "p", createdAt: .distantPast, generatedBy: "test", planKind: .tenK,
            race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: day(12, 6), trainingDays: [.monday, .wednesday, .friday]),
            planStart: start,
            weeks: [
                PlanWeek(index: 1, startDate: start, phase: .base, targetKm: 22.5, sessions: [], strength: []),
                PlanWeek(index: 2, startDate: start.adding(days: 7), phase: .base, targetKm: 23, sessions: [], strength: []),
            ]
        ).replacing(sessions: sessions, strength: strength)
    }()

    private static let workouts = CompletedRunsResult(
        runs: [
            CompletedRun(id: "r24", localDate: day(10, 24), distanceKm: 5, durationSeconds: 1_800),
            CompletedRun(id: "r26", localDate: day(10, 26), distanceKm: 6.2, durationSeconds: 2_040),
            CompletedRun(id: "r28", localDate: day(10, 28), distanceKm: 3, durationSeconds: 900),
        ],
        strength: [CompletedStrength(id: "s27", localDate: day(10, 27), durationSeconds: 1_920, kind: .functionalStrength)],
        asOf: nil, source: .fresh
    )

    private static func painTrigger() -> AdjustmentTrigger {
        let report = AreaReport(area: .knee, side: .left, kind: .pain, level: .moderate)
        let feedback = WorkoutFeedback(workoutId: "r26", workoutKind: .run, localDate: day(10, 26), status: .reported, areas: [report], recordedAt: .distantPast)
        return AdjustmentTrigger(feedback: feedback, report: report, reason: .pain)
    }

    @Test func pendingAsksAboutTheLastThreeDaysOnly() async throws {
        let repo = MemoryFeedback()
        let pending = PendingFeedback(feedback: repo, clock: WednesdayClock(), calendar: Self.utc)
        // 24 Oct is outside the 3 days (26, 27, 28); newest first.
        let first = await pending.execute(Self.workouts)
        #expect(first.map(\.id) == ["r28", "s27", "r26"])
        #expect(first.map(\.title) == ["Run · Wed 28 Oct", "Functional strength · Tue 27 Oct", "Run · Mon 26 Oct"])
        #expect(first.map(\.detail) == ["3.0 km · 15 min", "32 min", "6.2 km · 34 min"])
        // An answer (or a skip) is never asked again.
        try await repo.save(WorkoutFeedback(workoutId: "r28", workoutKind: .run, localDate: Self.day(10, 28), status: .skipped, recordedAt: .distantPast))
        #expect(await pending.execute(Self.workouts).map(\.id) == ["s27", "r26"])
    }

    @Test func savingReturnsTheTrigger() async throws {
        let repo = MemoryFeedback()
        let save = SaveWorkoutFeedback(feedback: repo)
        let ache = AreaReport(area: .calf, side: .left, kind: .ache, level: .moderate)
        let first = WorkoutFeedback(workoutId: "r24", workoutKind: .run, localDate: Self.day(10, 24), status: .reported, areas: [ache], recordedAt: .distantPast)
        #expect(try await save.execute(first) == nil)
        let second = WorkoutFeedback(workoutId: "r26", workoutKind: .run, localDate: Self.day(10, 26), status: .reported, areas: [ache], recordedAt: .distantPast)
        #expect(try await save.execute(second)?.reason == .repeatedAche)
        #expect(await repo.stored.count == 2)
    }

    private func suggest(
        _ adjuster: CannedAdjuster, models: [ModelChoice], available: Set<ModelChoice> = [.onDevice], adjustments: MemoryAdjustments = MemoryAdjustments()
    ) -> SuggestPlanAdjustment {
        SuggestPlanAdjustment(
            adjusting: adjuster, availability: Availability(available: available), adjustments: adjustments,
            loadFeedback: LoadWorkoutFeedback(feedback: MemoryFeedback()), models: models, clock: WednesdayClock(), calendar: Self.utc
        )
    }

    private var easierDraft: AdjustmentDraft {
        // The 3 km run on 28 Oct is under 60% of 6.5 km, so today is not done and the window starts today.
        AdjustmentDraft(
            runs: [
                AdjustmentDraft.Run(date: Self.day(10, 28), type: .easy, distanceKm: 5),
                AdjustmentDraft.Run(date: Self.day(10, 30), type: .easy, distanceKm: 8),
                AdjustmentDraft.Run(date: Self.day(11, 2), type: .easy, distanceKm: 5),
                AdjustmentDraft.Run(date: Self.day(11, 4), type: .easy, distanceKm: 5),
                AdjustmentDraft.Run(date: Self.day(11, 6), type: .easy, distanceKm: 9),
            ],
            strength: [AdjustmentDraft.Strength(date: Self.day(10, 28), focus: .mobility, minutes: 20)],
            reason: "Easier days while the knee settles."
        )
    }

    @Test func aModelWritesTheSuggestion() async throws {
        let adjuster = CannedAdjuster([.success(easierDraft)])
        let stored = try #require(try await suggest(adjuster, models: [.privateCloud(reasoning: .light), .onDevice])
            .execute(plan: Self.plan, workouts: Self.workouts, trigger: Self.painTrigger()))
        // PCC is unavailable, so on-device answers.
        #expect(await adjuster.calls.map(\.0) == [.onDevice])
        #expect(stored.adjustment.writtenBy == "Apple on-device")
        #expect(stored.adjustment.reason == "Easier days while the knee settles.")
        #expect(stored.adjustment.window == AdjustmentWindow(start: Self.day(10, 28), end: Self.day(11, 8)))
        #expect(stored.adjustment.afterStrength.map(\.name) == ["Strength: Mobility A"])
        #expect(stored.status == .pending)
        let prompt = try #require(await adjuster.calls.first?.1)
        #expect(prompt.facts.first == "Trigger: Mon 26 Oct run: pain, left knee, moderate.")
    }

    @Test func anInvalidAnswerIsRetriedOnceThenTheRulesWrite() async throws {
        let tooMuch = AdjustmentDraft(runs: [AdjustmentDraft.Run(date: Self.day(10, 30), type: .long, distanceKm: 50)], strength: [], reason: "More.")
        let adjuster = CannedAdjuster([.success(tooMuch)])
        let stored = try #require(try await suggest(adjuster, models: [.onDevice]).execute(plan: Self.plan, workouts: Self.workouts, trigger: Self.painTrigger()))
        let calls = await adjuster.calls
        #expect(calls.count == 2)
        #expect(calls[1].1.text.contains("Fix these problems:\n"))
        #expect(calls[1].1.text.contains("\nThe new schedule runs 50.0 km, more than the current 39.5 km."))
        #expect(stored.adjustment.writtenBy == "rules")
    }

    @Test func modelErrorsAndNoModelsGoToTheRules() async throws {
        let failing = CannedAdjuster([.failure(.timedOut)])
        let first = try await suggest(failing, models: [.onDevice]).execute(plan: Self.plan, workouts: Self.workouts, trigger: Self.painTrigger())
        #expect(await failing.calls.count == 1)
        #expect(first?.adjustment.writtenBy == "rules")
        let unused = CannedAdjuster([.success(easierDraft)])
        let second = try await suggest(unused, models: []).execute(plan: Self.plan, workouts: Self.workouts, trigger: Self.painTrigger())
        #expect(await unused.calls.isEmpty)
        #expect(second?.adjustment.writtenBy == "rules")
    }

    @Test func aNewSuggestionReplacesThePendingOne() async throws {
        let adjustments = MemoryAdjustments()
        let use = suggest(CannedAdjuster([.failure(.timedOut)]), models: [], adjustments: adjustments)
        _ = try await use.execute(plan: Self.plan, workouts: Self.workouts, trigger: Self.painTrigger())
        _ = try await use.execute(plan: Self.plan, workouts: Self.workouts, trigger: Self.painTrigger())
        #expect(await adjustments.saved.map(\.status) == [.dismissed, .pending])
    }
}
