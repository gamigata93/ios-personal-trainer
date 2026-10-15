#if DEBUG
import Foundation
import Observation
import Domain
import Application

/// DEBUG only: the Claude parts of the Model Lab: what was spent (an estimate),
/// the API key, consent, the spend caps and "What would this cost?". The full key
/// is never held here except while it is being typed; only its last 4
/// characters come back.
@MainActor
@Observable
final class ClaudeLabViewModel {
    enum CapTone { case normal, warning, over }

    var period: SpendPeriod = .thisMonth {
        didSet { if oldValue != period { Task { await refresh() } } }
    }
    private(set) var overview: SpendOverview = .empty(.thisMonth)
    /// Nil when there is no price table.
    private(set) var projection: [CostProjectionRow]?
    private(set) var settings = LabSettings()
    private(set) var keyStatus: APIKeyStatus = .none
    /// The SecureField's text; cleared after Save. Never pre-filled.
    var keyInput = ""
    /// The last Save, Test or Remove outcome.
    private(set) var keyMessage: String?
    private(set) var isTestingKey = false
    var perRunText = ""
    var perMonthText = ""
    private(set) var capsError: String?
    /// The consent sheet is up.
    var showsConsent = false
    /// Called after the key is saved or removed (availability changes).
    var onKeyChange: (@MainActor () async -> Void)?

    private let getSpendOverview: GetSpendOverview
    private let projectCosts: ProjectCosts
    private let clearUsageHistory: ClearUsageHistory
    private let settingsStore: LabSpendSettings
    private let manageKey: ManageAnthropicKey
    private let testKeyUseCase: TestAnthropicKey
    private let priceLineUseCase: GetClaudePriceLine
    private let exportUsage: @MainActor () async -> String?
    private let errorText: LLMErrorText
    private let locale: Locale
    private var afterConsent: (@MainActor () -> Void)?

    init(
        getSpendOverview: GetSpendOverview,
        projectCosts: ProjectCosts,
        clearUsageHistory: ClearUsageHistory,
        settings: LabSpendSettings,
        manageKey: ManageAnthropicKey,
        testKey: TestAnthropicKey,
        priceLine: GetClaudePriceLine,
        exportUsage: @escaping @MainActor () async -> String?,
        errorText: LLMErrorText,
        locale: Locale
    ) {
        self.getSpendOverview = getSpendOverview
        self.projectCosts = projectCosts
        self.clearUsageHistory = clearUsageHistory
        self.settingsStore = settings
        self.manageKey = manageKey
        self.testKeyUseCase = testKey
        self.priceLineUseCase = priceLine
        self.exportUsage = exportUsage
        self.errorText = errorText
        self.locale = locale
    }

    func load() async {
        settings = await settingsStore.load()
        perRunText = DollarInput.text(micros: settings.caps.perRunMicros)
        perMonthText = DollarInput.text(micros: settings.caps.monthlyMicros)
        keyStatus = await manageKey.status()
        await refresh()
    }

    /// The cost card and the projection, after a run or a change.
    func refresh() async {
        overview = await getSpendOverview.execute(period)
        projection = await projectCosts.execute(settings.scenario)
    }

    // MARK: Consent

    /// Runs `action` now, or once "Allow" is tapped on the consent sheet.
    func whenAllowed(_ model: ModelChoice, _ action: @escaping @MainActor () -> Void) {
        guard model.provider == .anthropic, !settings.consentGiven else { return action() }
        afterConsent = action
        showsConsent = true
    }

    func allow() async {
        await settingsStore.grantConsent()
        settings.consentGiven = true
        showsConsent = false
        let action = afterConsent
        afterConsent = nil
        action?()
    }

    func decline() {
        showsConsent = false
        afterConsent = nil
    }

    // MARK: Key

    func saveKey() async {
        do {
            keyStatus = try await manageKey.save(keyInput)
            keyInput = ""
            keyMessage = "Key saved."
        } catch .empty {
            keyMessage = "Paste a key first."
        } catch {
            keyMessage = "Couldn't save the key."
        }
        await onKeyChange?()
    }

    func removeKey() async {
        do {
            try await manageKey.remove()
            keyStatus = .none
            keyMessage = "Key removed."
        } catch {
            keyMessage = "Couldn't remove the key."
        }
        await onKeyChange?()
    }

    /// "Key works · 0.4 s · <$0.0001", or why it failed.
    func testKey() async {
        guard !isTestingKey else { return }
        isTestingKey = true
        defer { isTestingKey = false }
        do {
            let result = try await testKeyUseCase.execute()
            let latency = LLMUsage(latencyMs: result.latencyMs).latencyText
            keyMessage = "Key works · \(latency) · " + CostFormatter.text(micros: result.costMicros ?? 0)
        } catch {
            keyMessage = errorText.message(error)
        }
        await refresh()
    }

    // MARK: Caps and scenario

    /// Saves a typed per-run cap when it is a positive amount.
    func updatePerRun(_ text: String) async {
        perRunText = text
        guard let micros = DollarInput.micros(text) else { return capsError = "Enter an amount such as 0.25." }
        capsError = nil
        settings.caps = SpendCaps(perRunMicros: micros, monthlyMicros: settings.caps.monthlyMicros)
        await settingsStore.setCaps(settings.caps)
    }

