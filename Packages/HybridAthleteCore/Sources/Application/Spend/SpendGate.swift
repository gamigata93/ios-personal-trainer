import Foundation
import Domain

/// Decides whether a model call may be sent. Apple's models always pass. A Claude
/// call needs consent (except the key test, which sends no health data), a saved
/// key, a readable price table and a worst case inside both spend caps. Runs
/// BEFORE anything is sent, so a blocked call is never recorded.
public struct SpendGate: Sendable {
    public static let consentText = "Allow Claude runs first."
    public static let priceTableText = "Price table unavailable. Claude runs are blocked."
    public static let ledgerText = "Couldn't read the usage history, so the monthly limit can't be checked. Claude runs are blocked."

    private let settings: any LabSettingsStore
    private let secrets: any SecretStore
    private let prices: any PriceTableProvider
    private let ledger: any LLMUsageLedger
    private let clock: any Clock
    private let calendar: Calendar

    public init(
        settings: any LabSettingsStore,
        secrets: any SecretStore,
        prices: any PriceTableProvider,
        ledger: any LLMUsageLedger,
        clock: any Clock,
        calendar: Calendar
    ) {
        self.settings = settings
        self.secrets = secrets
        self.prices = prices
        self.ledger = ledger
        self.clock = clock
        self.calendar = calendar
    }

    /// Throws the reason a call is blocked: `.spendLimit(sentence)` or `.unavailable(.needsAPIKey)`.
    public func check(model: ModelChoice, purpose: LLMCallPurpose, promptCharacters: Int) async throws(LLMError) {
        guard case .anthropic(let claude) = model else { return }
        let settings = await settings.load()
        if purpose != .keyTest, !settings.consentGiven { throw .spendLimit(Self.consentText) }
        guard await secrets.hasSecret(.anthropicAPIKey) else { throw .unavailable(.needsAPIKey) }

        let estimated = SpendGuard.estimatedInputTokens(promptCharacters: promptCharacters)
        guard let rates = prices.priceTable()?.rates(modelApiId: claude.apiId, promptTokens: estimated) else {
            throw .spendLimit(Self.priceTableText)
        }
        let now = clock.now()
        let records: [LLMCallRecord]
        do {
            records = try await ledger.records(since: calendar.dateInterval(of: .month, for: now)?.start)
        } catch {
            throw .spendLimit(Self.ledgerText)
        }
        let worstCase = SpendGuard.worstCaseMicros(
            estimatedInputTokens: estimated,
            maxOutputTokens: purpose.task.maxOutputTokens,
            rates: rates
        )
        let monthSpent = SpendSummary(records: records, now: now, calendar: calendar).thisMonth.micros
        if case .deny(let reason) = SpendGuard.decide(worstCaseMicros: worstCase, monthSpentMicros: monthSpent, caps: settings.caps) {
            throw .spendLimit(reason)
        }
    }
}

/// Checks the gate before each coach note is sent. Used by the Lab and the real flow alike.
public struct SpendGatedCoachingModel: CoachingModel {
    private let inner: any CoachingModel
    private let gate: SpendGate

    public init(inner: any CoachingModel, gate: SpendGate) {
        self.inner = inner
        self.gate = gate
    }

    public func writeWorkoutNote(_ request: CoachNoteRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        let characters = CoachNotePromptBuilder.build(request).fullText.count
        try await gate.check(model: model, purpose: purpose, promptCharacters: characters)
        return try await inner.writeWorkoutNote(request, model: model, purpose: purpose)
    }
}

/// Checks the gate before each plan draft is sent, so every retry is checked too.
public struct SpendGatedPlanDraftingModel: PlanDraftingModel {
    private let inner: any PlanDraftingModel
    private let gate: SpendGate

    public init(inner: any PlanDraftingModel, gate: SpendGate) {
        self.inner = inner
        self.gate = gate
    }

    public func draftPlan(_ request: PlanRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> PlanDraftResult {
        let characters = PlanPromptBuilder.build(request).fullText.count
        try await gate.check(model: model, purpose: purpose, promptCharacters: characters)
        return try await inner.draftPlan(request, model: model, purpose: purpose)
    }
}
