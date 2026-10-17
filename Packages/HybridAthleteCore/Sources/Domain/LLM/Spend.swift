import Foundation

/// Why a model was called. Stored with every ledger record.
public enum LLMCallPurpose: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// labCoachNote is the Lab's "Workout note"; workoutNote the real flow's note.
    case labCoachNote, labPlanDraft, planGeneration, coachNote, keyTest, workoutNote

    public var task: LLMTask {
        switch self {
        case .labCoachNote, .coachNote, .workoutNote: .coachNote
        case .labPlanDraft, .planGeneration: .planDraft
        case .keyTest: .keyTest
        }
    }
}

/// What kind of answer a call asks for; sets the output ceiling.
public enum LLMTask: Sendable, Equatable {
    case coachNote, planDraft, keyTest

    public var maxOutputTokens: Int {
        switch self {
        case .coachNote: LLMSpendRules.coachNoteMaxOutputTokens
        case .planDraft: LLMSpendRules.planDraftMaxOutputTokens
        case .keyTest: LLMSpendRules.keyTestMaxOutputTokens
        }
    }
}

/// Spend constants, in one place.
public enum LLMSpendRules {
    /// Output ceilings: sent to Claude as max_tokens (the package honors them), and
    /// the worst case the spend guard assumes. Thinking tokens count against them.
    /// The four-part workout note (up to 1,180 characters) plus light thinking.
    public static let coachNoteMaxOutputTokens = 1_000
    public static let planDraftMaxOutputTokens = 4_000
    public static let keyTestMaxOutputTokens = 8
    /// Conservative: newer tokenizers produce more tokens per character, so
    /// estimates divide by 3 rather than the usual 4.
    public static let charactersPerToken = 3
    /// The key test's whole prompt.
    public static let keyTestPrompt = "Reply with OK."
    /// The model the key test runs on (the cheapest).
    public static let keyTestModel = AnthropicModel.haiku55
    public static let defaultPerRunCapMicros: Int64 = 250_000
    public static let defaultMonthlyCapMicros: Int64 = 5_000_000
    /// The cap bar turns amber here, and red at 100%.
    public static let capWarningShare = 0.8
}

/// One model call in the usage ledger: token counts and cost only. It never
/// holds prompt text, output text or the API key.
public struct LLMCallRecord: Sendable, Equatable, Codable {
    /// Nil until stored.
    public let id: Int64?
    public let createdAt: Date
    public let provider: LLMProvider
    /// `ModelChoice.ledgerModelId`: the API id for Claude, the choice id for Apple.
    public let modelId: String
    public let purpose: LLMCallPurpose
    public let success: Bool
    /// `LLMError.kind` for a failed call.
    public let errorKind: String?
    public let usage: TokenUsage
    public let latencyMs: Int
    /// Claude only: estimated from the price table.
    public let costMicros: Int64?
    public let priceTableVersion: String

    public init(
        id: Int64? = nil,
        createdAt: Date,
        provider: LLMProvider,
        modelId: String,
        purpose: LLMCallPurpose,
        success: Bool,
        errorKind: String? = nil,
        usage: TokenUsage,
        latencyMs: Int,
        costMicros: Int64?,
        priceTableVersion: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.provider = provider
        self.modelId = modelId
        self.purpose = purpose
        self.success = success
        self.errorKind = errorKind
        self.usage = usage
        self.latencyMs = latencyMs
        self.costMicros = costMicros
        self.priceTableVersion = priceTableVersion
    }

    public func with(id: Int64) -> LLMCallRecord {
        LLMCallRecord(
            id: id, createdAt: createdAt, provider: provider, modelId: modelId, purpose: purpose, success: success,
            errorKind: errorKind, usage: usage, latencyMs: latencyMs, costMicros: costMicros, priceTableVersion: priceTableVersion
        )
    }
}

// MARK: - Summary

public enum SpendPeriod: String, Sendable, CaseIterable, Identifiable {
    case today, thisMonth, allTime

    public var id: String { rawValue }

    /// "Today", "This month", "All time".
    public var title: String {
        switch self {
        case .today: "Today"
        case .thisMonth: "This month"
        case .allTime: "All time"
        }
    }
}

public struct SpendTotals: Sendable, Equatable {
    public let micros: Int64
    public let calls: Int
    /// Every input token, cached or not.
    public let tokensIn: Int
    public let tokensOut: Int

