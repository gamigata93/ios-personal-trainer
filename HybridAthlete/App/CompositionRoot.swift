import Foundation
import Domain
import Application
import Infrastructure

/// The only place that constructs infrastructure types. Builds the adapters,
/// the use cases on top of them, and the view models.
@MainActor
enum CompositionRoot {
    static func makeRootViewModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> RootViewModel {
        #if DEBUG
        let options = DebugOptions(arguments: arguments)
        if let today = options.today {
            clock = ShiftedClock(base: SystemClock(), today: today, calendar: .current)
        }
        let health = HealthEnvironment(options: options)
        #else
        let health = HealthEnvironment()
        #endif
        if health.usesRealHealth {
            // TODO: remove with LegacyKeychainCleanup in a later release.
            LegacyKeychainCleanup.run()
        }
        // The plan lives in the database (trainer.sqlite); a plan from the old JSON file
        // is imported once before the launch route. DEBUG fakes keep their plan, runs,
        // sleep and recovery in memory so they never mix with real ones.
        var database = health.usesRealHealth ? try? DatabaseProvider.onDisk() : try? DatabaseProvider.inMemory()
        var plans: any PlanRepository = database.map { GRDBPlanRepository(database: $0, clock: clock) } ?? UnavailablePlanRepository()
        var prepareStorage: @MainActor () async -> Void = {}
        if health.usesRealHealth {
            let importer = LegacyPlanImporter(plans: plans, clock: clock)
            prepareStorage = { await importer.run() }
        }
        var runsCache: any CompletedRunsCache = health.usesRealHealth ? FileCompletedRunsCache() : InMemoryCompletedRunsCache()
        var sleepCache: any SleepCache = health.usesRealHealth ? FileSleepCache() : InMemorySleepCache()
        var recoveryCache: any RecoveryCache = health.usesRealHealth ? FileRecoveryCache() : InMemoryRecoveryCache()
        var homeHealth: HomeHealthFactory = { _ in health.source }
        var launch = MainLaunch()
        var models = LanguageModels.apple(database: database, clock: clock)
        var generator: any PlanGenerator = PlanGeneratorKind.automatic.make(models: models)
        let loadProfile = LoadHeartRateProfile(snapshots: health.cache, recovery: recoveryCache)
        var workoutDetail: WorkoutDetailFactory = { _ in HealthKitWorkoutDetailSource() }
        var heartRateProfile: @Sendable () async -> HeartRateProfile? = { await loadProfile.execute() }
        var coachNoteModels: CoachNoteModels?
        var preferenceOverride: CoachModelPreference?
        var strengthHealth: StrengthSourceFactory = { _ in health.source as? any StrengthWorkoutSource }
        var adjustModels = AdjustModels(
            adjusting: models.adjusting, availability: models.availability, models: CoachModelPreference.automatic.candidates
        )
        var asksFeedback = health.usesRealHealth
        var raceScope = RaceDistanceScope.app
        #if DEBUG
        if options.allowsAnyDistance { raceScope = .unrestricted }
        if let scenario = options.fakeLLM {
            models = LanguageModels.fake(scenario, clock: clock)
        }
        generator = options.planGenerator.make(models: models, fallback: options.planFallback, delaySeconds: options.planDelay)
        launch = MainLaunch(startTab: options.startTab, calendarMonth: options.calendarMonth)
        if options.seedsPlan {
            // Coach notes live next to the seeded plan (their sessions are foreign keys).
            database = try? GRDBPlanRepository.seededDatabase(SeedPlan.plan(createdAt: clock.now()))
            plans = database.map { GRDBPlanRepository(database: $0, clock: clock) } ?? UnavailablePlanRepository()
        }
        if !health.usesRealHealth {
            // DEBUG fakes: the fixed profile (max 182, resting 49) and canned workout detail.
            heartRateProfile = { FakeHeartRateProfile.profile }
            let fakesRuns = options.fakesRuns
            let high = options.fakeHeartRateHigh
            let scenario = options.workoutDetailScenario
            workoutDetail = { plans in
                let runs = FakeRunsHealthDataSource(
                    base: health.source, activePlan: { await plans.loadActive() }, clock: clock, calendar: .current, highHeartRate: high
                )
                return FakeWorkoutDetailSource(
                    scenario: scenario,
                    runs: { fakesRuns ? await runs.allRuns() : [] },
                    activePlan: { await plans.loadActive() },
                    highHeartRate: high
                )
            }
        }
        if options.fakesRuns {
            runsCache = InMemoryCompletedRunsCache()
            let high = options.fakeHeartRateHigh
            homeHealth = { plans in
                FakeRunsHealthDataSource(base: health.source, activePlan: { await plans.loadActive() }, clock: clock, calendar: .current, highHeartRate: high)
            }
            strengthHealth = { plans in
                FakeRunsHealthDataSource(base: health.source, activePlan: { await plans.loadActive() }, clock: clock, calendar: .current)
            }
        }
        // Fake Health never asks for feedback unless -feedbackPopup, and the rules
        // write suggestions unless -fakeAdjust picks a canned model.
        if !health.usesRealHealth {
            asksFeedback = options.feedbackPopup
            adjustModels = AdjustModels(adjusting: models.adjusting, availability: models.availability, models: [])
        }
        if let scenario = options.fakeAdjust {
            let seeded = plans
            adjustModels = AdjustModels(
                adjusting: FakePlanAdjuster(scenario: scenario, activePlan: { await seeded.loadActive() }),
                availability: FakeModelAvailabilityChecker(scenario: .ok, clock: clock, secrets: models.spend.secrets),
                models: [.onDevice]
            )
        }
        if let scenario = options.fakeCoachNote {
            coachNoteModels = CoachNoteModels.fake(scenario, spend: models.spend, clock: clock)
            if scenario == .rules { preferenceOverride = .ruleBased }
        }
        // Fake Health data never reaches a real model unless asked for: the rules write
        // the notes, so UI tests stay fast and repeatable.
        if !health.usesRealHealth && options.fakeCoachNote == nil { preferenceOverride = .ruleBased }
        if let preference = options.coachModel { preferenceOverride = preference }
        if let scenario = options.sleepScenario {
            sleepCache = InMemorySleepCache(FakeSleepHealthDataSource.seededCache(scenario, clock: clock, calendar: .current))
            let withoutSleep = homeHealth
            homeHealth = { plans in
                FakeSleepHealthDataSource(base: withoutSleep(plans), scenario: scenario, clock: clock, calendar: .current)
            }
        }
        if let scenario = options.recoveryScenario {
            recoveryCache = InMemoryRecoveryCache(FakeRecoveryHealthDataSource.seededCache(scenario, clock: clock, calendar: .current))
            let withoutRecovery = homeHealth
            homeHealth = { plans in
                FakeRecoveryHealthDataSource(base: withoutRecovery(plans), scenario: scenario, clock: clock, calendar: .current)
            }
        }
        #endif
        let noteDatabase = database ?? (try? DatabaseProvider.inMemory())
        let feedbackInputs = FeedbackInputs(
            feedback: noteDatabase.map { GRDBWorkoutFeedbackRepository(database: $0) as any WorkoutFeedbackRepository }
                ?? UnavailableWorkoutFeedbackRepository(),
            adjustments: noteDatabase.map { GRDBPlanAdjustmentRepository(database: $0, clock: clock) as any PlanAdjustmentRepository }
                ?? UnavailablePlanAdjustmentRepository(),
            adjust: adjustModels,
            strengthHealth: strengthHealth,
            asksAutomatically: asksFeedback
        )
        let notes = NoteInputs(
            notes: noteDatabase.map { GRDBCoachNoteRepository(database: $0) as any CoachNoteRepository } ?? UnavailableCoachNoteRepository(),
            analyses: noteDatabase.map { GRDBWorkoutAnalysisRepository(database: $0) as any WorkoutAnalysisRepository }
                ?? UnavailableWorkoutAnalysisRepository(),
            detail: workoutDetail,
            profile: heartRateProfile,
            models: coachNoteModels ?? CoachNoteModels(coaching: models.coaching, availability: models.availability),
            settings: models.spend.settings,
            preferenceOverride: preferenceOverride
        )
        return makeRootViewModel(
            health: health,
            plans: plans,
            stores: HomeStores(runs: runsCache, sleep: sleepCache, recovery: recoveryCache),
            homeHealth: homeHealth,
            launch: launch,
            generator: generator,
            models: models,
            notes: notes,
            feedback: feedbackInputs,
            raceScope: raceScope,
            prepareStorage: prepareStorage
        )
    }

