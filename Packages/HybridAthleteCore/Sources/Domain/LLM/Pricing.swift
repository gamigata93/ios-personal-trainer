import Foundation

/// Prices for Claude models, decoded from the bundled Prices.json (data, not code).
/// Money is `Decimal` parsed from strings, never `Double`. Every cost in this app
/// is an ESTIMATE from these prices; Anthropic's Console is the source of truth.
public struct PriceTable: Sendable, Equatable, Decodable {
    /// USD per million tokens for one model and prompt-length tier.
    public struct Rates: Sendable, Equatable, Decodable {
        public let input: Decimal
        public let output: Decimal
        public let cacheWrite5m: Decimal
        public let cacheWrite1h: Decimal
        public let cacheRead: Decimal

        public init(input: Decimal, output: Decimal, cacheWrite5m: Decimal, cacheWrite1h: Decimal, cacheRead: Decimal) {
            self.input = input
            self.output = output
            self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h
            self.cacheRead = cacheRead
        }

        private enum CodingKeys: String, CodingKey {
            case input, output, cacheWrite5m, cacheWrite1h, cacheRead
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = try Self.money(container, .input)
            output = try Self.money(container, .output)
            cacheWrite5m = try Self.money(container, .cacheWrite5m)
            cacheWrite1h = try Self.money(container, .cacheWrite1h)
            cacheRead = try Self.money(container, .cacheRead)
        }

        /// A non-negative decimal string such as "0.125", parsed exactly.
        private static func money(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Decimal {
            let text = try container.decode(String.self, forKey: key)
            guard
                text.wholeMatch(of: /\d+(\.\d+)?/) != nil,
                let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
            else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not a decimal string: \(text)")
            }
            return value
        }
    }

    /// Prompts with more than `aboveTokens` tokens use these rates for every line.
    public struct LongPromptTier: Sendable, Equatable, Decodable {
        public let aboveTokens: Int
        public let rates: Rates

        public init(aboveTokens: Int, rates: Rates) {
            self.aboveTokens = aboveTokens
            self.rates = rates
        }
    }

    public struct ModelPrices: Sendable, Equatable, Decodable {
        public let id: String
        public let rates: Rates
        public let longPrompt: LongPromptTier?

        public init(id: String, rates: Rates, longPrompt: LongPromptTier? = nil) {
            self.id = id
            self.rates = rates
            self.longPrompt = longPrompt
        }
    }

    public static let supportedSchemaVersion = 1
    /// Past this age the Lab asks for the prices to be checked again.
    public static let staleAfterDays = 60

    public let schemaVersion: Int
    public let lastVerified: LocalDate
    public let source: String
    public let models: [ModelPrices]

    public init(schemaVersion: Int = PriceTable.supportedSchemaVersion, lastVerified: LocalDate, source: String, models: [ModelPrices]) {
        self.schemaVersion = schemaVersion
        self.lastVerified = lastVerified
        self.source = source
        self.models = models
    }

    /// "v1 2026-10-14": stored with every ledger record.
    public var version: String { "v\(schemaVersion) \(lastVerified)" }

    /// The rates for a request whose prompt (uncached input + cache reads + cache
    /// writes) has `promptTokens` tokens. The long tier starts ABOVE its threshold:
    /// exactly 100,000 is still the lower tier. Each request is priced on its own.
    public func rates(modelApiId: String, promptTokens: Int) -> Rates? {
        guard let model = models.first(where: { $0.id == modelApiId }) else { return nil }
        if let long = model.longPrompt, promptTokens > long.aboveTokens { return long.rates }
        return model.rates
    }

    /// "$2 in · $10 out per 1M tokens", "$0.10 in · $0.50 out per 1M tokens" (the
    /// standard tier); nil for a model the table lacks.
    public func priceLine(modelApiId: String) -> String? {
        guard let rates = models.first(where: { $0.id == modelApiId })?.rates else { return nil }
        return "\(CostFormatter.rateText(rates.input)) in · \(CostFormatter.rateText(rates.output)) out per 1M tokens"
    }

