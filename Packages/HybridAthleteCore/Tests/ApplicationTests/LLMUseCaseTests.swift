import Foundation
import Testing
import Application
import Domain

private enum Worked {
    static let request = PlanRequest(
        race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: LocalDate(year: 2026, month: 12, day: 6), trainingDays: [.monday, .wednesday, .friday]),
        fitness: FitnessSummary(weeklyKm: 18.44, longestRunKm: 17.0, avgPaceSecPerKm: 337),
        today: LocalDate(year: 2026, month: 10, day: 10),
        planKind: .tenK,
        source: .custom
    )

    /// A valid structure: 8 weeks, Mon tempo 5, Wed easy 6, Fri long 7.5, ending in taper.
    static let draft = PlanDraft(weeks: [PlanPhase.base, .base, .base, .build, .build, .peak, .peak, .taper].enumerated().map { offset, phase in
        DraftWeek(index: offset + 1, phase: phase, sessions: [
            DraftSession(weekday: .monday, type: .tempo, distanceKm: 5),
            DraftSession(weekday: .wednesday, type: .easy, distanceKm: 6),
            DraftSession(weekday: .friday, type: .long, distanceKm: 7.5),
        ])
    })

    static var validPlan: TrainingPlan { PlanDraftExpander.expand(draft, request: request, generatedBy: "on-device-v1") }

    /// A plan with a session on a Tuesday (a rest day).
    static var invalidPlan: TrainingPlan {
        var weeks = draft.weeks
        weeks[0] = DraftWeek(index: 1, phase: .base, sessions: [DraftSession(weekday: .tuesday, type: .easy, distanceKm: 5)])
        return PlanDraftExpander.expand(PlanDraft(weeks: weeks), request: request, generatedBy: "on-device-v1")
    }
}

/// Answers from a script, one per call, recording every request.
private actor ScriptedGenerator: PlanGenerator {
    enum Step { case plan(TrainingPlan), fail(any Error) }
    private var steps: [Step]
    private(set) var requests: [PlanRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    func generate(_ request: PlanRequest) async throws -> TrainingPlan {
        requests.append(request)
        let step = steps.isEmpty ? .fail(LLMError.other("no more steps")) : steps.removeFirst()
        switch step {
        case .plan(let plan): return plan
        case .fail(let error): throw error
        }
    }
}

private struct StaticGenerator: PlanGenerator {
    let plan: TrainingPlan
    func generate(_ request: PlanRequest) async throws -> TrainingPlan { plan }
}

@Suite("Plan generator decorators")
struct PlanGeneratorDecoratorTests {
    @Test func invalidThenValidRetriesWithRevisionNotes() async throws {
        let inner = ScriptedGenerator([.plan(Worked.invalidPlan), .plan(Worked.validPlan)])
        let plan = try await ValidatingPlanGenerator(inner: inner).generate(Worked.request)
        #expect(plan == Worked.validPlan)
        let requests = await inner.requests
        #expect(requests.count == 2)
        #expect(requests[0].revisionNotes.isEmpty)
        let expected = PlanValidator.violations(Worked.invalidPlan, request: Worked.request).map(\.message)
        #expect(!expected.isEmpty)
        #expect(requests[1].revisionNotes == Array(expected.prefix(8)))
    }

    @Test func invalidTwiceThrowsTheLastMessages() async {
        let inner = ScriptedGenerator([.plan(Worked.invalidPlan), .plan(Worked.invalidPlan)])
        let messages = PlanValidator.violations(Worked.invalidPlan, request: Worked.request).map(\.message)
        await #expect(throws: LLMError.invalidPlan(messages)) { try await ValidatingPlanGenerator(inner: inner).generate(Worked.request) }
        #expect(await inner.requests.count == 2)
    }

    @Test(arguments: [LLMError.unavailable(.notReady), .quotaLimitReached(resetDate: nil), .guardrailViolation, .cancelled, .networkUnavailable, .timedOut])
    func hardFailuresAreNotRetried(error: LLMError) async {
        let inner = ScriptedGenerator([.fail(error), .plan(Worked.validPlan)])
        await #expect(throws: error) { try await ValidatingPlanGenerator(inner: inner).generate(Worked.request) }
        #expect(await inner.requests.count == 1)
    }

    @Test func malformedOutputIsRetriedOnce() async throws {
        let inner = ScriptedGenerator([.fail(LLMError.malformedOutput("Week 1 uses Tuesday, which is not a training day.\nThe last week must be a taper week.")), .plan(Worked.validPlan)])
        _ = try await ValidatingPlanGenerator(inner: inner).generate(Worked.request)
        #expect(await inner.requests.last?.revisionNotes == ["Week 1 uses Tuesday, which is not a training day.", "The last week must be a taper week."])
    }

    @Test func oneAttemptDoesNotRetry() async {
        let inner = ScriptedGenerator([.plan(Worked.invalidPlan), .plan(Worked.validPlan)])
        await #expect(throws: LLMError.self) { try await ValidatingPlanGenerator(inner: inner, maxAttempts: 1).generate(Worked.request) }
        #expect(await inner.requests.count == 1)
    }

    @Test(arguments: [LLMError.networkUnavailable, .quotaLimitReached(resetDate: nil), .invalidPlan(["x"])])
    func fallbackUsesTheTemplate(error: LLMError) async throws {
        let template = StaticGenerator(plan: PlanDraftExpander.expand(Worked.draft, request: Worked.request, generatedBy: "template-v1"))
        let plan = try await FallbackPlanGenerator(primary: ScriptedGenerator([.fail(error)]), fallback: template).generate(Worked.request)
        #expect(plan.generatedBy == "template-v1")
    }

    @Test func cancellationDoesNotFallBack() async {
        let template = StaticGenerator(plan: Worked.validPlan)
        await #expect(throws: LLMError.cancelled) {
            try await FallbackPlanGenerator(primary: ScriptedGenerator([.fail(LLMError.cancelled)]), fallback: template).generate(Worked.request)
        }
    }
}