    /// Where the main app opens. DEBUG `-startTab` and `-calendarMonth` set it.
    private struct MainLaunch {
        var startTab: MainScreens.Tab = .home
        var calendarMonth: YearMonth?
    }

    /// The Health source Home reads runs, sleep and recovery from, given the plan store
    /// (DEBUG `-fakeRuns` derives runs from the active plan).
    private typealias HomeHealthFactory = @MainActor (any PlanRepository) -> any HealthDataSource

    /// Where one workout's detail is read from, given the plan store (DEBUG fakes derive it).
    private typealias WorkoutDetailFactory = @MainActor (any PlanRepository) -> any WorkoutDetailSource

    /// Where strength workouts are read from, given the plan store (DEBUG `-fakeRuns` derives them); nil reads none.
    private typealias StrengthSourceFactory = @MainActor (any PlanRepository) -> (any StrengthWorkoutSource)?

    /// The model that drafts suggested changes, what says whether it can run, and
    /// the models to try in order (empty: the rules write every suggestion).
    private struct AdjustModels {
        let adjusting: any PlanAdjustingModel
        let availability: any ModelAvailabilityChecker
        let models: [ModelChoice]
    }

    /// Everything the after-workout feedback and suggested changes are built from.
    private struct FeedbackInputs {
        let feedback: any WorkoutFeedbackRepository
        let adjustments: any PlanAdjustmentRepository
        let adjust: AdjustModels
        let strengthHealth: StrengthSourceFactory
        /// The popup opens by itself (real Health, or DEBUG `-feedbackPopup`).
        let asksAutomatically: Bool
    }

    /// The model that writes coach notes and what says whether it can run: the
    /// real (gated) models, or DEBUG `-fakeCoachNote`.
    struct CoachNoteModels {
        let coaching: any CoachingModel
        let availability: any ModelAvailabilityChecker

        #if DEBUG
        /// Canned notes through the same spend gate and ledger; every Apple model is available.
        static func fake(_ scenario: FakeCoachNoteScenario, spend: SpendServices, clock: any Clock) -> CoachNoteModels {
            let meter = LLMCallMeter(prices: spend.prices, recorder: spend.ledger, clock: clock)
            return CoachNoteModels(
                coaching: SpendGatedCoachingModel(inner: FakeCoachNoteModel(scenario: scenario, meter: meter), gate: spend.gate),
                availability: FakeModelAvailabilityChecker(scenario: .ok, clock: clock, secrets: spend.secrets)
            )
        }
        #endif
    }