    /// True when `lastVerified` is more than 60 days before `today`.
    public func isStale(today: LocalDate) -> Bool {
        lastVerified.days(to: today) > Self.staleAfterDays
    }

    /// Decodes and checks Prices.json; throws on a malformed file or an unknown schema.
    public static func decode(_ data: Data) throws -> PriceTable {
        let table = try JSONDecoder().decode(PriceTable.self, from: data)
        guard table.schemaVersion == supportedSchemaVersion, !table.models.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported price table"))
        }
        return table
    }
}

/// Billed token counts of one call. Output includes any thinking tokens, so
/// `reasoning` is informational and never billed again.
public struct TokenUsage: Sendable, Equatable, Codable {
    public let uncachedInput: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let output: Int
    public let reasoning: Int?

    public init(uncachedInput: Int, cacheRead: Int = 0, cacheWrite: Int = 0, output: Int, reasoning: Int? = nil) {
        self.uncachedInput = uncachedInput
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
        self.reasoning = reasoning
    }

    public static let zero = TokenUsage(uncachedInput: 0, output: 0)

    /// What picks the price tier: every input token, cached or not.
    public var promptTokens: Int { uncachedInput + cacheRead + cacheWrite }
}

/// Framework usage (input total, cached input, output total, reasoning) to billing fields.
public enum UsageNormalizer {
    public enum InputConvention: Sendable {
        /// The input total counts cached tokens too.
        case totalIncludesCached
        /// The input total is the uncached part only.
        case totalExcludesCached
    }

    /// ClaudeForFoundationModels 0.2.3 (`EventTranslator.TurnUsage`) reports
    /// `input.totalTokenCount = input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
    /// and `input.cachedTokenCount = cache_read_input_tokens`. So the total INCLUDES
    /// the cached tokens. Cache writes are folded into the total and cannot be told
    /// apart: they stay in `uncachedInput` (billed at the input rate) and
    /// `cacheWrite` is 0. Output includes thinking; reasoning is reported as 0.
    public static let frameworkConvention = InputConvention.totalIncludesCached

    public static func billing(
        inputTotal: Int,
        cachedInput: Int,
        output: Int,
        reasoning: Int?,
        convention: InputConvention = frameworkConvention
    ) -> TokenUsage {
        let cached = max(0, cachedInput)
        let uncached = switch convention {
        case .totalIncludesCached: max(0, inputTotal - cached)
        case .totalExcludesCached: max(0, inputTotal)
        }
        return TokenUsage(uncachedInput: uncached, cacheRead: cached, cacheWrite: 0, output: max(0, output), reasoning: reasoning)
    }
}

/// One call's cost per line, in micro-dollars (1 = $0.000001). Tokens x $/MTok
/// is micro-dollars directly. Each line is rounded half up on its own.
public struct CostBreakdown: Sendable, Equatable {
    public let input: Int64
    public let cacheRead: Int64
    public let cacheWrite: Int64
    public let output: Int64

    public init(input: Int64, cacheRead: Int64, cacheWrite: Int64, output: Int64) {
        self.input = input
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
    }

    public var total: Int64 { input + cacheRead + cacheWrite + output }
}

public enum CostCalculator {
    /// Cache writes are priced at the 5-minute rate: the package asks for the
    /// API's default cache window, which is 5 minutes.
    public static func cost(_ usage: TokenUsage, rates: PriceTable.Rates) -> CostBreakdown {
        CostBreakdown(
            input: micros(usage.uncachedInput, rates.input),
            cacheRead: micros(usage.cacheRead, rates.cacheRead),
            cacheWrite: micros(usage.cacheWrite, rates.cacheWrite5m),
            output: micros(usage.output, rates.output)
        )
    }

