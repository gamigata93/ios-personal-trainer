import Foundation
import Testing
import Domain

/// The price table as in the bundled Prices.json, decoded from the same JSON shape.
enum TestPrices {
    static let json = """
        {
          "schemaVersion": 1, "lastVerified": "2026-10-14", "source": "https://platform.claude.com/docs/en/about-claude/pricing",
          "models": [
            { "id": "claude-haiku-5-5",
              "rates": { "input": "0.10", "output": "0.50", "cacheWrite5m": "0.125", "cacheWrite1h": "0.20", "cacheRead": "0.01" },
              "longPrompt": { "aboveTokens": 100000,
                "rates": { "input": "0.50", "output": "2.50", "cacheWrite5m": "0.625", "cacheWrite1h": "1.00", "cacheRead": "0.05" } } },
            { "id": "claude-sonnet-5-5", "rates": { "input": "2", "output": "10", "cacheWrite5m": "2.50", "cacheWrite1h": "4", "cacheRead": "0.10" } },
            { "id": "claude-opus-5-5", "rates": { "input": "4", "output": "20", "cacheWrite5m": "5", "cacheWrite1h": "8", "cacheRead": "0.20" } },
            { "id": "claude-fable-5-1", "rates": { "input": "10", "output": "50", "cacheWrite5m": "12.50", "cacheWrite1h": "20", "cacheRead": "0.25" } }
          ]
        }
        """

    static var table: PriceTable {
        get throws { try PriceTable.decode(Data(json.utf8)) }
    }

    static func cost(_ usage: TokenUsage, _ model: AnthropicModel) throws -> CostBreakdown {
        try #require(CostCalculator.cost(usage, modelApiId: model.apiId, table: try table))
    }
}

@Suite("Price table")
struct PriceTableTests {
    @Test func decimalStringsStayExact() throws {
        let table = try TestPrices.table
        let haiku = try #require(table.rates(modelApiId: "claude-haiku-5-5", promptTokens: 1_000))
        #expect(haiku.cacheWrite5m == Decimal(string: "0.125"))
        #expect(haiku.cacheWrite5m * 8 == 1)
        #expect(haiku.input == Decimal(1) / 10)
        #expect(table.lastVerified == LocalDate(year: 2026, month: 10, day: 14))
        #expect(table.version == "v1 2026-10-14")
    }

    @Test func longTierStartsAboveTheThreshold() throws {
        let table = try TestPrices.table
        #expect(table.rates(modelApiId: "claude-haiku-5-5", promptTokens: 100_000)?.input == Decimal(string: "0.10"))
        #expect(table.rates(modelApiId: "claude-haiku-5-5", promptTokens: 100_001)?.input == Decimal(string: "0.50"))
        #expect(table.rates(modelApiId: "claude-sonnet-5-5", promptTokens: 500_000)?.input == 2)
        #expect(table.rates(modelApiId: "claude-unknown", promptTokens: 1) == nil)
    }

    @Test func malformedTablesAreRejected() {
        #expect(throws: (any Error).self) { try PriceTable.decode(Data(TestPrices.json.replacingOccurrences(of: "\"0.125\"", with: "0.125").utf8)) }
        #expect(throws: (any Error).self) { try PriceTable.decode(Data(TestPrices.json.replacingOccurrences(of: "\"0.125\"", with: "\"-0.125\"").utf8)) }
        #expect(throws: (any Error).self) { try PriceTable.decode(Data(TestPrices.json.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2").utf8)) }
        #expect(throws: (any Error).self) { try PriceTable.decode(Data("{}".utf8)) }
    }

    @Test func priceLines() throws {
        let table = try TestPrices.table
        #expect(table.priceLine(modelApiId: "claude-sonnet-5-5") == "$2 in · $10 out per 1M tokens")
        #expect(table.priceLine(modelApiId: "claude-haiku-5-5") == "$0.10 in · $0.50 out per 1M tokens")
        #expect(table.priceLine(modelApiId: "claude-fable-5-1") == "$10 in · $50 out per 1M tokens")
        #expect(CostFormatter.rateText(Decimal(string: "0.125") ?? 0) == "$0.125")
        #expect(CostFormatter.rateText(Decimal(string: "12.50") ?? 0) == "$12.50")
        #expect(table.priceLine(modelApiId: "nope") == nil)
    }