    /// Everything the coach notes are built from, in one place.
    private struct NoteInputs {
        let notes: any CoachNoteRepository
        let analyses: any WorkoutAnalysisRepository
        let detail: WorkoutDetailFactory
        let profile: @Sendable () async -> HeartRateProfile?
        let models: CoachNoteModels
        let settings: any LabSettingsStore
        let preferenceOverride: CoachModelPreference?
    }

    /// What the DEBUG Model Lab reads: the models and the cached Health summaries.
    private struct LabInputs {
        let models: LanguageModels
        let snapshots: any SnapshotCache
    }

    /// Where Home caches what it reads.
    private struct HomeStores {
        let runs: any CompletedRunsCache
        let sleep: any SleepCache
        let recovery: any RecoveryCache
    }

    // MARK: Plan generation

    /// Which adapter builds plans for the real flow. Release builds always use the
    /// template; DEBUG `-planGenerator` picks another. A new generator is one new
    /// adapter plus one case here.
    enum PlanGeneratorKind: Equatable {
        /// Private Cloud Compute (light), then on-device, then the template.
        case automatic
        case template
        case onDevice
        case pcc(ReasoningLevel)
        case anthropic(AnthropicModel)

        /// "template", "onDevice", "pcc.light", "pcc.moderate", "pcc.deep",
        /// "anthropic.haiku55", "anthropic.sonnet55", "anthropic.opus55", "anthropic.fable51".
        init?(id: String) {
            if id == "template" {
                self = .template
                return
            }
            if id == "auto" {
                self = .automatic
                return
            }
            switch ModelChoice(id: id) {
            case .onDevice: self = .onDevice
            case .privateCloud(let level): self = .pcc(level)
            case .anthropic(let model): self = .anthropic(model)
            case nil: return nil
            }
        }

        var model: ModelChoice? {
            switch self {
            case .template, .automatic: nil
            case .onDevice: .onDevice
            case .pcc(let level): .privateCloud(reasoning: level)
            case .anthropic(let model): .anthropic(model)
            }
        }

        /// The template (with the DEBUG delay when one is asked for), or a model
        /// drafting the plan, checked with two attempts and never delayed;
        /// `fallback` adds the template behind a model.
        func make(models: LanguageModels, fallback: Bool = false, delaySeconds: Double? = nil) -> any PlanGenerator {
            if self == .automatic {
                // Each model gets two checked attempts; any model error moves on, the template is last.
                func checked(_ model: ModelChoice) -> any PlanGenerator {
                    ValidatingPlanGenerator(inner: ModelPlanGenerator(drafting: models.drafting, model: model))
                }
                return FallbackPlanGenerator(
                    primary: checked(.privateCloud(reasoning: .light)),
                    fallback: FallbackPlanGenerator(primary: checked(.onDevice), fallback: TemplatePlanGenerator())
                )
            }
            guard let model else {
                #if DEBUG
                if let delaySeconds, delaySeconds > 0 {
                    return SimulatedDelayPlanGenerator(inner: TemplatePlanGenerator(), seconds: delaySeconds)
                }
                #endif
                return TemplatePlanGenerator()
            }
            let checked = ValidatingPlanGenerator(
                inner: ModelPlanGenerator(drafting: models.drafting, model: model),
                maxAttempts: ValidatingPlanGenerator.defaultAttempts
            )
            return fallback ? FallbackPlanGenerator(primary: checked, fallback: TemplatePlanGenerator()) : checked
        }
    }

    /// Everything that meters and gates paid model calls: the usage ledger, the
    /// price table, the Lab settings, the secret store, the gate and the key test.
    struct SpendServices {
        let ledger: any LLMUsageLedger
        let prices: any PriceTableProvider
        let settings: any LabSettingsStore
        let secrets: any SecretStore
        let gate: SpendGate
        let keyTester: any AnthropicKeyTesting
    }

    /// The models (Apple's and Claude, or the DEBUG fakes) and their spend
    /// services, built in ONE place. Every adapter records its own attempts
    /// through the meter; the gate runs before anything is sent.
    struct LanguageModels {
        let coaching: any CoachingModel
        let drafting: any PlanDraftingModel
        /// Apple's models only (suggested changes never go to Claude).
        let adjusting: any PlanAdjustingModel
        let availability: any ModelAvailabilityChecker
        let spend: SpendServices

        /// On-device and Private Cloud Compute through Foundation Models (PCC stays
        /// off until the managed entitlement is added), and Claude through
        /// ClaudeForFoundationModels with the key from the Keychain. The ledger is
        /// the app database; without one, Claude runs are blocked.
        static func apple(database: DatabaseProvider?, clock: any Clock) -> LanguageModels {
            let configuration = FoundationModelsConfiguration.current
            let ledger: any LLMUsageLedger = database.map { GRDBLLMUsageLedger(database: $0) } ?? UnavailableLLMUsageLedger()
            let prices = BundledPriceTableProvider()
            let secrets = KeychainSecretStore()
            let settings = UserDefaultsLabSettingsStore()
            let meter = LLMCallMeter(prices: prices, recorder: ledger, clock: clock)
            let gate = SpendGate(settings: settings, secrets: secrets, prices: prices, ledger: ledger, clock: clock, calendar: .current)
            let coaching = FoundationModelsCoachingModel(configuration: configuration, secrets: secrets, meter: meter)
            return LanguageModels(
                coaching: SpendGatedCoachingModel(inner: FallbackCoachingModel(primary: coaching, fallback: coaching), gate: gate),
                drafting: SpendGatedPlanDraftingModel(
                    inner: FoundationModelsPlanDrafter(configuration: configuration, secrets: secrets, meter: meter),
                    gate: gate
                ),
                adjusting: FoundationModelsPlanAdjuster(configuration: configuration, secrets: secrets, meter: meter),
                availability: FoundationModelAvailabilityChecker(configuration: configuration, secrets: secrets),
                spend: SpendServices(
                    ledger: ledger, prices: prices, settings: settings, secrets: secrets, gate: gate,
                    keyTester: ClaudeKeyTester(secrets: secrets, meter: meter)
                )
            )
        }