    /// The cost at the tier the whole prompt falls in; nil for a model the table lacks.
    public static func cost(_ usage: TokenUsage, modelApiId: String, table: PriceTable) -> CostBreakdown? {
        table.rates(modelApiId: modelApiId, promptTokens: usage.promptTokens).map { cost(usage, rates: $0) }
    }

    /// `tokens` x `rate` ($/MTok), rounded half up to whole micro-dollars.
    public static func micros(_ tokens: Int, _ rate: Decimal) -> Int64 {
        roundedHalfUp(Decimal(tokens) * rate)
    }

    static func roundedHalfUp(_ value: Decimal) -> Int64 {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return NSDecimalNumber(decimal: result).int64Value
    }
}

/// Dollar texts for micro-dollar amounts.
public enum CostFormatter {
    /// >= $1: "$1.23"; >= $0.01: "$0.028"; >= $0.0001: "$0.0001"; 1 to 99 micros: "<$0.0001"; 0: "$0.00".
    public static func text(micros: Int64) -> String {
        switch micros {
        case ..<1: "$0.00"
        case ..<100: "<$0.0001"
        case ..<10_000: dollars(micros, decimals: 4)
        case ..<1_000_000: dollars(micros, decimals: 3)
        default: dollars(micros, decimals: 2)
        }
    }

    /// "≈ $28 per 1,000 runs": whole dollars from $10, otherwise as `text`.
    public static func perThousandRunsText(micros: Int64) -> String {
        let total = micros * 1_000
        let amount = total >= 10_000_000 ? "$" + grouped((total + 500_000) / 1_000_000) : text(micros: total)
        return "≈ \(amount) per 1,000 runs"
    }

    /// Limits and worst cases: whole cents as "$0.25" and "$5.00", anything finer as `text`.
    public static func limitText(micros: Int64) -> String {
        micros % 10_000 == 0 ? dollars(micros, decimals: 2) : text(micros: micros)
    }

    /// A $/MTok rate: "$2", "$0.10", "$12.50", "$0.125".
    public static func rateText(_ rate: Decimal) -> String {
        let text = "\(rate)"
        guard let dot = text.firstIndex(of: ".") else { return "$" + text }
        let decimals = text.distance(from: dot, to: text.endIndex) - 1
        return "$" + text + String(repeating: "0", count: max(0, 2 - decimals))
    }

    /// For VoiceOver: "3 cents", "5 dollars", "1 dollar 23 cents", "less than 1 cent".
    public static func spokenText(micros: Int64) -> String {
        guard micros > 0 else { return "0 dollars" }
        let cents = (micros + 5_000) / 10_000
        guard cents > 0 else { return "less than 1 cent" }
        let dollars = cents / 100
        let rest = cents % 100
        let centText = "\(rest) \(rest == 1 ? "cent" : "cents")"
        guard dollars > 0 else { return "\(cents) \(cents == 1 ? "cent" : "cents")" }
        let dollarText = "\(dollars) \(dollars == 1 ? "dollar" : "dollars")"
        return rest == 0 ? dollarText : "\(dollarText) \(centText)"
    }

    /// For VoiceOver: "a 5 dollar limit", or "a limit of 1 dollar 23 cents".
    public static func spokenLimit(micros: Int64) -> String {
        micros > 0 && micros % 1_000_000 == 0 ? "a \(micros / 1_000_000) dollar limit" : "a limit of \(spokenText(micros: micros))"
    }

    /// Rounded half up to `decimals` places, always showing them all.
    private static func dollars(_ micros: Int64, decimals: Int) -> String {
        let divisor = Int64(pow(10, Double(6 - decimals)))
        let units = (micros + divisor / 2) / divisor
        let scale = Int64(pow(10, Double(decimals)))
        let fraction = String(units % scale)
        return "$" + grouped(units / scale) + "." + String(repeating: "0", count: decimals - fraction.count) + fraction
    }

    /// "1,234".
    private static func grouped(_ value: Int64) -> String {
        let digits = Array(String(value))
        var text = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { text.append(",") }
            text.append(digit)
        }
        return text
    }
}