    @Test func staleAfterSixtyDays() throws {
        let table = try TestPrices.table
        #expect(!table.isStale(today: LocalDate(year: 2026, month: 12, day: 13)))
        #expect(table.isStale(today: LocalDate(year: 2026, month: 12, day: 14)))
    }
}

@Suite("Cost calculator")
struct CostCalculatorTests {
    @Test func sonnetPlanDraft() throws {
        let cost = try TestPrices.cost(TokenUsage(uncachedInput: 1_850, output: 2_400), .sonnet55)
        #expect(cost.input == 3_700)
        #expect(cost.output == 24_000)
        #expect(cost.total == 27_700)
        #expect(CostFormatter.text(micros: cost.total) == "$0.028")
    }

    @Test func haikuCoachNote() throws {
        let cost = try TestPrices.cost(TokenUsage(uncachedInput: 600, output: 150), .haiku55)
        #expect(cost.input == 60)
        #expect(cost.output == 75)
        #expect(cost.total == 135)
        #expect(CostFormatter.text(micros: cost.total) == "$0.0001")
    }

    @Test func haikuLongPromptTier() throws {
        let long = try TestPrices.cost(TokenUsage(uncachedInput: 120_000, output: 1_000), .haiku55)
        #expect(long.input == 60_000)
        #expect(long.output == 2_500)
        #expect(long.total == 62_500)
        #expect(try TestPrices.cost(TokenUsage(uncachedInput: 100_000, output: 0), .haiku55).total == 10_000)
        // 99,000 uncached + 2,000 cache reads = 101,000: every line uses the long tier.
        let mixed = try TestPrices.cost(TokenUsage(uncachedInput: 99_000, cacheRead: 2_000, output: 0), .haiku55)
        #expect(mixed.input == 49_500)
        #expect(mixed.cacheRead == 100)
    }

    @Test func opusWithCaching() throws {
        let cost = try TestPrices.cost(TokenUsage(uncachedInput: 1_000, cacheRead: 8_000, cacheWrite: 2_000, output: 500), .opus55)
        #expect(cost == CostBreakdown(input: 4_000, cacheRead: 1_600, cacheWrite: 10_000, output: 10_000))
        #expect(cost.total == 25_600)
    }

    @Test func reasoningIsInsideOutputAndNotBilledAgain() throws {
        let cost = try TestPrices.cost(TokenUsage(uncachedInput: 1_000, output: 1_000, reasoning: 700), .fable51)
        #expect(cost.input == 10_000)
        #expect(cost.output == 50_000)
        #expect(cost.total == 60_000)
    }

    @Test func eachLineIsRoundedHalfUpOnItsOwn() throws {
        // Haiku: 5 x 0.10 = 0.5 -> 1, 1 x 0.50 = 0.5 -> 1. Unrounded the sum is 1.0.
        let cost = try TestPrices.cost(TokenUsage(uncachedInput: 5, output: 1), .haiku55)
        #expect(cost.total == 2)
        // 3 x 0.125 = 0.375 -> 0; 4 x 0.125 = 0.5 -> 1.
        #expect(try TestPrices.cost(TokenUsage(uncachedInput: 0, cacheWrite: 3, output: 0), .haiku55).cacheWrite == 0)
        #expect(try TestPrices.cost(TokenUsage(uncachedInput: 0, cacheWrite: 4, output: 0), .haiku55).cacheWrite == 1)
    }
}

@Suite("Cost formatter")
struct CostFormatterTests {
    @Test func tiers() {
        #expect(CostFormatter.text(micros: 1_234_567) == "$1.23")
        #expect(CostFormatter.text(micros: 27_700) == "$0.028")
        #expect(CostFormatter.text(micros: 135) == "$0.0001")
        #expect(CostFormatter.text(micros: 99) == "<$0.0001")
        #expect(CostFormatter.text(micros: 1) == "<$0.0001")
        #expect(CostFormatter.text(micros: 0) == "$0.00")
        #expect(CostFormatter.text(micros: 1_234_567_890) == "$1,234.57")
    }

    @Test func perThousandRuns() {
        #expect(CostFormatter.perThousandRunsText(micros: 27_700) == "≈ $28 per 1,000 runs")
        #expect(CostFormatter.perThousandRunsText(micros: 135) == "≈ $0.135 per 1,000 runs")
    }