        #if DEBUG
        /// `-fakeLLM <scenario>`: canned answers, no FoundationModels, and an
        /// in-memory ledger, settings and secret store (never the database or the
        /// Keychain). Prices come from the real bundled table.
        static func fake(_ scenario: FakeLLMScenario, clock: any Clock) -> LanguageModels {
            let ledger = InMemoryLLMUsageLedger()
            let prices = BundledPriceTableProvider()
            let secrets = InMemorySecretStore()
            let settings = InMemoryLabSettingsStore()
            let meter = LLMCallMeter(prices: prices, recorder: ledger, clock: clock)
            let gate = SpendGate(settings: settings, secrets: secrets, prices: prices, ledger: ledger, clock: clock, calendar: .current)
            let model = FakeLanguageModel(scenario: scenario, clock: clock, meter: meter)
            return LanguageModels(
                coaching: SpendGatedCoachingModel(inner: model, gate: gate),
                drafting: SpendGatedPlanDraftingModel(inner: model, gate: gate),
                adjusting: FakePlanAdjuster(scenario: .fail, activePlan: { nil }),
                availability: FakeModelAvailabilityChecker(scenario: scenario, clock: clock, secrets: secrets),
                spend: SpendServices(
                    ledger: ledger, prices: prices, settings: settings, secrets: secrets, gate: gate,
                    keyTester: FakeKeyTester(scenario: scenario, meter: meter)
                )
            )
        }
        #endif
    }

    // MARK: Assembly

    /// The system clock; DEBUG `-today` replaces it before anything is built.
    private static var clock: any Clock = SystemClock()
    private static let norms = BundledNormRepository()

    private static func makeRootViewModel(
        health: HealthEnvironment,
        plans: any PlanRepository,
        stores: HomeStores,
        homeHealth: @escaping HomeHealthFactory,
        launch: MainLaunch,
        generator: any PlanGenerator,
        models: LanguageModels,
        notes: NoteInputs,
        feedback: FeedbackInputs,
        raceScope: RaceDistanceScope,
        prepareStorage: @escaping @MainActor () async -> Void
    ) -> RootViewModel {
        let clock = clock
        let errorText = LLMErrorText(calendar: .current, locale: .current, now: { clock.now() })
        return RootViewModel(
            resolveLaunchRoute: LaunchRouteResolver(health: health.source, plans: plans),
            refreshHealthSnapshot: RefreshHealthSnapshot(health: health.source, cache: health.cache, clock: clock),
            makeConnectHealth: { onFinished in
                ConnectHealthViewModel(
                    requestHealthAccess: RequestHealthAccess(health: health.source),
                    onFinished: onFinished,
                    personaChoices: health.personaChoices,
                    onChoosePersona: { health.choosePersona($0) }
                )
            },
            makeStartingPoint: { onContinue in
                makeStartingPoint(health: health.source, cache: health.cache, onContinue: onContinue)
            },
            makeRaceSetup: { draft, onBuild, onBack in
                RaceSetupViewModel(
                    draft: draft,
                    validateRaceSetup: ValidateRaceSetup(clock: clock, calendar: .current, scope: raceScope),
                    calendar: .current,
                    onBuild: onBuild,
                    onBack: onBack
                )
            },
            makeGenerating: { setup, source, onSuccess, onBack in
                GeneratingViewModel(
                    setup: setup,
                    source: source,
                    createPlan: CreatePlan(
                        generator: generator,
                        plans: plans,
                        cache: health.cache,
                        clock: clock,
                        calendar: .current,
                        makeID: { UUID().uuidString },
                        scope: raceScope
                    ),
                    onSuccess: onSuccess,
                    onBack: onBack,
                    errorText: errorText
                )
            },
            makeHome: { onNoPlan in
                makeMain(
                    plans: plans, stores: stores, health: homeHealth(plans), clock: clock, launch: launch,
                    lab: LabInputs(models: models, snapshots: health.cache), notes: notes, feedback: feedback, onNoPlan: onNoPlan
                )
            },
            prepareStorage: prepareStorage
        )
    }

