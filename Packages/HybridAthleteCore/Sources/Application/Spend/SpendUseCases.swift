import Foundation
import Domain

/// What the Lab's cost card shows for one period.
public struct SpendOverview: Sendable, Equatable {
    public let period: SpendPeriod
    public let totals: SpendTotals
    /// Most expensive first.
    public let rows: [SpendModelRow]
    public let firstRecordDate: Date?
    /// Always this month's spend, for the cap card.
    public let monthSpentMicros: Int64
    /// Nil when Prices.json is missing or malformed.
    public let pricesLastVerified: LocalDate?
    public let pricesAreStale: Bool
    /// The ledger could not be read.
    public let loadFailed: Bool

    public static func empty(_ period: SpendPeriod) -> SpendOverview {
        SpendOverview(
            period: period, totals: .zero, rows: [], firstRecordDate: nil, monthSpentMicros: 0,
            pricesLastVerified: nil, pricesAreStale: false, loadFailed: false
        )
    }
}

/// The cost card: totals and per-model rows for one period, from the ledger.
public struct GetSpendOverview: Sendable {
    private let ledger: any LLMUsageLedger
    private let prices: any PriceTableProvider
    private let clock: any Clock
    private let calendar: Calendar

    public init(ledger: any LLMUsageLedger, prices: any PriceTableProvider, clock: any Clock, calendar: Calendar) {
        self.ledger = ledger
        self.prices = prices
        self.clock = clock
        self.calendar = calendar
    }

    public func execute(_ period: SpendPeriod) async -> SpendOverview {
        let now = clock.now()
        let table = prices.priceTable()
        let records = try? await ledger.records(since: nil)
        let summary = SpendSummary(records: records ?? [], now: now, calendar: calendar)
        return SpendOverview(
            period: period,
            totals: summary.totals(period),
            rows: summary.rows(period),
            firstRecordDate: summary.firstRecordDate,
            monthSpentMicros: summary.thisMonth.micros,
            pricesLastVerified: table?.lastVerified,
            pricesAreStale: table?.isStale(today: LocalDate(date: now, calendar: calendar)) ?? false,
            loadFailed: records == nil
        )
    }
}

/// "What would this cost?": your own average runs at today's prices. Nil when
/// there is no price table.
public struct ProjectCosts: Sendable {
    private let ledger: any LLMUsageLedger
    private let prices: any PriceTableProvider

    public init(ledger: any LLMUsageLedger, prices: any PriceTableProvider) {
        self.ledger = ledger
        self.prices = prices
    }

    public func execute(_ scenario: CostScenario) async -> [CostProjectionRow]? {
        guard let table = prices.priceTable() else { return nil }
        let records = (try? await ledger.records(since: nil)) ?? []
        return CostProjection.rows(records: records, table: table, scenario: scenario)
    }
}

/// Clears the usage history ("Clear history").
public struct ClearUsageHistory: Sendable {
    private let ledger: any LLMUsageLedger

    public init(ledger: any LLMUsageLedger) {
        self.ledger = ledger
    }

    public func execute() async throws {
        try await ledger.clear()
    }
}

/// Reads and changes the Lab's consent, caps and cost scenario.
public struct LabSpendSettings: Sendable {
    private let store: any LabSettingsStore

    public init(store: any LabSettingsStore) {
        self.store = store
    }

    public func load() async -> LabSettings {
        await store.load()
    }

    public func grantConsent() async {
        var settings = await store.load()
        settings.consentGiven = true
        await store.save(settings)
    }

    public func setCaps(_ caps: SpendCaps) async {
        var settings = await store.load()
        settings.caps = caps
        await store.save(settings)
    }

    /// "Use for coach notes" and "Automatic" in the Lab.
    public func setCoachModelPreference(_ preference: CoachModelPreference) async {
        var settings = await store.load()
        settings.coachModelPreference = preference
        await store.save(settings)
    }

    public func setScenario(_ scenario: CostScenario) async {
        var settings = await store.load()
        settings.scenario = scenario
        await store.save(settings)
    }
}

/// What the Lab may show about the saved key: whether there is one, and its last 4 characters.
public enum APIKeyStatus: Sendable, Equatable {
    case none
    case saved(lastFour: String)

    /// "No key saved" or "Saved · ends …a1b2".
    public var text: String {
        switch self {
        case .none: "No key saved"
        case .saved(let lastFour): "Saved · ends \u{2026}\(lastFour)"
        }
    }
}

/// Saves, removes and describes the Anthropic key. The full key goes only to the
/// secret store; callers get the last 4 characters back.
public struct ManageAnthropicKey: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case empty
        case storeFailed
    }

    private let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func status() async -> APIKeyStatus {
        guard let key = try? await secrets.secret(for: .anthropicAPIKey), !key.isEmpty else { return .none }
        return .saved(lastFour: String(key.suffix(4)))
    }

    /// Trims spaces and line breaks (a pasted key often has one).
    @discardableResult
    public func save(_ key: String) async throws(Failure) -> APIKeyStatus {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        do {
            try await secrets.setSecret(trimmed, for: .anthropicAPIKey)
        } catch {
            throw .storeFailed
        }
        return .saved(lastFour: String(trimmed.suffix(4)))
    }

    public func remove() async throws(Failure) {
        do {
            try await secrets.removeSecret(for: .anthropicAPIKey)
        } catch {
            throw .storeFailed
        }
    }
}

/// "Test": a tiny request on Haiku 5.5 through the spend gate.
public struct TestAnthropicKey: Sendable {
    private let gate: SpendGate
    private let tester: any AnthropicKeyTesting

    public init(gate: SpendGate, tester: any AnthropicKeyTesting) {
        self.gate = gate
        self.tester = tester
    }

    public func execute() async throws(LLMError) -> KeyTestResult {
        try await gate.check(
            model: .anthropic(LLMSpendRules.keyTestModel),
            purpose: .keyTest,
            promptCharacters: LLMSpendRules.keyTestPrompt.count
        )
        do {
            return try await tester.testKey()
        } catch let error as LLMError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .other(String(describing: type(of: error)))
        }
    }
}

/// Dollars typed into a cap field ("0.25", "5", "1,50") to micro-dollars; nil
/// for anything that is not a positive amount.
public enum DollarInput {
    public static func micros(_ text: String) -> Int64? {
        let normalized = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard
            normalized.wholeMatch(of: /\d+(\.\d{1,6})?/) != nil,
            let dollars = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        let micros = CostCalculator.micros(1_000_000, dollars)
        return micros > 0 ? micros : nil
    }

    /// "0.25", "5.00": what the cap fields show.
    public static func text(micros: Int64) -> String {
        String(CostFormatter.limitText(micros: micros).dropFirst())
    }
}

/// "$2 in · $10 out per 1M tokens" under a Claude pill; nil without a price table.
public struct GetClaudePriceLine: Sendable {
    private let prices: any PriceTableProvider

    public init(prices: any PriceTableProvider) {
        self.prices = prices
    }

    public func execute(_ model: AnthropicModel) -> String? {
        prices.priceTable()?.priceLine(modelApiId: model.apiId)
    }
}