/// A drafting model that returns a fixed draft, or fails.
private struct FakeDrafting: PlanDraftingModel {
    var draft: PlanDraft = Worked.draft
    var error: LLMError?

    func draftPlan(_ request: PlanRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> PlanDraftResult {
        if let error { throw error }
        return PlanDraftResult(draft: draft, usage: LLMUsage(inputTokens: 600, outputTokens: 500, latencyMs: 2_000), promptText: "prompt")
    }
}

private actor FakeCoaching: CoachingModel {
    var failures: [ModelChoice: LLMError] = [:]
    private(set) var calls: [ModelChoice] = []

    init(failures: [ModelChoice: LLMError] = [:]) { self.failures = failures }

    func writeWorkoutNote(_ request: CoachNoteRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        calls.append(model)
        if let error = failures[model] { throw error }
        return CoachNoteResult(
            note: CoachNote(headline: "Good run", observation: "You ran 9.5 km.", nextStep: "Rest."),
            usage: LLMUsage(inputTokens: 300, outputTokens: 60, latencyMs: 1_000), promptText: "prompt", model: model
        )
    }
}

private struct FakeAvailability: ModelAvailabilityChecker {
    var unavailable: [ModelChoice: ModelAvailability] = [:]
    func status(for model: ModelChoice) async -> ModelStatus {
        ModelStatus(availability: unavailable[model] ?? .available, contextSize: 4_096)
    }
}

@Suite("Model plan generator, fallback coaching and the Lab runner")
struct ModelRunnerTests {
    @Test func modelPlanGeneratorExpandsAValidDraft() async throws {
        let plan = try await ModelPlanGenerator(drafting: FakeDrafting(), model: .privateCloud(reasoning: .moderate)).generate(Worked.request)
        #expect(plan.generatedBy == "pcc-moderate-v1")
        #expect(plan.weeks.count == 8)
    }

    @Test func aBadShapeIsMalformedOutputWithTheMessages() async {
        let short = PlanDraft(weeks: Array(Worked.draft.weeks.prefix(7)))
        await #expect(throws: LLMError.malformedOutput("The plan needs exactly 8 weeks, not 7.\nThe last week must be a taper week.")) {
            try await ModelPlanGenerator(drafting: FakeDrafting(draft: short), model: .onDevice).generate(Worked.request)
        }
    }

    @Test func coachingFallsBackFromPrivateCloudToOnDevice() async throws {
        let inner = FakeCoaching(failures: [.privateCloud(reasoning: .moderate): .networkUnavailable])
        let result = try await FallbackCoachingModel(primary: inner, fallback: inner).writeWorkoutNote(.sampleShortRun, model: .privateCloud(reasoning: .moderate), purpose: .labCoachNote)
        #expect(result.model == .onDevice)
        #expect(await inner.calls == [.privateCloud(reasoning: .moderate), .onDevice])
    }