    func updatePerMonth(_ text: String) async {
        perMonthText = text
        guard let micros = DollarInput.micros(text) else { return capsError = "Enter an amount such as 5.00." }
        capsError = nil
        settings.caps = SpendCaps(perRunMicros: settings.caps.perRunMicros, monthlyMicros: micros)
        await settingsStore.setCaps(settings.caps)
    }

    func setScenario(plans: Int, notes: Int) async {
        settings.scenario = CostScenario(plansPerMonth: plans, notesPerMonth: notes)
        await settingsStore.setScenario(settings.scenario)
        projection = await projectCosts.execute(settings.scenario)
    }

    // MARK: History

    func clearHistory() async {
        try? await clearUsageHistory.execute()
        await refresh()
    }

    func usageJSON() async -> String? {
        await exportUsage()
    }

    // MARK: Texts

    var totalText: String { CostFormatter.text(micros: overview.totals.micros) }

    /// "Estimated from token usage reported by the SDK · since 14 Oct 2026".
    var captionText: String {
        let since = overview.firstRecordDate.map { "since " + $0.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) }
        return "Estimated from token usage reported by the SDK · " + (since ?? "no calls yet")
    }

    /// "3 calls · 4,205 tokens in · 5,150 tokens out".
    var statsText: String {
        let totals = overview.totals
        return "\(totals.calls) \(totals.calls == 1 ? "call" : "calls") · \(number(totals.tokensIn)) tokens in · \(number(totals.tokensOut)) tokens out"
    }

    var staleText: String? {
        guard overview.pricesAreStale, let date = overview.pricesLastVerified else { return nil }
        return "Prices last verified \(date). Check platform.claude.com/docs/en/about-claude/pricing."
    }

    var priceTableMissingText: String? {
        overview.pricesLastVerified == nil ? SpendGate.priceTableText : nil
    }

    func rowText(_ row: SpendModelRow) -> String {
        "\(row.calls) \(row.calls == 1 ? "call" : "calls") · " + CostFormatter.text(micros: row.micros)
    }

    /// "This month, 3 cents spent. 2 calls, 4,205 tokens in, 5,150 tokens out."
    var costAccessibilityText: String {
        let rows = overview.rows.map { "\($0.name), \($0.calls) \($0.calls == 1 ? "call" : "calls"), \(CostFormatter.spokenText(micros: $0.micros))" }
        return "\(period.title), \(CostFormatter.spokenText(micros: overview.totals.micros)) spent. "
            + statsText.replacingOccurrences(of: " · ", with: ", ") + "."
            + (rows.isEmpty ? "" : " " + rows.joined(separator: ". ") + ".")
    }

    /// "This month: $0.028 of $5.00".
    var capLine: String {
        "This month: \(CostFormatter.text(micros: overview.monthSpentMicros)) of \(CostFormatter.limitText(micros: settings.caps.monthlyMicros))"
    }

    /// 0...1 for the bar.
    var capShare: Double {
        guard settings.caps.monthlyMicros > 0 else { return 1 }
        return min(1, Double(overview.monthSpentMicros) / Double(settings.caps.monthlyMicros))
    }

    var capTone: CapTone {
        let share = settings.caps.monthlyMicros > 0 ? Double(overview.monthSpentMicros) / Double(settings.caps.monthlyMicros) : 1
        if share >= 1 { return .over }
        return share >= LLMSpendRules.capWarningShare ? .warning : .normal
    }

    /// "This month, 3 cents spent of a 5 dollar limit. Per run limit 25 cents."
    var capAccessibilityText: String {
        "This month, \(CostFormatter.spokenText(micros: overview.monthSpentMicros)) spent of "
            + "\(CostFormatter.spokenLimit(micros: settings.caps.monthlyMicros)). "
            + "Per run limit \(CostFormatter.spokenText(micros: settings.caps.perRunMicros))."
    }

    var outputCapText: String {
        "Claude's output is capped at \(number(LLMSpendRules.coachNoteMaxOutputTokens)) tokens for a coach note "
            + "and \(number(LLMSpendRules.planDraftMaxOutputTokens)) for a plan draft."
    }

    func priceLine(_ model: ModelChoice) -> String? {
        guard case .anthropic(let claude) = model else { return nil }
        return priceLineUseCase.execute(claude)
    }

    /// "Plan draft $0.028 · Coach note $0.0030", or "Run it once to see a number".
    func projectionLine(_ row: CostProjectionRow) -> String {
        func part(_ micros: Int64?) -> String { micros.map { CostFormatter.text(micros: $0) } ?? CostProjection.noDataText }
        return "Plan draft \(part(row.planDraftMicros)) · Coach note \(part(row.coachNoteMicros))"
    }

    /// "≈ $0.145 a month".
    func monthlyLine(_ row: CostProjectionRow) -> String {
        row.monthlyMicros.map { "≈ \(CostFormatter.text(micros: $0)) a month" } ?? CostProjection.noDataText
    }

    private func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}
#endif