    /// Home, Calendar and Session detail around one shared plan store and one
    /// shared runs store. Recovery is assembled here too, in one place.
    private static func makeMain(
        plans repository: any PlanRepository,
        stores: HomeStores,
        health: any HealthDataSource,
        clock: any Clock,
        launch: MainLaunch,
        lab: LabInputs,
        notes inputs: NoteInputs,
        feedback feedbackInputs: FeedbackInputs,
        onNoPlan: @escaping @MainActor () -> Void
    ) -> MainScreens {
        let plans = ActivePlanStore(
            loadActivePlan: LoadActivePlan(plans: repository),
            applyPlanEdit: ApplyPlanEdit(plans: repository, clock: clock, calendar: .current),
            undoPlanEdit: UndoPlanEdit(plans: repository),
            loadRecentPlanEdits: LoadRecentPlanEdits(plans: repository)
        )
        let runs = CompletedRunsStore(
            plans: plans,
            loadCompletedRuns: LoadCompletedRuns(cache: stores.runs),
            refreshCompletedRuns: RefreshCompletedRuns(
                health: health, strength: feedbackInputs.strengthHealth(repository), cache: stores.runs, clock: clock, calendar: .current
            ),
            clock: clock
        )
        let loadFeedback = LoadWorkoutFeedback(feedback: feedbackInputs.feedback)
        // Coach notes: analysis, facts, the provider chain and the store, in one place.
        let prepareNote = PrepareWorkoutNote(
            analyze: AnalyzeWorkout(source: inputs.detail(repository), analyses: inputs.analyses, clock: clock),
            build: BuildWorkoutNoteRequest(
                profile: inputs.profile, sleep: stores.sleep, recovery: stores.recovery, analyses: inputs.analyses,
                feedback: loadFeedback, clock: clock, calendar: .current
            )
        )
        let notes = CoachNoteStore(
            plans: plans,
            runs: runs,
            generate: GenerateDetailedCoachNote(
                prepare: prepareNote,
                write: WriteWorkoutNote(
                    coaching: inputs.models.coaching,
                    availability: inputs.models.availability,
                    settings: inputs.settings,
                    preferenceOverride: inputs.preferenceOverride
                ),
                notes: inputs.notes,
                clock: clock
            ),
            prepare: prepareNote,
            loadNotes: LoadCoachNotes(notes: inputs.notes),
            today: { LocalDate(date: clock.now(), calendar: .current) }
        )
        // After-workout feedback and suggested changes, in one place.
        let feedback = FeedbackStore(
            plans: plans,
            runs: runs,
            pending: PendingFeedback(feedback: feedbackInputs.feedback, clock: clock, calendar: .current),
            save: SaveWorkoutFeedback(feedback: feedbackInputs.feedback),
            load: loadFeedback,
            suggest: SuggestPlanAdjustment(
                adjusting: feedbackInputs.adjust.adjusting, availability: feedbackInputs.adjust.availability,
                adjustments: feedbackInputs.adjustments, loadFeedback: loadFeedback, models: feedbackInputs.adjust.models,
                clock: clock, calendar: .current
            ),
            adjustments: PlanAdjustments(adjustments: feedbackInputs.adjustments),
            clock: clock,
            asksAutomatically: feedbackInputs.asksAutomatically
        )
        notes.isAwaitingFeedback = { [weak feedback] id in feedback?.isAwaiting(id) ?? false }
        feedback.onAnswered = { await notes.afterRefresh() }
        // Feedback first: notes for workouts still being asked about wait for the answer.
        runs.onRefreshed = {
            await feedback.afterRefresh()
            await notes.afterRefresh()
        }
        let loadCachedSleep = LoadCachedSleep(cache: stores.sleep)
        let refreshRecoverySection = RefreshRecoverySection(
            refreshSleep: RefreshSleep(health: health, cache: stores.sleep, clock: clock, calendar: .current),
            loadCachedSleep: loadCachedSleep,
            refreshRecovery: RefreshRecovery(health: health, cache: stores.recovery, clock: clock, calendar: .current)
        )
        let home = HomeViewModel(
            plans: plans,
            runs: runs,
            loadCachedSleep: loadCachedSleep,
            loadCachedRecovery: LoadCachedRecovery(cache: stores.recovery),
            refreshRecoverySection: refreshRecoverySection,
            getHomeOverview: GetHomeOverview(
                clock: clock,
                calendar: .current,
                sleepOverview: GetSleepOverview(calendar: .current, locale: .current),
                recoveryOverview: GetRecoveryOverview()
            ),
            deleteActivePlan: DeleteActivePlan(plans: repository),
            clock: clock,
            notes: notes,
            onNoPlan: onNoPlan
        )
        #if DEBUG
        home.sdkHasRmssdType = HealthKitDataSource.sdkHasRmssdType
        let spend = lab.models.spend
        home.makeModelLab = {
            ModelLabViewModel(
                runner: RunModelExperiment(
                    coaching: inputs.models.coaching,
                    drafting: lab.models.drafting,
                    availability: inputs.models.availability,
                    template: TemplatePlanGenerator()
                ),
                prepareNote: prepareNote,
                buildPlanRequest: BuildLabPlanRequest(fitness: LoadFitnessSummary(cache: lab.snapshots), clock: clock, calendar: .current),
                plans: plans,
                runs: runs,
                settings: LabSpendSettings(store: spend.settings),
                errorText: LLMErrorText(calendar: .current, locale: .current, now: { clock.now() }),
                today: { LocalDate(date: clock.now(), calendar: .current) },
                claude: makeClaudeLab(spend: spend, clock: clock)
            )
        }
        #endif
        home.feedback = feedback
        let getSessionDetail = GetSessionDetail(clock: clock, calendar: .current)
        let getStrengthDetail = GetStrengthDetail(clock: clock, calendar: .current)
        let screens = MainScreens(
            plans: plans,
            runs: runs,
            home: home,
            calendar: CalendarViewModel(
                plans: plans,
                runs: runs,
                getCalendarMonth: GetCalendarMonth(clock: clock, calendar: .current),
                requestedMonth: launch.calendarMonth
            ),
            startTab: launch.startTab,
            notes: notes,
            makeSessionDetail: { id in
                let detail = SessionDetailViewModel(
                    sessionID: id, plans: plans, runs: runs, notes: notes, getSessionDetail: getSessionDetail, clock: clock, calendar: .current
                )
                detail.feedback = feedback
                return detail
            }
        )
        screens.feedback = feedback
        screens.makeStrengthDetail = { id in
            StrengthDetailViewModel(sessionID: id, plans: plans, runs: runs, getStrengthDetail: getStrengthDetail)
        }
        return screens
    }

