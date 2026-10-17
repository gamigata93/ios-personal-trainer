import Foundation
import Testing
import Domain
import Application
import Infrastructure
@testable import HybridAthlete

@MainActor
struct PlanGeneratorCompositionTests {
    private struct Wednesday: Clock {
        func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
    }

    private func generator(_ arguments: [String]) -> any PlanGenerator {
        let options = CompositionRoot.DebugOptions(arguments: arguments)
        let models = options.fakeLLM.map { CompositionRoot.LanguageModels.fake($0, clock: Wednesday()) }
            ?? .apple(database: try? DatabaseProvider.inMemory(), clock: Wednesday())
        return options.planGenerator.make(models: models, fallback: options.planFallback, delaySeconds: options.planDelay)
    }

    @Test func defaultIsTheTemplateWithoutDelay() {
        #expect(generator([]) is TemplatePlanGenerator)
        #expect((generator(["-planDelay", "2"]) as? SimulatedDelayPlanGenerator)?.seconds == 2)
        #expect(generator(["-planDelay", "0"]) is TemplatePlanGenerator)
    }

    @Test func aModelKindIsValidatedWithTwoAttemptsAndNoDelay() {
        let checked = generator(["-planGenerator", "pcc.moderate", "-planDelay", "2"])
        #expect((checked as? ValidatingPlanGenerator)?.maxAttempts == 2)
        #expect(generator(["-planGenerator", "pcc.moderate", "-planFallback"]) is FallbackPlanGenerator)
        #expect(CompositionRoot.PlanGeneratorKind(id: "pcc.moderate") == .pcc(.moderate))
        #expect(CompositionRoot.PlanGeneratorKind(id: "onDevice") == .onDevice)
        #expect(CompositionRoot.PlanGeneratorKind(id: "anthropic.sonnet55") == .anthropic(.sonnet55))
        #expect(CompositionRoot.PlanGeneratorKind(id: "anthropic.fable51")?.model == .anthropic(.fable51))
        #expect(CompositionRoot.PlanGeneratorKind(id: "gpt") == nil)
        let claude = generator(["-planGenerator", "anthropic.haiku55", "-planDelay", "2"])
        #expect((claude as? ValidatingPlanGenerator)?.maxAttempts == 2)
    }

    @Test func everyClaudeAttemptIsRecordedOnItsOwn() async throws {
        // invalidPlan: the first draft breaks a rule, the retry with notes is valid.
        let models = CompositionRoot.LanguageModels.fake(.invalidPlan, clock: Wednesday())
        await models.spend.settings.save(LabSettings(consentGiven: true))
        try await models.spend.secrets.setSecret("sk-ant-test-a1b2", for: .anthropicAPIKey)
        let generator = CompositionRoot.PlanGeneratorKind.anthropic(.sonnet55).make(models: models)
        let plan = try await generator.generate(SeedPlan.request)
        #expect(plan.generatedBy == "claude-sonnet-5-5-v1")
        let records = try await models.spend.ledger.records(since: nil)
        #expect(records.map(\.purpose) == [.planGeneration, .planGeneration])
        #expect(records.map(\.costMicros) == [27_700, 27_700])
    }

    @Test func claudeWithoutConsentFailsTheRealFlow() async {
        let models = CompositionRoot.LanguageModels.fake(.anthropicOk, clock: Wednesday())
        await #expect(throws: LLMError.spendLimit("Allow Claude runs first.")) {
            try await CompositionRoot.PlanGeneratorKind.anthropic(.haiku55).make(models: models).generate(SeedPlan.request)
        }
    }

    @Test func fakeInvalidPlanSucceedsInTheRealFlow() async throws {
        let plan = try await generator(["-planGenerator", "onDevice", "-fakeLLM", "invalidPlan"]).generate(SeedPlan.request)
        #expect(plan.generatedBy == "on-device-v1")
    }

    @Test func generatingMapsModelErrors() {
        let text = LLMErrorText(calendar: .current, locale: Locale(identifier: "en_GB"), now: { Date() })
        #expect(GeneratingViewModel.message(.modelFailed(.invalidPlan(["x"])), errorText: text) == "The model's plan broke the rules. Try again.")
        #expect(GeneratingViewModel.message(.modelFailed(.unavailable(.notEnabledForBuild)), errorText: text) == ModelAvailability.notEnabledForBuild.message)
        #expect(GeneratingViewModel.message(.modelFailed(.quotaLimitReached(resetDate: nil)), errorText: text).hasPrefix("Today's Apple Intelligence limit was reached."))
    }
}