    public static let zero = SpendTotals(micros: 0, calls: 0, tokensIn: 0, tokensOut: 0)

    public init(micros: Int64, calls: Int, tokensIn: Int, tokensOut: Int) {
        self.micros = micros
        self.calls = calls
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
    }

    init(_ records: [LLMCallRecord]) {
        self.init(
            micros: records.reduce(0) { $0 + ($1.costMicros ?? 0) },
            calls: records.count,
            tokensIn: records.reduce(0) { $0 + $1.usage.promptTokens },
            tokensOut: records.reduce(0) { $0 + $1.usage.output }
        )
    }
}

public struct SpendModelRow: Sendable, Equatable, Identifiable {
    public let modelId: String
    public let name: String
    public let calls: Int
    public let micros: Int64

    public var id: String { modelId }
}

/// What Claude cost: today, this month and all time, with a row per model. Only
/// Anthropic records count (Apple's models are free). Day and month boundaries
/// use the injected calendar and its time zone.
public struct SpendSummary: Sendable, Equatable {
    public let today: SpendTotals
    public let thisMonth: SpendTotals
    public let allTime: SpendTotals
    /// The earliest Anthropic call.
    public let firstRecordDate: Date?
    private let rowsByPeriod: [SpendPeriod: [SpendModelRow]]

    public init(records: [LLMCallRecord], now: Date, calendar: Calendar) {
        let paid = records.filter { $0.provider == .anthropic }
        // [start, end) of the local day and month that hold `now`.
        func within(_ component: Calendar.Component) -> [LLMCallRecord] {
            guard let interval = calendar.dateInterval(of: component, for: now) else { return [] }
            return paid.filter { $0.createdAt >= interval.start && $0.createdAt < interval.end }
        }
        let periods: [SpendPeriod: [LLMCallRecord]] = [
            .today: within(.day),
            .thisMonth: within(.month),
            .allTime: paid,
        ]
        today = SpendTotals(periods[.today] ?? [])
        thisMonth = SpendTotals(periods[.thisMonth] ?? [])
        allTime = SpendTotals(paid)
        firstRecordDate = paid.map(\.createdAt).min()
        rowsByPeriod = periods.mapValues(Self.rows)
    }

    public func totals(_ period: SpendPeriod) -> SpendTotals {
        switch period {
        case .today: today
        case .thisMonth: thisMonth
        case .allTime: allTime
        }
    }

    /// Most expensive first; ties by name.
    public func rows(_ period: SpendPeriod) -> [SpendModelRow] {
        rowsByPeriod[period] ?? []
    }

    private static func rows(_ records: [LLMCallRecord]) -> [SpendModelRow] {
        Dictionary(grouping: records, by: \.modelId)
            .map { id, records in
                SpendModelRow(
                    modelId: id,
                    name: ModelChoice.displayName(ledgerModelId: id),
                    calls: records.count,
                    micros: records.reduce(0) { $0 + ($1.costMicros ?? 0) }
                )
            }
            .sorted { $0.micros != $1.micros ? $0.micros > $1.micros : $0.name < $1.name }
    }
}

// MARK: - Guard

public struct SpendCaps: Sendable, Equatable, Codable {
    public let perRunMicros: Int64
    public let monthlyMicros: Int64

    public init(perRunMicros: Int64, monthlyMicros: Int64) {
        self.perRunMicros = perRunMicros
        self.monthlyMicros = monthlyMicros
    }

    /// $0.25 a run, $5.00 a month.
    public static let defaults = SpendCaps(
        perRunMicros: LLMSpendRules.defaultPerRunCapMicros,
        monthlyMicros: LLMSpendRules.defaultMonthlyCapMicros
    )
}

public enum SpendDecision: Sendable, Equatable {
    case allow
    /// The sentence to show.
    case deny(String)
}

/// Blocks a Claude run BEFORE it is sent when its worst case could pass a cap.
public enum SpendGuard {
    /// ceil(characters / 3).
    public static func estimatedInputTokens(promptCharacters: Int) -> Int {
        let perToken = LLMSpendRules.charactersPerToken
        return (max(0, promptCharacters) + perToken - 1) / perToken
    }

