#if DEBUG
import Foundation
import Observation
import Domain
import Application

/// DEBUG only: compare Apple's models and Claude on real data. Runs one experiment
/// on one model, or on every available model of the same provider one after
/// another. Never saves anything but the usage ledger (token counts and costs).
@MainActor
@Observable
final class ModelLabViewModel: Identifiable {
    enum Experiment: String, CaseIterable, Identifiable {
        case coachNote, planDraft
        var id: String { rawValue }
        var title: String { self == .coachNote ? "Workout note" : "Plan draft" }
    }

    /// Which run the Workout note uses: the newest completed session, one picked
    /// from the list, or the fixed sample (a 5.0 km tempo).
    enum CoachInput: Hashable {
        case latest
        case session(String)
        case sample
    }

    /// One completed session in the picker.
    struct SessionChoice: Identifiable, Equatable {
        let id: String
        /// "Mon 26 Oct · Tempo run".
        let title: String
    }

    /// One finished run, newest first.
    struct Card: Identifiable, Equatable {
        /// 1-based, in the order the runs started.
        let id: Int
        let result: ExperimentResult
        let errorText: String?
        let json: String?
    }

    /// A run in progress.
    struct Running: Equatable {
        let id: Int
        let model: ModelChoice
    }

    var selectedModel: ModelChoice = .onDevice {
        didSet { if oldValue != selectedModel { Task { await loadStatus(selectedModel) } } }
    }
    var experiment: Experiment = .coachNote
    var coachInput: CoachInput = .latest

    private(set) var statuses: [ModelChoice: ModelStatus] = [:]
    private(set) var cards: [Card] = []
    private(set) var running: Running?
    /// Why "My latest completed session" cannot run, when it cannot.
    private(set) var latestUnavailableText: String?

    /// Which model the real coach notes use.
    private(set) var coachPreference: CoachModelPreference = .automatic

    private let runner: RunModelExperiment
    private let prepareNote: PrepareWorkoutNote
    private let buildPlanRequest: BuildLabPlanRequest
    private let plans: ActivePlanStore
    private let runs: CompletedRunsStore
    private let settings: LabSpendSettings
    private let errorText: LLMErrorText
    private let today: () -> LocalDate
    /// Costs, key, consent and caps.
    let claude: ClaudeLabViewModel
    /// The run in progress (also one started after consent).
    private(set) var task: Task<Void, Never>?
    private var nextId = 1

    init(
        runner: RunModelExperiment,
        prepareNote: PrepareWorkoutNote,
        buildPlanRequest: BuildLabPlanRequest,
        plans: ActivePlanStore,
        runs: CompletedRunsStore,
        settings: LabSpendSettings,
        errorText: LLMErrorText,
        today: @escaping () -> LocalDate,
        claude: ClaudeLabViewModel
    ) {
        self.runner = runner
        self.prepareNote = prepareNote
        self.buildPlanRequest = buildPlanRequest
        self.plans = plans
        self.runs = runs
        self.settings = settings
        self.errorText = errorText
        self.today = today
        self.claude = claude
        claude.onKeyChange = { [weak self] in
            for model in ModelChoice.claude { await self?.loadStatus(model) }
        }
    }

    var status: ModelStatus? { statuses[selectedModel] }
    var isRunning: Bool { running != nil }

    /// "Below limit", "Nearing usage limit", "Limit reached, resets 14:30".
    func quotaLine(_ quota: QuotaStatus) -> String { errorText.quotaLine(quota) }

    func appear() async {
        await plans.loadIfNeeded()
        await runs.loadCached()
        await claude.load()
        coachPreference = await settings.load().coachModelPreference
        for model in ModelChoice.all {
            await loadStatus(model)
        }
    }

    private func loadStatus(_ model: ModelChoice) async {
        statuses[model] = await runner.status(for: model)
    }

    // MARK: Running