    @Test func coachingDoesNotFallBackOnCancel() async {
        let inner = FakeCoaching(failures: [.privateCloud(reasoning: .light): .cancelled])
        await #expect(throws: LLMError.cancelled) {
            try await FallbackCoachingModel(primary: inner, fallback: inner).writeWorkoutNote(.sampleShortRun, model: .privateCloud(reasoning: .light), purpose: .labCoachNote)
        }
    }

    private func runner(drafting: FakeDrafting = FakeDrafting(), unavailable: [ModelChoice: ModelAvailability] = [:]) -> RunModelExperiment {
        RunModelExperiment(
            coaching: FakeCoaching(), drafting: drafting, availability: FakeAvailability(unavailable: unavailable),
            template: StaticGenerator(plan: Worked.validPlan)
        )
    }

    @Test func coachNoteResultCarriesSoftFlags() async {
        let result = await runner().run(.coachNote(.sampleShortRun), model: .onDevice)
        #expect(result.output == .coachNote(CoachNote(headline: "Good run", observation: "You ran 9.5 km.", nextStep: "Rest.")))
        #expect(result.softFlags == ["Numbers not in the facts: 9.5"])
        #expect(result.validityText == "1 issue")
        #expect(result.usage?.latencyMs == 1_000)
        #expect(result.experiment == "coachNote")
    }

    @Test func planDraftShowsATableAndViolationsWithoutRetrying() async throws {
        var weeks = Worked.draft.weeks
        weeks[0] = DraftWeek(index: 1, phase: .base, sessions: [DraftSession(weekday: .tuesday, type: .easy, distanceKm: 5)])
        let result = await runner(drafting: FakeDrafting(draft: PlanDraft(weeks: weeks))).run(.planDraft(Worked.request), model: .onDevice)
        #expect(result.violations == ["Week 1 uses Tuesday, which is not a training day."])
        #expect(result.validityText == "1 issue")

        let valid = await runner().run(.planDraft(Worked.request), model: .onDevice)
        guard case .planDraft(let table) = valid.output else { Issue.record("no table"); return }
        #expect(table.rows.count == 8)
        #expect(table.rows[0] == "Wk 1 · base · 18.5 km · Mon tempo 5.0, Wed easy 6.0, Fri long 7.5")
        #expect(table.comparisonLine?.hasPrefix("Weekly km, model / template: 18.5/18.5") == true)
        #expect(valid.validityText == "Valid")
    }

    @Test func unavailableModelsAreReportedAndSkipped() async {
        let lab = runner(unavailable: [.privateCloud(reasoning: .light): .notEnabledForBuild, .privateCloud(reasoning: .moderate): .notEnabledForBuild, .privateCloud(reasoning: .deep): .notEnabledForBuild])
        let result = await lab.run(.coachNote(.sampleShortRun), model: .privateCloud(reasoning: .light))
        #expect(result.error == .unavailable(.notEnabledForBuild))
        #expect(result.validityText == nil)
        #expect(result.promptText.contains("Facts:\nSession: Long run (Long run)"))
        #expect(await lab.availableModels(.apple) == [.onDevice])
        let all = await lab.execute(.coachNote(.sampleShortRun), models: await lab.availableModels(.apple))
        #expect(all.map(\.model) == [.onDevice])
    }

    @Test func errorsFromTheModel() async {
        let result = await runner(drafting: FakeDrafting(error: .contextTooLarge)).run(.planDraft(Worked.request), model: .onDevice)
        #expect(result.error == .contextTooLarge)
        #expect(result.output == nil)
    }
}

@Suite("Model error text and latest session facts")
struct LLMErrorTextTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_793_178_000) // Wed 28 Oct 2026, 09:00 UTC
    private var text: LLMErrorText {
        let now = now
        return LLMErrorText(calendar: Self.utc, locale: Locale(identifier: "en_GB"), now: { now })
    }

    @Test func messages() {
        #expect(text.message(.quotaLimitReached(resetDate: now.addingTimeInterval(3 * 3_600))) == "Today's Apple Intelligence limit was reached. It resets 12:00.")
        #expect(text.message(.quotaLimitReached(resetDate: now.addingTimeInterval(24 * 3_600))) == "Today's Apple Intelligence limit was reached. It resets tomorrow 9:00.")
        #expect(text.message(.unavailable(.notEnabledForBuild)) == ModelAvailability.notEnabledForBuild.message)
        #expect(text.message(.invalidPlan(["x"])) == "The model's plan broke the rules. Try again.")
        #expect(text.quotaLine(QuotaStatus(state: .belowLimit, resetDate: nil)) == "Below limit")
        #expect(text.quotaLine(QuotaStatus(state: .nearingLimit, resetDate: nil)) == "Nearing usage limit")
        #expect(text.quotaLine(QuotaStatus(state: .limitReached, resetDate: now.addingTimeInterval(3 * 3_600))) == "Limit reached, resets 12:00")
    }

    @Test func latestCompletedSessionFacts() throws {
        let facts = try #require(BuildLatestSessionFacts().execute(
            plan: CalendarPlanFixture.plan, runs: CalendarPlanFixture.runs, today: CalendarPlanFixture.today
        ))
        // 26 Oct: an easy run planned 6.0 km, done 6.2 km in 2046 s; week 3 of 8; 41 days to race.
        #expect(facts.sessionName == "Easy run" && facts.plannedKm == 6 && facts.doneKm == 6.2)
        #expect(facts.weekIndex == 3 && facts.weeksTotal == 8 && facts.phase == .base && facts.daysToRace == 41)
        #expect(facts.paceSecPerKm == 330)
        #expect(facts.sleep == nil && facts.hrv == nil && facts.restingHr == nil)
        #expect(BuildLatestSessionFacts().execute(plan: CalendarPlanFixture.plan, runs: [], today: CalendarPlanFixture.today) == nil)
    }
}