    /// Every input token at the input rate plus the whole output ceiling at the output rate.
    public static func worstCaseMicros(estimatedInputTokens: Int, maxOutputTokens: Int, rates: PriceTable.Rates) -> Int64 {
        CostCalculator.micros(estimatedInputTokens, rates.input) + CostCalculator.micros(maxOutputTokens, rates.output)
    }

    /// Denied when the worst case is over the per-run cap, or when this month's
    /// spend plus the worst case is over the monthly cap. Exactly equal is allowed.
    public static func decide(worstCaseMicros: Int64, monthSpentMicros: Int64, caps: SpendCaps) -> SpendDecision {
        let worst = CostFormatter.limitText(micros: worstCaseMicros)
        if worstCaseMicros > caps.perRunMicros {
            return .deny(
                "Blocked by your spend limit: this run could cost up to \(worst), "
                    + "your per-run limit is \(CostFormatter.limitText(micros: caps.perRunMicros))."
            )
        }
        if monthSpentMicros + worstCaseMicros > caps.monthlyMicros {
            return .deny(
                "Blocked by your spend limit: this run could cost up to \(worst), "
                    + "and \(CostFormatter.limitText(micros: monthSpentMicros)) is already spent this month "
                    + "of your \(CostFormatter.limitText(micros: caps.monthlyMicros)) monthly limit."
            )
        }
        return .allow
    }
}

// MARK: - Projection

/// "What would this cost?": how many plans and notes a month.
public struct CostScenario: Sendable, Equatable, Codable {
    public let plansPerMonth: Int
    public let notesPerMonth: Int

    public init(plansPerMonth: Int, notesPerMonth: Int) {
        self.plansPerMonth = max(0, plansPerMonth)
        self.notesPerMonth = max(0, notesPerMonth)
    }

    /// 2 plans and 30 notes.
    public static let defaults = CostScenario(plansPerMonth: 2, notesPerMonth: 30)
}

public struct CostProjectionRow: Sendable, Equatable, Identifiable {
    public let model: AnthropicModel
    /// One plan draft at the average tokens of your own runs.
    public let planDraftMicros: Int64?
    public let coachNoteMicros: Int64?
    /// Nil while a needed part has no data.
    public let monthlyMicros: Int64?

    public var id: String { model.rawValue }
}

/// Prices the average tokens of your own successful Claude runs at the current
/// rates. Assumes no caching: every input token is priced as uncached input.
public enum CostProjection {
    public static let noDataText = "Run it once to see a number"

    /// One row per Claude model, in the Lab's order.
    public static func rows(records: [LLMCallRecord], table: PriceTable, scenario: CostScenario) -> [CostProjectionRow] {
        let successful = records.filter { $0.provider == .anthropic && $0.success }
        return AnthropicModel.allCases.map { model in
            let mine = successful.filter { $0.modelId == model.apiId }
            let plan = averageCost(mine.filter { $0.purpose.task == .planDraft }, model: model, table: table)
            let note = averageCost(mine.filter { $0.purpose.task == .coachNote }, model: model, table: table)
            return CostProjectionRow(
                model: model,
                planDraftMicros: plan,
                coachNoteMicros: note,
                monthlyMicros: monthly(plan: plan, note: note, scenario: scenario)
            )
        }
    }

    /// plans x plan draft + notes x coach note; nil while a needed part has no data.
    public static func monthly(plan: Int64?, note: Int64?, scenario: CostScenario) -> Int64? {
        let planPart = scenario.plansPerMonth == 0 ? 0 : plan.map { $0 * Int64(scenario.plansPerMonth) }
        let notePart = scenario.notesPerMonth == 0 ? 0 : note.map { $0 * Int64(scenario.notesPerMonth) }
        guard let planPart, let notePart else { return nil }
        return planPart + notePart
    }

    /// The average prompt and output, priced at the current rates; nil without records.
    static func averageCost(_ records: [LLMCallRecord], model: AnthropicModel, table: PriceTable) -> Int64? {
        guard !records.isEmpty else { return nil }
        let count = Decimal(records.count)
        let input = Decimal(records.reduce(0) { $0 + $1.usage.promptTokens }) / count
        let output = Decimal(records.reduce(0) { $0 + $1.usage.output }) / count
        guard let rates = table.rates(modelApiId: model.apiId, promptTokens: Int(CostCalculator.roundedHalfUp(input))) else { return nil }
        return CostCalculator.roundedHalfUp(input * rates.input) + CostCalculator.roundedHalfUp(output * rates.output)
    }
}