@MainActor
struct ModelLabViewModelTests {
    private struct Wednesday: Clock {
        func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) }
    }

    private func lab(
        _ scenario: FakeLLMScenario = .ok,
        plan: TrainingPlan? = SeedPlan.plan(createdAt: .distantPast),
        models given: CompositionRoot.LanguageModels? = nil
    ) async -> ModelLabViewModel {
        let models = given ?? CompositionRoot.LanguageModels.fake(scenario, clock: Wednesday())
        let plans = ActivePlanStore(plans: StubPlans(plan: plan), clock: Wednesday())
        let runsCache = StubRunsCache()
        let runs = CompletedRunsStore(
            plans: plans,
            loadCompletedRuns: LoadCompletedRuns(cache: runsCache),
            refreshCompletedRuns: RefreshCompletedRuns(health: StubHealthDataSource(), cache: runsCache, clock: Wednesday(), calendar: .current),
            clock: Wednesday()
        )
        let analyses = MemoryWorkoutAnalyses()
        let prepare = PrepareWorkoutNote(
            analyze: AnalyzeWorkout(source: FakeWorkoutDetailSource(scenario: .tempo, runs: { [] }, activePlan: { nil }), analyses: analyses, clock: Wednesday()),
            build: BuildWorkoutNoteRequest(
                profile: { FakeHeartRateProfile.profile }, sleep: StubSleepCache(), recovery: StubRecoveryCache(),
                analyses: analyses, clock: Wednesday(), calendar: .current
            )
        )
        let viewModel = ModelLabViewModel(
            runner: RunModelExperiment(coaching: models.coaching, drafting: models.drafting, availability: models.availability, template: TemplatePlanGenerator()),
            prepareNote: prepare,
            buildPlanRequest: BuildLabPlanRequest(fitness: LoadFitnessSummary(cache: StubSnapshotCache()), clock: Wednesday(), calendar: .current),
            plans: plans,
            runs: runs,
            settings: LabSpendSettings(store: models.spend.settings),
            errorText: LLMErrorText(calendar: .current, locale: Locale(identifier: "en_GB"), now: { Wednesday().now() }),
            today: { LocalDate(year: 2026, month: 10, day: 28) },
            claude: CompositionRoot.makeClaudeLab(spend: models.spend, clock: Wednesday())
        )
        await viewModel.appear()
        return viewModel
    }

    @Test func sampleWorkoutNoteOnDevice() async {
        let viewModel = await lab()
        #expect(viewModel.status?.availability == .available)
        #expect(viewModel.status?.contextSize == 4_096)
        viewModel.coachInput = .sample
        await viewModel.run()?.value
        let card = viewModel.cards.first
        #expect(card?.id == 1)
        #expect(card?.result.usage?.latencyText == "1.2 s")
        #expect(card?.result.usage?.line == "in 312 · out 64 · cached 0")
        #expect(card?.json?.contains("\"experiment\" : \"workoutNote\"") == true)
        if case .workoutNote = card?.result.output {} else { Issue.record("expected a workout note") }
        #expect(card?.result.factsLevel == 0)
    }

    @Test func latestWithoutRunsExplainsWhy() async {
        let viewModel = await lab()
        await viewModel.run()?.value
        #expect(viewModel.cards.isEmpty)
        #expect(viewModel.latestUnavailableText == "No completed session with a run yet. Use the sample.")
    }

    @Test func runAllMakesOneCardPerAvailableModelNewestFirst() async {
        let viewModel = await lab()
        viewModel.experiment = .planDraft
        await viewModel.runAll()?.value
        // Apple's models only: "Run all" never mixes free and paid models.
        #expect(viewModel.cards.map(\.result.model) == ModelChoice.apple.reversed())
        #expect(viewModel.runAllTitle == "Run all Apple models")
        guard case .planDraft(let table) = viewModel.cards.first?.result.output else { Issue.record("no table"); return }
        #expect(table.rows.count == 8)
        #expect(viewModel.cards.first?.result.validityText == "Valid")
    }

    @Test func invalidPlanShowsOneIssueInTheLab() async {
        let viewModel = await lab(.invalidPlan)
        viewModel.experiment = .planDraft
        await viewModel.run()?.value
        #expect(viewModel.cards.first?.result.validityText == "1 issue")
    }

    @Test func unavailableAndQuota() async {
        let unavailable = await lab(.unavailable)
        unavailable.coachInput = .sample
        await unavailable.run()?.value
        #expect(unavailable.cards.first?.errorText == ModelAvailability.notReady.message)

        let quota = await lab(.quota)
        quota.coachInput = .sample
        await quota.run()?.value
        #expect(quota.cards.first?.errorText?.hasPrefix("Today's Apple Intelligence limit was reached. It resets") == true)
    }

    // MARK: Claude

    @Test func consentComesBeforeTheFirstClaudeRun() async throws {
        let models = CompositionRoot.LanguageModels.fake(.anthropicOk, clock: Wednesday())
        let viewModel = await lab(models: models)
        viewModel.selectedModel = .anthropic(.sonnet55)
        viewModel.experiment = .planDraft
        #expect(viewModel.run() == nil)
        #expect(viewModel.claude.showsConsent)
        #expect(viewModel.cards.isEmpty)

        viewModel.claude.keyInput = "sk-ant-api03-secret-a1b2"
        await viewModel.claude.saveKey()
        await viewModel.claude.allow()
        await viewModel.task?.value
        #expect(!viewModel.claude.showsConsent)
        #expect(await models.spend.settings.load().consentGiven)
        let card = try #require(viewModel.cards.first)
        #expect(card.result.usage?.costMicros == 27_700)
        #expect(viewModel.claude.totalText == "$0.028")
        #expect(viewModel.runAllTitle == "Run all Claude models")
        #expect(viewModel.claude.priceLine(.anthropic(.sonnet55)) == "$2 in · $10 out per 1M tokens")
        #expect(card.json?.contains("sk-ant") == false)
        #expect(await viewModel.claude.usageJSON()?.contains("sk-ant") == false)
    }

    @Test func notNowRunsNothing() async {
        let viewModel = await lab(.anthropicOk)
        viewModel.selectedModel = .anthropic(.haiku55)
        viewModel.coachInput = .sample
        viewModel.run()
        viewModel.claude.decline()
        #expect(!viewModel.claude.showsConsent)
        #expect(viewModel.task == nil)
        #expect(viewModel.cards.isEmpty)
    }

    @Test func theKeyIsStoredAndOnlyItsLastFourAreShown() async throws {
        let models = CompositionRoot.LanguageModels.fake(.anthropicOk, clock: Wednesday())
        let viewModel = await lab(models: models)
        #expect(viewModel.claude.keyStatus == .none)
        #expect(viewModel.statuses[.anthropic(.opus55)]?.availability == .needsAPIKey)
        viewModel.claude.keyInput = "sk-ant-api03-secret-a1b2"
        await viewModel.claude.saveKey()
        #expect(viewModel.claude.keyStatus == .saved(lastFour: "a1b2"))
        #expect(viewModel.claude.keyStatus.text == "Saved · ends \u{2026}a1b2")
        #expect(viewModel.claude.keyInput.isEmpty)
        #expect(try await models.spend.secrets.secret(for: .anthropicAPIKey) == "sk-ant-api03-secret-a1b2")
        #expect(viewModel.statuses[.anthropic(.opus55)]?.availability == .available)

        await viewModel.claude.testKey()
        #expect(viewModel.claude.keyMessage?.hasPrefix("Key works · 0.4 s · ") == true)
        let records = try await models.spend.ledger.records(since: nil)
        #expect(records.map(\.purpose) == [.keyTest])

        await viewModel.claude.removeKey()
        #expect(viewModel.claude.keyStatus == .none)
        #expect(try await models.spend.secrets.secret(for: .anthropicAPIKey) == nil)
        #expect(viewModel.statuses[.anthropic(.opus55)]?.availability == .needsAPIKey)
    }

    /// Consent and a key in the fake stores, then a Claude model selected.
    private func claudeLab(_ scenario: FakeLLMScenario, model: AnthropicModel) async throws -> (ModelLabViewModel, CompositionRoot.LanguageModels) {
        let models = CompositionRoot.LanguageModels.fake(scenario, clock: Wednesday())
        await models.spend.settings.save(LabSettings(consentGiven: true))
        try await models.spend.secrets.setSecret("sk-ant-test-a1b2", for: .anthropicAPIKey)
        let viewModel = await lab(models: models)
        viewModel.selectedModel = .anthropic(model)
        return (viewModel, models)
    }

    @Test func aDeniedRunRecordsNothing() async throws {
        let (viewModel, models) = try await claudeLab(.anthropicOk, model: .fable51)
        await viewModel.claude.updatePerRun("0.01")
        viewModel.experiment = .planDraft
        await viewModel.run()?.value
        let error = try #require(viewModel.cards.first?.errorText)
        #expect(error.hasPrefix("Blocked by your spend limit: this run could cost up to $0."))
        #expect(error.hasSuffix(", your per-run limit is $0.01."))
        #expect(try await models.spend.ledger.records(since: nil).isEmpty)
    }

    @Test func aFailedRunIsStillRecorded() async throws {
        let (viewModel, models) = try await claudeLab(.credits, model: .sonnet55)
        viewModel.coachInput = .sample
        await viewModel.run()?.value
        #expect(viewModel.cards.first?.errorText == "Your Anthropic credit balance is too low. Add credits in the Claude Console.")
        let records = try await models.spend.ledger.records(since: nil)
        #expect(records.map(\.errorKind) == ["billingProblem"])
        #expect(records.first?.success == false)
    }

    @Test func capsAndProjection() async throws {
        let (viewModel, _) = try await claudeLab(.anthropicOk, model: .sonnet55)
        #expect(viewModel.claude.perRunText == "0.25")
        #expect(viewModel.claude.perMonthText == "5.00")
        viewModel.experiment = .planDraft
        await viewModel.run()?.value
        viewModel.coachInput = .sample
        viewModel.experiment = .coachNote
        await viewModel.run()?.value
        #expect(viewModel.claude.capLine == "This month: $0.030 of $5.00")
        #expect(viewModel.claude.capTone == .normal)
        #expect(viewModel.claude.capAccessibilityText == "This month, 3 cents spent of a 5 dollar limit. Per run limit 25 cents.")
        let sonnet = try #require(viewModel.claude.projection?.first { $0.model == .sonnet55 })
        // 2 plans x 27,700 + 30 notes x (600 x 2 + 150 x 10 = 2,700) = 136,400.
        #expect(sonnet.monthlyMicros == 136_400)
        #expect(viewModel.claude.monthlyLine(sonnet) == "≈ $0.136 a month")
        await viewModel.claude.updatePerRun("abc")
        #expect(viewModel.claude.capsError == "Enter an amount such as 0.25.")
        await viewModel.claude.clearHistory()
        #expect(viewModel.claude.totalText == "$0.00")
    }
}