    @Test func limitsAndSpokenText() {
        #expect(CostFormatter.limitText(micros: 250_000) == "$0.25")
        #expect(CostFormatter.limitText(micros: 5_000_000) == "$5.00")
        #expect(CostFormatter.limitText(micros: 320_000) == "$0.32")
        #expect(CostFormatter.limitText(micros: 213_000) == "$0.213")
        #expect(CostFormatter.spokenText(micros: 28_000) == "3 cents")
        #expect(CostFormatter.spokenText(micros: 5_000_000) == "5 dollars")
        #expect(CostFormatter.spokenText(micros: 1_230_000) == "1 dollar 23 cents")
        #expect(CostFormatter.spokenText(micros: 135) == "less than 1 cent")
        #expect(CostFormatter.spokenLimit(micros: 5_000_000) == "a 5 dollar limit")
        #expect(CostFormatter.spokenLimit(micros: 250_000) == "a limit of 25 cents")
    }
}

@Suite("Usage normalizer")
struct UsageNormalizerTests {
    @Test func theFrameworkTotalIncludesCachedTokens() {
        // ClaudeForFoundationModels: total = input_tokens + cache reads + cache writes; cached = cache reads.
        #expect(UsageNormalizer.frameworkConvention == .totalIncludesCached)
        let usage = UsageNormalizer.billing(inputTotal: 9_000, cachedInput: 8_000, output: 500, reasoning: nil)
        #expect(usage == TokenUsage(uncachedInput: 1_000, cacheRead: 8_000, cacheWrite: 0, output: 500))
        #expect(usage.promptTokens == 9_000)
    }

    @Test func theOtherConvention() {
        let usage = UsageNormalizer.billing(inputTotal: 1_000, cachedInput: 8_000, output: 500, reasoning: 40, convention: .totalExcludesCached)
        #expect(usage == TokenUsage(uncachedInput: 1_000, cacheRead: 8_000, output: 500, reasoning: 40))
        #expect(usage.promptTokens == 9_000)
    }

    @Test func neverNegative() {
        let usage = UsageNormalizer.billing(inputTotal: 10, cachedInput: 50, output: -1, reasoning: nil)
        #expect(usage == TokenUsage(uncachedInput: 0, cacheRead: 50, output: 0))
    }
}

private func record(
    _ model: AnthropicModel?,
    _ isoDate: String,
    micros: Int64?,
    usage: TokenUsage = TokenUsage(uncachedInput: 0, output: 0),
    purpose: LLMCallPurpose = .labPlanDraft,
    success: Bool = true
) -> LLMCallRecord {
    LLMCallRecord(
        createdAt: (try? Date.ISO8601FormatStyle().parse(isoDate)) ?? .distantPast,
        provider: model == nil ? .apple : .anthropic,
        modelId: model?.apiId ?? "onDevice",
        purpose: purpose,
        success: success,
        errorKind: success ? nil : "billingProblem",
        usage: usage,
        latencyMs: 1_000,
        costMicros: micros,
        priceTableVersion: "v1 2026-10-14"
    )
}