    #if DEBUG
    /// The Lab's cost, key, consent and caps, over the spend services.
    static func makeClaudeLab(spend: SpendServices, clock: any Clock) -> ClaudeLabViewModel {
        ClaudeLabViewModel(
            getSpendOverview: GetSpendOverview(ledger: spend.ledger, prices: spend.prices, clock: clock, calendar: .current),
            projectCosts: ProjectCosts(ledger: spend.ledger, prices: spend.prices),
            clearUsageHistory: ClearUsageHistory(ledger: spend.ledger),
            settings: LabSpendSettings(store: spend.settings),
            manageKey: ManageAnthropicKey(secrets: spend.secrets),
            testKey: TestAnthropicKey(gate: spend.gate, tester: spend.keyTester),
            priceLine: GetClaudePriceLine(prices: spend.prices),
            exportUsage: { await UsageLedgerJSON.export(ledger: spend.ledger, prices: spend.prices) },
            errorText: LLMErrorText(calendar: .current, locale: .current, now: { clock.now() }),
            locale: .current
        )
    }
    #endif

    private static func makeStartingPoint(
        health: any HealthDataSource,
        cache: any SnapshotCache,
        onContinue: @escaping @MainActor (RaceSetupDraft) -> Void
    ) -> StartingPointViewModel {
        StartingPointViewModel(
            loadCachedSnapshot: LoadCachedSnapshot(cache: cache),
            refreshHealthSnapshot: RefreshHealthSnapshot(health: health, cache: cache, clock: clock),
            computeFitnessBaseline: ComputeFitnessBaseline(norms: norms, clock: clock),
            suggestPlans: SuggestPlans(clock: clock, calendar: .current),
            clock: clock,
            calendar: .current,
            onContinue: onContinue
        )
    }

    // MARK: Previews and tests

    #if DEBUG
    /// The dashboard for a persona with an empty in-memory cache, read through the
    /// real use cases and norm data. For SwiftUI previews and view-model tests.
    static func previewStartingPointViewModel(
        persona id: String = "casual",
        slow: Bool = false,
        onContinue: @escaping @MainActor (RaceSetupDraft) -> Void = { _ in }
    ) -> StartingPointViewModel {
        let base: any HealthDataSource = Persona.named(id).map { PersonaHealthDataSource(persona: $0, clock: clock) }
            ?? InMemoryHealthDataSource(clock: clock)
        return makeStartingPoint(
            health: SimulatedHealthDataSource(base: base, mode: slow ? .slow : .normal, alreadyRequested: true),
            cache: InMemorySnapshotCache(),
            onContinue: onContinue
        )
    }

    /// Race setup with a draft, for SwiftUI previews and view-model tests.
    static func previewRaceSetupViewModel(
        draft: RaceSetupDraft = .custom,
        onBuild: @escaping @MainActor (RaceSetup, PlanSource) -> Void = { _, _ in }
    ) -> RaceSetupViewModel {
        RaceSetupViewModel(
            draft: draft,
            validateRaceSetup: ValidateRaceSetup(clock: clock, calendar: .current),
            calendar: .current,
            onBuild: onBuild,
            onBack: {}
        )
    }

    /// Home and Calendar for the seed plan with `-fakeRuns` runs on a given day
    /// ("yyyy-MM-dd"), all in memory. For SwiftUI previews.
    /// `sleep` names a `FakeSleepScenario` ("normal", "short"...) and `recovery` a
    /// `FakeRecoveryScenario` ("mock", "strained"...), so views need not import Infrastructure.
    static func previewMainScreens(
        today: String,
        sleep scenarioName: String = "normal",
        recovery recoveryName: String = "mock",
        startTab: MainScreens.Tab = .home
    ) -> MainScreens {
        let sleep = FakeSleepScenario(rawValue: scenarioName) ?? .normal
        let recovery = FakeRecoveryScenario(rawValue: recoveryName) ?? .mock
        let clock: any Clock = LocalDate(today).map { ShiftedClock(base: SystemClock(), today: $0, calendar: .current) } ?? SystemClock()
        let plans: any PlanRepository = (try? GRDBPlanRepository.inMemory(seededWith: SeedPlan.plan(createdAt: clock.now()), clock: clock))
            ?? UnavailablePlanRepository()
        let runs = FakeRunsHealthDataSource(
            base: InMemoryHealthDataSource(clock: clock), activePlan: { await plans.loadActive() }, clock: clock, calendar: .current
        )
        let withSleep = FakeSleepHealthDataSource(base: runs, scenario: sleep, clock: clock, calendar: .current)
        let source = FakeRecoveryHealthDataSource(base: withSleep, scenario: recovery, clock: clock, calendar: .current)
        let stores = HomeStores(
            runs: InMemoryCompletedRunsCache(),
            sleep: InMemorySleepCache(FakeSleepHealthDataSource.seededCache(sleep, clock: clock, calendar: .current)),
            recovery: InMemoryRecoveryCache(FakeRecoveryHealthDataSource.seededCache(recovery, clock: clock, calendar: .current))
        )
        let models = LanguageModels.fake(.ok, clock: clock)
        let database = try? DatabaseProvider.inMemory()
        let notes = NoteInputs(
            notes: database.map { GRDBCoachNoteRepository(database: $0) as any CoachNoteRepository } ?? UnavailableCoachNoteRepository(),
            analyses: InMemoryWorkoutAnalysisRepository(),
            detail: { plans in FakeWorkoutDetailSource(scenario: .tempo, runs: { [] }, activePlan: { await plans.loadActive() }) },
            profile: { FakeHeartRateProfile.profile },
            models: .fake(.ok, spend: models.spend, clock: clock),
            settings: models.spend.settings,
            preferenceOverride: .ruleBased
        )
        let feedback = FeedbackInputs(
            feedback: database.map { GRDBWorkoutFeedbackRepository(database: $0) as any WorkoutFeedbackRepository }
                ?? UnavailableWorkoutFeedbackRepository(),
            adjustments: UnavailablePlanAdjustmentRepository(),
            adjust: AdjustModels(adjusting: models.adjusting, availability: models.availability, models: []),
            strengthHealth: { _ in runs },
            asksAutomatically: false
        )
        return makeMain(
            plans: plans, stores: stores, health: source, clock: clock, launch: MainLaunch(startTab: startTab),
            lab: LabInputs(models: models, snapshots: InMemorySnapshotCache()), notes: notes, feedback: feedback, onNoPlan: {}
        )
    }