    /// The selected experiment on the selected model. A Claude model asks for
    /// consent first (nil is returned; the run starts after "Allow").
    @discardableResult
    func run() -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        let model = selectedModel
        guard model.provider == .apple || claude.settings.consentGiven else {
            claude.whenAllowed(model) { [weak self] in self?.run() }
            return nil
        }
        let task = Task {
            guard let experiment = await makeExperiment() else { return }
            await run(experiment, on: [model])
        }
        self.task = task
        return task
    }

    /// The selected experiment on every available model of the selected model's
    /// provider (Apple or Claude, never both), one after another.
    @discardableResult
    func runAll() -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        let provider = selectedModel.provider
        guard provider == .apple || claude.settings.consentGiven else {
            claude.whenAllowed(selectedModel) { [weak self] in self?.runAll() }
            return nil
        }
        let task = Task {
            guard let experiment = await makeExperiment() else { return }
            await run(experiment, on: await runner.availableModels(provider))
        }
        self.task = task
        return task
    }

    func cancel() {
        task?.cancel()
    }

    private func run(_ experiment: ModelExperiment, on models: [ModelChoice]) async {
        for model in models {
            if Task.isCancelled { break }
            let id = nextId
            nextId += 1
            running = Running(id: id, model: model)
            let result = await runner.run(experiment, model: model)
            statuses[model] = result.status
            cards.insert(Card(
                id: id,
                result: result,
                errorText: result.error.map(errorText.message),
                json: ExperimentResultJSON.string(result, errorText: errorText)
            ), at: 0)
            running = nil
            await claude.refresh()
        }
        running = nil
    }

    /// "Run all Apple models" or "Run all Claude models".
    var runAllTitle: String {
        selectedModel.provider == .apple ? "Run all Apple models" : "Run all Claude models"
    }

    // MARK: Workout note input

    /// Completed sessions, newest first.
    var sessionChoices: [SessionChoice] {
        guard let plan = plans.plan else { return [] }
        let progress = PlanProgress(plan: plan, runs: runs.result.runs, today: today())
        return plan.sessions
            .filter { $0.date <= today() && progress.matches[$0.id] != nil }
            .sorted { $0.date > $1.date }
            .map { SessionChoice(id: $0.id, title: "\(HomeFormat.shortDate($0.date)) · \($0.name)") }
    }

    /// The session the Workout note runs on; nil for the sample or when none is completed.
    var selectedSessionID: String? {
        switch coachInput {
        case .sample: nil
        case .session(let id): id
        case .latest: sessionChoices.first?.id
        }
    }

    /// Nil (with `latestUnavailableText` set) when no completed session can be used.
    private func makeExperiment() async -> ModelExperiment? {
        switch experiment {
        case .planDraft:
            return .planDraft(await buildPlanRequest.execute(plan: plans.plan))
        case .coachNote:
            if coachInput == .sample { return .workoutNote(.sampleTempo) }
            guard let plan = plans.plan else {
                latestUnavailableText = "There is no plan yet. Use the sample."
                return nil
            }
            guard let id = selectedSessionID,
                  case .ready(let prepared) = try? await prepareNote.execute(plan: plan, runs: runs.result.runs, sessionId: id)
            else {
                latestUnavailableText = "No completed session with a run yet. Use the sample."
                return nil
            }
            latestUnavailableText = nil
            return .workoutNote(prepared.request)
        }
    }

    // MARK: Coach notes model

    /// "Use for coach notes": the real notes use the selected model from now on.
    func useForCoachNotes() async {
        await setCoachPreference(.model(selectedModel))
    }

    /// The "Automatic" chip: Private Cloud Compute, then on-device, then the rules.
    func useAutomaticForCoachNotes() async {
        await setCoachPreference(.automatic)
    }

    private func setCoachPreference(_ preference: CoachModelPreference) async {
        await settings.setCoachModelPreference(preference)
        coachPreference = preference
    }

    /// "Coach notes use: Automatic".
    var coachPreferenceText: String { "Coach notes use: \(coachPreference.displayName)" }
}
#endif