@Suite("Spend summary")
struct SpendSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3_600) ?? .gmt
        return calendar
    }

    private let records = [
        // Local 1 Nov 00:30 (UTC+3): November, not October.
        record(.sonnet55, "2026-10-31T21:30:00Z", micros: 27_700, usage: TokenUsage(uncachedInput: 1_850, output: 2_400)),
        // Local 31 Oct 23:30: October.
        record(.haiku55, "2026-10-31T20:30:00Z", micros: 135, usage: TokenUsage(uncachedInput: 600, output: 150)),
        record(.opus55, "2026-11-15T10:00:00Z", micros: 25_600, usage: TokenUsage(uncachedInput: 1_000, cacheRead: 8_000, cacheWrite: 2_000, output: 500)),
        // Apple's models are free and not counted.
        record(nil, "2026-11-15T09:00:00Z", micros: nil),
    ]

    @Test func periodsUseTheLocalCalendar() throws {
        let now = try Date.ISO8601FormatStyle().parse("2026-11-15T12:00:00Z")
        let summary = SpendSummary(records: records, now: now, calendar: calendar)
        #expect(summary.allTime.micros == 53_435)
        #expect(CostFormatter.text(micros: summary.allTime.micros) == "$0.053")
        #expect(summary.allTime.calls == 3)
        #expect(summary.allTime.tokensIn == 1_850 + 600 + 11_000)
        #expect(summary.allTime.tokensOut == 2_400 + 150 + 500)
        #expect(summary.thisMonth.micros == 27_700 + 25_600)
        #expect(summary.thisMonth.calls == 2)
        #expect(summary.today.micros == 25_600)
        #expect(summary.firstRecordDate == (try Date.ISO8601FormatStyle().parse("2026-10-31T20:30:00Z")))
    }

    @Test func rowsAreSortedByCost() throws {
        let now = try Date.ISO8601FormatStyle().parse("2026-11-15T12:00:00Z")
        let summary = SpendSummary(records: records, now: now, calendar: calendar)
        #expect(summary.rows(.allTime).map(\.name) == ["Sonnet 5.5", "Opus 5.5", "Haiku 5.5"])
        #expect(summary.rows(.allTime).map(\.micros) == [27_700, 25_600, 135])
        #expect(summary.rows(.today).map(\.modelId) == ["claude-opus-5-5"])
    }

    @Test func octoberOnlySeesTheHaikuRecord() throws {
        let now = try Date.ISO8601FormatStyle().parse("2026-10-31T20:45:00Z") // local 31 Oct 23:45
        let summary = SpendSummary(records: records, now: now, calendar: calendar)
        #expect(summary.thisMonth.micros == 135)
        #expect(summary.today.micros == 135)
    }
}

@Suite("Spend guard")
struct SpendGuardTests {
    @Test func fableWithinAndOverThePerRunCap() throws {
        let fable = try #require(try TestPrices.table.rates(modelApiId: "claude-fable-5-1", promptTokens: 2_000))
        let allowed = SpendGuard.worstCaseMicros(estimatedInputTokens: 2_000, maxOutputTokens: 4_000, rates: fable)
        #expect(allowed == 220_000)
        #expect(SpendGuard.decide(worstCaseMicros: allowed, monthSpentMicros: 0, caps: .defaults) == .allow)

        let denied = SpendGuard.worstCaseMicros(estimatedInputTokens: 2_000, maxOutputTokens: 6_000, rates: fable)
        #expect(denied == 320_000)
        #expect(SpendGuard.decide(worstCaseMicros: denied, monthSpentMicros: 0, caps: .defaults)
            == .deny("Blocked by your spend limit: this run could cost up to $0.32, your per-run limit is $0.25."))
    }

    @Test func monthlyCap() {
        let caps = SpendCaps(perRunMicros: 250_000, monthlyMicros: 5_000_000)
        guard case .deny = SpendGuard.decide(worstCaseMicros: 20_000, monthSpentMicros: 4_990_000, caps: caps) else {
            Issue.record("expected a denial")
            return
        }
        #expect(SpendGuard.decide(worstCaseMicros: 10_000, monthSpentMicros: 4_990_000, caps: caps) == .allow)
        #expect(SpendGuard.decide(worstCaseMicros: 250_000, monthSpentMicros: 0, caps: caps) == .allow)
    }

    @Test func characterEstimate() {
        #expect(SpendGuard.estimatedInputTokens(promptCharacters: 900) == 300)
        #expect(SpendGuard.estimatedInputTokens(promptCharacters: 901) == 301)
        #expect(SpendGuard.estimatedInputTokens(promptCharacters: 0) == 0)
    }

    @Test func ceilings() {
        #expect(LLMCallPurpose.labCoachNote.task.maxOutputTokens == 1_000)
        #expect(LLMCallPurpose.workoutNote.task.maxOutputTokens == 1_000)
        #expect(LLMCallPurpose.planGeneration.task.maxOutputTokens == 4_000)
        #expect(LLMCallPurpose.keyTest.task.maxOutputTokens == 8)
        #expect(SpendCaps.defaults == SpendCaps(perRunMicros: 250_000, monthlyMicros: 5_000_000))
    }
}