    /// The connect screen, for SwiftUI previews.
    static func previewConnectHealthViewModel() -> ConnectHealthViewModel {
        ConnectHealthViewModel(
            requestHealthAccess: RequestHealthAccess(health: InMemoryHealthDataSource(clock: clock)),
            onFinished: {}
        )
    }
    #endif

    // MARK: Health environment

    #if DEBUG
    /// DEBUG launch arguments for fake Health data. None of this ships in release.
    ///
    /// - `-useInMemoryStores`: sample data instead of HealthKit (UI tests).
    /// - `-persona <id>`: a made-up persona instead of HealthKit.
    /// - `-simulate <normal|slow|locked|empty|denied>`: how the fake data behaves.
    /// - `-authorized`: the fake starts as already asked, skipping Connect Health.
    /// - `-resetCache`: delete the cache file for this data source at launch.
    /// - `-today yyyy-MM-dd`: the clock reads this date (at the real time of day).
    /// - `-seedPlan`: an in-memory database seeded with the fixed plan (`SeedPlan`) and fake Health, so Home opens at once.
    /// - `-fakeRuns`: completed runs derived from the active plan as seeded (original dates), kept in memory.
    /// - `-fakeSleep <scenario>`: sleep from a `FakeSleepScenario`, kept in memory.
    /// - `-fakeRecovery <scenario>`: HRV and resting heart rate from a `FakeRecoveryScenario`, kept in memory.
    /// - `-startTab <home|calendar>`: the tab the main app opens on.
    /// - `-calendarMonth yyyy-MM`: the month the Calendar opens on (clamped to the plan).
    /// - `-planGenerator <auto|template|onDevice|pcc.light|pcc.moderate|pcc.deep|anthropic.haiku55|anthropic.sonnet55|anthropic.opus55|anthropic.fable51>`:
    ///   the generator for Race setup -> Generating (Claude runs are recorded with purpose planGeneration).
    /// - `-planFallback`: a model generator falls back to the template.
    /// - `-fakeLLM <ok|invalidPlan|unavailable|quota|slow|anthropicOk|noKey|badKey|credits|rateLimited>`: canned model
    ///   answers (no FoundationModels, no network), with an in-memory ledger, settings and secret store.
    /// - `-planDelay <seconds>`: the template waits this long first (0 or absent: no wait).
    /// - `-fakeWorkoutDetail <tempo|easyDrift|noHr|paused|laps|flat|tempoVaried>`: canned workout detail for every run (no HealthKit).
    /// - `-fakeCoachNote <ok|slow|fail|rules>`: canned coach notes (fail throws once; rules forces the rule-based note).
    /// - `-fakeHeartRateHigh`: easy runs average 153 bpm instead of 139.
    /// - `-coachModel <auto|template|onDevice|pcc.light|pcc.moderate|pcc.deep|anthropic.haiku55|...>`: the coach notes'
    ///   model for this run, over the Lab's choice.
    /// - `-allowAnyDistance`: race setup and plan creation accept any distance up to 250 km (old fixtures, ultras).
    /// - `-feedbackPopup`: with fake Health, the after-workout popup opens by itself (it always does with real Health).
    /// - `-fakeAdjust <ok|fail>`: canned suggested changes (fail: the rules write them); without it, fakes use the rules.
    struct DebugOptions {
        let usesFakes: Bool
        let personaID: String?
        let mode: SimulationMode
        let startsAuthorized: Bool
        let resetsCache: Bool
        let today: LocalDate?
        let seedsPlan: Bool
        let fakesRuns: Bool
        let sleepScenario: FakeSleepScenario?
        let recoveryScenario: FakeRecoveryScenario?
        let startTab: MainScreens.Tab
        let calendarMonth: YearMonth?
        let planGenerator: PlanGeneratorKind
        let planFallback: Bool
        let fakeLLM: FakeLLMScenario?
        let planDelay: Double?
        let workoutDetailScenario: FakeWorkoutDetailScenario?
        let fakeCoachNote: FakeCoachNoteScenario?
        let fakeHeartRateHigh: Bool
        let coachModel: CoachModelPreference?
        let feedbackPopup: Bool
        let fakeAdjust: FakeAdjustScenario?
        let allowsAnyDistance: Bool