@Suite("Cost projection")
struct CostProjectionTests {
    @Test func sonnetFromYourOwnRuns() throws {
        let records = [
            record(.sonnet55, "2026-10-10T10:00:00Z", micros: 27_700, usage: TokenUsage(uncachedInput: 1_850, output: 2_400), purpose: .labPlanDraft),
            record(.sonnet55, "2026-10-10T11:00:00Z", micros: 3_000, usage: TokenUsage(uncachedInput: 700, output: 160), purpose: .labCoachNote),
            // Failures and the key test are not averaged in.
            record(.sonnet55, "2026-10-10T12:00:00Z", micros: 0, usage: TokenUsage(uncachedInput: 99_999, output: 0), purpose: .labPlanDraft, success: false),
            record(.sonnet55, "2026-10-10T13:00:00Z", micros: 2, usage: TokenUsage(uncachedInput: 12, output: 2), purpose: .keyTest),
        ]
        let rows = CostProjection.rows(records: records, table: try TestPrices.table, scenario: .defaults)
        let sonnet = try #require(rows.first { $0.model == .sonnet55 })
        #expect(sonnet.planDraftMicros == 27_700)
        #expect(sonnet.coachNoteMicros == 3_000)
        #expect(sonnet.monthlyMicros == 145_400)
        #expect(CostFormatter.text(micros: 145_400) == "$0.145")

        let haiku = try #require(rows.first { $0.model == .haiku55 })
        #expect(haiku.planDraftMicros == nil && haiku.coachNoteMicros == nil && haiku.monthlyMicros == nil)
        #expect(CostProjection.noDataText == "Run it once to see a number")
        #expect(rows.map(\.model) == AnthropicModel.allCases)
    }

    @Test func averagesAndAssumesNoCaching() throws {
        let records = [
            record(.sonnet55, "2026-10-10T10:00:00Z", micros: nil, usage: TokenUsage(uncachedInput: 1_800, output: 2_400), purpose: .planGeneration),
            record(.sonnet55, "2026-10-10T11:00:00Z", micros: nil, usage: TokenUsage(uncachedInput: 900, cacheRead: 1_000, output: 2_400), purpose: .labPlanDraft),
        ]
        let row = try #require(CostProjection.rows(records: records, table: try TestPrices.table, scenario: .defaults).first { $0.model == .sonnet55 })
        #expect(row.planDraftMicros == 27_700)
        #expect(row.monthlyMicros == nil)
        #expect(CostProjection.monthly(plan: 27_700, note: nil, scenario: CostScenario(plansPerMonth: 2, notesPerMonth: 0)) == 55_400)
    }
}

@Suite("Claude model choices")
struct ClaudeModelChoiceTests {
    @Test func idsAndTags() {
        #expect(ModelChoice.claude.map(\.id) == ["anthropic.haiku55", "anthropic.sonnet55", "anthropic.opus55", "anthropic.fable51"])
        #expect(ModelChoice.claude.map(\.generatedBy) == ["claude-haiku-5-5-v1", "claude-sonnet-5-5-v1", "claude-opus-5-5-v1", "claude-fable-5-1-v1"])
        #expect(ModelChoice.claude.map(\.displayName) == ["Haiku 5.5", "Sonnet 5.5", "Opus 5.5", "Fable 5.1"])
        #expect(ModelChoice(id: "anthropic.sonnet55") == .anthropic(.sonnet55))
        #expect(ModelChoice.anthropic(.opus55).provider == .anthropic)
        #expect(ModelChoice.onDevice.provider == .apple)
        #expect(ModelChoice.anthropic(.fable51).ledgerModelId == "claude-fable-5-1")
        #expect(ModelChoice.displayName(ledgerModelId: "claude-haiku-5-5") == "Haiku 5.5")
        #expect(ModelChoice.displayName(ledgerModelId: "pcc.deep") == "PCC deep")
        #expect(ModelAvailability.needsAPIKey.message == "Add your Anthropic API key to run Claude models.")
        #expect(LLMError.rateLimited(retryAfter: 3).kind == "rateLimited")
    }

    @Test func usageLines() {
        let usage = LLMUsage(TokenUsage(uncachedInput: 1_000, cacheRead: 800, output: 50), latencyMs: 900, costMicros: 2_330)
        #expect(usage.inputTokens == 1_800)
        #expect(usage.cacheLine == "cache read 800 · cache write 0")
        #expect(LLMUsage(TokenUsage(uncachedInput: 5, output: 5), latencyMs: 1, costMicros: nil).cacheLine == nil)
    }
}