        init(arguments: [String]) {
            func value(after flag: String) -> String? {
                arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            }
            personaID = value(after: "-persona")
            let simulate = value(after: "-simulate").flatMap(SimulationMode.init(rawValue:))
            mode = simulate ?? .normal
            seedsPlan = arguments.contains("-seedPlan")
            fakesRuns = arguments.contains("-fakeRuns")
            sleepScenario = value(after: "-fakeSleep").flatMap(FakeSleepScenario.init(rawValue:))
            recoveryScenario = value(after: "-fakeRecovery").flatMap(FakeRecoveryScenario.init(rawValue:))
            startTab = value(after: "-startTab") == "calendar" ? .calendar : .home
            calendarMonth = value(after: "-calendarMonth").flatMap { YearMonth($0) }
            let planGeneratorArgument = value(after: "-planGenerator").flatMap(PlanGeneratorKind.init(id:))
            planFallback = arguments.contains("-planFallback")
            fakeLLM = value(after: "-fakeLLM").flatMap(FakeLLMScenario.init(rawValue:))
            planDelay = value(after: "-planDelay").flatMap(Double.init)
            workoutDetailScenario = value(after: "-fakeWorkoutDetail").flatMap(FakeWorkoutDetailScenario.init(rawValue:))
            fakeCoachNote = value(after: "-fakeCoachNote").flatMap(FakeCoachNoteScenario.init(rawValue:))
            fakeHeartRateHigh = arguments.contains("-fakeHeartRateHigh")
            coachModel = value(after: "-coachModel").flatMap(CoachModelPreference.init(id:))
            feedbackPopup = arguments.contains("-feedbackPopup")
            allowsAnyDistance = arguments.contains("-allowAnyDistance")
            fakeAdjust = value(after: "-fakeAdjust").flatMap(FakeAdjustScenario.init(rawValue:))
            today = value(after: "-today").flatMap { LocalDate($0) }
            usesFakes = arguments.contains("-useInMemoryStores") || personaID != nil || simulate != nil || seedsPlan
            // Fakes build plans with the template unless a generator is asked for; real Health uses Automatic.
            planGenerator = planGeneratorArgument ?? (usesFakes ? .template : .automatic)
            startsAuthorized = arguments.contains("-authorized") || seedsPlan
            resetsCache = arguments.contains("-resetCache")
        }
    }
    #endif

    /// The Health source and the cache that belongs to it. Release builds always use
    /// HealthKit and the real cache file. DEBUG fakes get their own cache file each,
    /// so persona data never mixes with real data.
    @MainActor
    private final class HealthEnvironment {
        private struct Built {
            let key: String
            let source: any HealthDataSource
            let cache: any SnapshotCache
        }

        private var built: Built?
        #if DEBUG
        private let options: DebugOptions
        private var personaID: String?
        private var hasResetCache = false

        init(options: DebugOptions) {
            self.options = options
            self.personaID = options.personaID
        }
        #else
        init() {}
        #endif

        var source: any HealthDataSource { current().source }
        var cache: any SnapshotCache { current().cache }

        var usesRealHealth: Bool {
            #if DEBUG
            !options.usesFakes
            #else
            true
            #endif
        }

        var personaChoices: [String] {
            #if DEBUG
            Persona.all.map(\.id)
            #else
            []
            #endif
        }

        /// DEBUG only: switch to a persona (`nil` = back to the launch choice).
        func choosePersona(_ id: String?) {
            #if DEBUG
            personaID = id
            #endif
        }

        private func current() -> Built {
            #if DEBUG
            let usesFakes = options.usesFakes || personaID != nil
            let key = usesFakes ? (personaID ?? "sample") : "live"
            #else
            let key = "live"
            #endif
            if let built, built.key == key { return built }
            let fresh = build(key: key)
            built = fresh
            return fresh
        }

        private func build(key: String) -> Built {
            #if DEBUG
            if key != "live" {
                return buildFake(key: key)
            }
            #endif
            let cache = FileSnapshotCache()
            #if DEBUG
            resetIfAsked(cache)
            #endif
            return Built(key: key, source: HealthKitDataSource(clock: CompositionRoot.clock, calendar: .current), cache: cache)
        }

        #if DEBUG
        private func buildFake(key: String) -> Built {
            let clock = CompositionRoot.clock
            let base: any HealthDataSource = Persona.named(key).map { PersonaHealthDataSource(persona: $0, clock: clock) }
                ?? InMemoryHealthDataSource(clock: clock)
            let file = FileSnapshotCache(fileName: "HealthSnapshot-debug-\(key).json")
            resetIfAsked(file)

            let cache: any SnapshotCache = options.mode == .locked
                ? SeededSnapshotCache(underlying: file) {
                    // What a normal read of the same fake would have cached.
                    let memory = InMemorySnapshotCache()
                    for await _ in RefreshHealthSnapshot(health: base, cache: memory, clock: clock).execute() {}
                    return await memory.load()
                }
                : file
            return Built(
                key: key,
                source: SimulatedHealthDataSource(base: base, mode: options.mode, alreadyRequested: options.startsAuthorized),
                cache: cache
            )
        }

        private func resetIfAsked(_ cache: FileSnapshotCache) {
            guard options.resetsCache, !hasResetCache else { return }
            hasResetCache = true
            cache.clear()
        }
        #endif
    }
}
