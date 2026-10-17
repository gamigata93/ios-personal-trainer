import Foundation
import Testing
import Application
import Domain

// MARK: - Fakes

private struct FixedClock: Clock {
    var date = Date(timeIntervalSince1970: 1_793_178_000) // Wed 28 Oct 2026, 09:00 UTC
    func now() -> Date { date }
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

private func rates(_ input: String, _ output: String) -> PriceTable.Rates {
    let d = { (text: String) in Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    return PriceTable.Rates(input: d(input), output: d(output), cacheWrite5m: d(input) * 5 / 4, cacheWrite1h: d(input) * 2, cacheRead: d(input) / 10)
}

private struct FakePrices: PriceTableProvider {
    var table: PriceTable? = PriceTable(
        lastVerified: LocalDate(year: 2026, month: 10, day: 14),
        source: "test",
        models: [
            .init(id: "claude-haiku-5-5", rates: rates("0.10", "0.50")),
            .init(id: "claude-sonnet-5-5", rates: rates("2", "10")),
            .init(id: "claude-fable-5-1", rates: rates("10", "50")),
        ]
    )
    func priceTable() -> PriceTable? { table }
}

private actor MemoryLedger: LLMUsageLedger {
    private(set) var stored: [LLMCallRecord] = []
    var failsReads = false

    init(_ records: [LLMCallRecord] = [], failsReads: Bool = false) {
        stored = records
        self.failsReads = failsReads
    }

    func record(_ record: LLMCallRecord) async { stored.append(record) }
    func records(since date: Date?) async throws -> [LLMCallRecord] {
        struct ReadFailed: Error {}
        if failsReads { throw ReadFailed() }
        return stored.filter { record in date.map { record.createdAt >= $0 } ?? true }
    }
    func clear() async throws { stored = [] }
    func firstRecordDate() async throws -> Date? { stored.map(\.createdAt).min() }
}

private actor MemorySettings: LabSettingsStore {
    var settings: LabSettings
    init(_ settings: LabSettings = LabSettings()) { self.settings = settings }
    func load() async -> LabSettings { settings }
    func save(_ settings: LabSettings) async { self.settings = settings }
}

private actor MemorySecrets: SecretStore {
    private(set) var values: [SecretKey: String] = [:]
    init(_ values: [SecretKey: String] = [:]) { self.values = values }
    func secret(for key: SecretKey) async throws -> String? { values[key] }
    func hasSecret(_ key: SecretKey) async -> Bool { values[key] != nil }
    func setSecret(_ value: String, for key: SecretKey) async throws { values[key] = value }
    func removeSecret(for key: SecretKey) async throws { values[key] = nil }
}

/// Behaves like an adapter: records every attempt it "sends" through the meter.
/// The first `invalidAttempts` drafts break a rule (a Tuesday session).
private actor MeteredDrafting: PlanDraftingModel {
    let meter: LLMCallMeter
    var invalidAttempts: Int
    var failure: LLMError?
    private(set) var calls = 0

    init(meter: LLMCallMeter, invalidAttempts: Int = 0, failure: LLMError? = nil) {
        self.meter = meter
        self.invalidAttempts = invalidAttempts
        self.failure = failure
    }

    func draftPlan(_ request: PlanRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> PlanDraftResult {
        calls += 1
        let usage = TokenUsage(uncachedInput: 1_850, output: failure == nil ? 2_400 : 300)
        if let failure {
            // A failed request still reports what it used.
            await meter.record(model: model, purpose: purpose, usage: usage, latencyMs: 500, error: failure)
            throw failure
        }
        let record = await meter.record(model: model, purpose: purpose, usage: usage, latencyMs: 1_000, error: nil)
        var draft = SpendFixture.draft
        if calls <= invalidAttempts {
            var weeks = draft.weeks
            weeks[0] = DraftWeek(index: 1, phase: .base, sessions: [DraftSession(weekday: .tuesday, type: .easy, distanceKm: 5)])
            draft = PlanDraft(weeks: weeks)
        }
        return PlanDraftResult(draft: draft, usage: LLMUsage(usage, latencyMs: 1_000, costMicros: record.costMicros), promptText: "prompt")
    }
}

private actor CountingCoaching: CoachingModel {
    private(set) var calls = 0
    func writeWorkoutNote(_ prompt: Prompt, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        calls += 1
        let note = CoachNote(headline: "Good", howItWent: "Fine.", versusPlan: "Fine.", programStatus: "Fine.", nextStep: "Rest.")
        return CoachNoteResult(note: note, usage: LLMUsage(latencyMs: 1), promptText: "p", model: model)
    }
}

private struct FakeKeyTesting: AnthropicKeyTesting {
    let meter: LLMCallMeter
    var failure: LLMError?
    func testKey() async throws -> KeyTestResult {
        let model = ModelChoice.anthropic(.haiku55)
        if let failure {
            await meter.record(model: model, purpose: .keyTest, usage: .zero, latencyMs: 200, error: failure)
            throw failure
        }
        let record = await meter.record(model: model, purpose: .keyTest, usage: TokenUsage(uncachedInput: 12, output: 2), latencyMs: 400, error: nil)
        return KeyTestResult(latencyMs: 400, costMicros: record.costMicros)
    }
}

private struct ScriptedAvailability: ModelAvailabilityChecker {
    func status(for model: ModelChoice) async -> ModelStatus { ModelStatus(availability: .available) }
}

private struct NoTemplate: PlanGenerator {
    func generate(_ request: PlanRequest) async throws -> TrainingPlan { throw LLMError.other("none") }
}

enum SpendFixture {
    static let request = PlanRequest(
        race: RaceSetup(distanceKm: 10, elevationGainM: 0, raceDate: LocalDate(year: 2026, month: 12, day: 6), trainingDays: [.monday, .wednesday, .friday]),
        fitness: FitnessSummary(weeklyKm: 18.44, longestRunKm: 17.0, avgPaceSecPerKm: 337),
        today: LocalDate(year: 2026, month: 10, day: 10),
        planKind: .tenK,
        source: .custom
    )

    static let draft = PlanDraft(weeks: [PlanPhase.base, .base, .base, .build, .build, .peak, .peak, .taper].enumerated().map { offset, phase in
        DraftWeek(index: offset + 1, phase: phase, sessions: [
            DraftSession(weekday: .monday, type: .tempo, distanceKm: 5),
            DraftSession(weekday: .wednesday, type: .easy, distanceKm: 6),
            DraftSession(weekday: .friday, type: .long, distanceKm: 7.5),
        ])
    })
}

/// Everything around the gate, wired with fakes.
private struct Harness {
    let ledger: MemoryLedger
    let settings: MemorySettings
    let secrets: MemorySecrets
    let prices: FakePrices
    let clock = FixedClock()

    init(
        consent: Bool = true,
        key: String? = "sk-ant-test-a1b2",
        caps: SpendCaps = .defaults,
        records: [LLMCallRecord] = [],
        failsReads: Bool = false,
        prices: FakePrices = FakePrices()
    ) {
        ledger = MemoryLedger(records, failsReads: failsReads)
        settings = MemorySettings(LabSettings(consentGiven: consent, caps: caps))
        secrets = MemorySecrets(key.map { [.anthropicAPIKey: $0] } ?? [:])
        self.prices = prices
    }

    var meter: LLMCallMeter { LLMCallMeter(prices: prices, recorder: ledger, clock: clock) }
    var gate: SpendGate { SpendGate(settings: settings, secrets: secrets, prices: prices, ledger: ledger, clock: clock, calendar: utc) }
}

// MARK: - Tests

@Suite("Spend gate")
struct SpendGateTests {
    private let sonnet = ModelChoice.anthropic(.sonnet55)

    @Test func appleModelsAlwaysPass() async throws {
        let harness = Harness(consent: false, key: nil, prices: FakePrices(table: nil))
        try await harness.gate.check(model: .onDevice, purpose: .labPlanDraft, promptCharacters: 1_000_000)
    }

    @Test func claudeNeedsConsentThenAKey() async {
        await #expect(throws: LLMError.spendLimit("Allow Claude runs first.")) {
            try await Harness(consent: false).gate.check(model: sonnet, purpose: .labCoachNote, promptCharacters: 900)
        }
        await #expect(throws: LLMError.unavailable(.needsAPIKey)) {
            try await Harness(key: nil).gate.check(model: sonnet, purpose: .labCoachNote, promptCharacters: 900)
        }
        // The key test sends no health data, so it needs no consent.
        try? await Harness(consent: false).gate.check(model: .anthropic(.haiku55), purpose: .keyTest, promptCharacters: 14)
    }

    @Test func noPriceTableBlocksClaude() async {
        await #expect(throws: LLMError.spendLimit("Price table unavailable. Claude runs are blocked.")) {
            try await Harness(prices: FakePrices(table: nil)).gate.check(model: sonnet, purpose: .labCoachNote, promptCharacters: 900)
        }
    }

    @Test func caps() async throws {
        // Fable plan draft, 3,000 characters = 1,000 tokens: 1,000 x 10 + 4,000 x 50 = 210,000 <= 250,000.
        try await Harness().gate.check(model: .anthropic(.fable51), purpose: .labPlanDraft, promptCharacters: 3_000)
        await #expect(throws: LLMError.spendLimit("Blocked by your spend limit: this run could cost up to $0.21, your per-run limit is $0.01.")) {
            try await Harness(caps: SpendCaps(perRunMicros: 10_000, monthlyMicros: 5_000_000))
                .gate.check(model: .anthropic(.fable51), purpose: .labPlanDraft, promptCharacters: 3_000)
        }
        // $4.99 already spent this month: a $0.21 worst case passes $5.00.
        let spent = LLMCallRecord(
            createdAt: FixedClock().now().addingTimeInterval(-3_600), provider: .anthropic, modelId: "claude-fable-5-1",
            purpose: .labPlanDraft, success: true, usage: .zero, latencyMs: 1, costMicros: 4_990_000, priceTableVersion: "v1"
        )
        await #expect(throws: LLMError.self) {
            try await Harness(records: [spent]).gate.check(model: .anthropic(.fable51), purpose: .labPlanDraft, promptCharacters: 3_000)
        }
    }

    @Test func anUnreadableLedgerBlocks() async {
        await #expect(throws: LLMError.spendLimit(SpendGate.ledgerText)) {
            try await Harness(failsReads: true).gate.check(model: sonnet, purpose: .labCoachNote, promptCharacters: 900)
        }
    }

    @Test func aDeniedRunRecordsNothingAndIsNeverSent() async throws {
        let harness = Harness(caps: SpendCaps(perRunMicros: 1, monthlyMicros: 5_000_000))
        let inner = MeteredDrafting(meter: harness.meter)
        let gated = SpendGatedPlanDraftingModel(inner: inner, gate: harness.gate)
        await #expect(throws: LLMError.self) { try await gated.draftPlan(SpendFixture.request, model: sonnet, purpose: .labPlanDraft) }
        #expect(await inner.calls == 0)
        #expect(await harness.ledger.stored.isEmpty)

        let coaching = CountingCoaching()
        await #expect(throws: LLMError.self) {
            try await SpendGatedCoachingModel(inner: coaching, gate: harness.gate).writeWorkoutNote(WorkoutNoteFixture.samplePrompt, model: sonnet, purpose: .labCoachNote)
        }
        #expect(await coaching.calls == 0)
    }

    @Test func everyValidatingAttemptIsRecordedOnItsOwn() async throws {
        let harness = Harness()
        let drafting = SpendGatedPlanDraftingModel(inner: MeteredDrafting(meter: harness.meter, invalidAttempts: 1), gate: harness.gate)
        let generator = ValidatingPlanGenerator(inner: ModelPlanGenerator(drafting: drafting, model: sonnet))
        let plan = try await generator.generate(SpendFixture.request)
        #expect(plan.generatedBy == "claude-sonnet-5-5-v1")
        let records = await harness.ledger.stored
        #expect(records.count == 2)
        #expect(records.map(\.purpose) == [.planGeneration, .planGeneration])
        #expect(records.map(\.costMicros) == [27_700, 27_700])
        #expect(records.allSatisfy { $0.success && $0.modelId == "claude-sonnet-5-5" })
    }

    @Test func aFailedRunStillRecordsTheReportedUsage() async throws {
        let harness = Harness()
        let drafting = SpendGatedPlanDraftingModel(inner: MeteredDrafting(meter: harness.meter, failure: .providerUnavailable), gate: harness.gate)
        await #expect(throws: LLMError.providerUnavailable) { try await drafting.draftPlan(SpendFixture.request, model: sonnet, purpose: .labPlanDraft) }
        let record = try #require(await harness.ledger.stored.first)
        #expect(!record.success)
        #expect(record.errorKind == "providerUnavailable")
        #expect(record.usage == TokenUsage(uncachedInput: 1_850, output: 300))
        #expect(record.costMicros == Int64(3_700 + 3_000))
    }
}

@Suite("Call meter")
struct LLMCallMeterTests {
    @Test func claudeIsPricedAndAppleIsFree() async {
        let harness = Harness()
        let claude = await harness.meter.record(
            model: .anthropic(.haiku55), purpose: .labCoachNote, usage: TokenUsage(uncachedInput: 600, output: 150), latencyMs: 700, error: nil
        )
        #expect(claude.costMicros == 135)
        #expect(claude.provider == .anthropic && claude.modelId == "claude-haiku-5-5")
        #expect(claude.priceTableVersion == "v1 2026-10-14")
        #expect(claude.createdAt == FixedClock().now())
        let apple = await harness.meter.record(model: .onDevice, purpose: .planGeneration, usage: TokenUsage(uncachedInput: 600, output: 500), latencyMs: 2_000, error: .timedOut)
        #expect(apple.costMicros == nil)
        #expect(apple.provider == .apple && apple.modelId == "onDevice")
        #expect(!apple.success && apple.errorKind == "timedOut")
        #expect(await harness.ledger.stored.count == 2)
    }
}

@Suite("Lab runner with Claude")
struct ClaudeLabRunnerTests {
    @Test func withoutConsentTheLabShowsWhy() async {
        let harness = Harness(consent: false)
        let lab = RunModelExperiment(
            coaching: SpendGatedCoachingModel(inner: CountingCoaching(), gate: harness.gate),
            drafting: SpendGatedPlanDraftingModel(inner: MeteredDrafting(meter: harness.meter), gate: harness.gate),
            availability: ScriptedAvailability(),
            template: NoTemplate()
        )
        let result = await lab.run(.workoutNote(WorkoutNoteFixture.requestA), model: .anthropic(.sonnet55))
        #expect(result.error == .spendLimit("Allow Claude runs first."))
        #expect(await lab.availableModels(.anthropic) == ModelChoice.claude)
    }

    @Test func aLabPlanDraftCarriesItsCost() async {
        let harness = Harness()
        let lab = RunModelExperiment(
            coaching: CountingCoaching(),
            drafting: SpendGatedPlanDraftingModel(inner: MeteredDrafting(meter: harness.meter), gate: harness.gate),
            availability: ScriptedAvailability(),
            template: NoTemplate()
        )
        let result = await lab.run(.planDraft(SpendFixture.request), model: .anthropic(.sonnet55))
        #expect(result.usage?.costMicros == 27_700)
        #expect(await harness.ledger.stored.map(\.purpose) == [.labPlanDraft])
    }
}

@Suite("Spend overview, projection and settings")
struct SpendOverviewTests {
    private func record(_ model: AnthropicModel, _ offset: TimeInterval, micros: Int64, purpose: LLMCallPurpose, usage: TokenUsage) -> LLMCallRecord {
        LLMCallRecord(
            createdAt: FixedClock().now().addingTimeInterval(offset), provider: .anthropic, modelId: model.apiId, purpose: purpose,
            success: true, usage: usage, latencyMs: 1, costMicros: micros, priceTableVersion: "v1"
        )
    }

    @Test func overviewAndProjection() async throws {
        let records = [
            record(.sonnet55, -60, micros: 27_700, purpose: .labPlanDraft, usage: TokenUsage(uncachedInput: 1_850, output: 2_400)),
            record(.haiku55, -40 * 86_400, micros: 135, purpose: .labCoachNote, usage: TokenUsage(uncachedInput: 600, output: 150)),
        ]
        let harness = Harness(records: records)
        let overview = await GetSpendOverview(ledger: harness.ledger, prices: harness.prices, clock: harness.clock, calendar: utc).execute(.thisMonth)
        #expect(overview.totals.micros == 27_700)
        #expect(overview.monthSpentMicros == 27_700)
        #expect(overview.rows.map(\.name) == ["Sonnet 5.5"])
        #expect(overview.firstRecordDate == records[1].createdAt)
        #expect(overview.pricesLastVerified == LocalDate(year: 2026, month: 10, day: 14))
        #expect(!overview.pricesAreStale)
        let allTime = await GetSpendOverview(ledger: harness.ledger, prices: harness.prices, clock: harness.clock, calendar: utc).execute(.allTime)
        #expect(allTime.totals.micros == 27_835)

        let rows = try #require(await ProjectCosts(ledger: harness.ledger, prices: harness.prices).execute(.defaults))
        #expect(rows.first { $0.model == .sonnet55 }?.planDraftMicros == 27_700)
        #expect(await ProjectCosts(ledger: harness.ledger, prices: FakePrices(table: nil)).execute(.defaults) == nil)

        try await ClearUsageHistory(ledger: harness.ledger).execute()
        #expect(await harness.ledger.stored.isEmpty)
    }

    @Test func settings() async {
        let store = MemorySettings()
        let settings = LabSpendSettings(store: store)
        #expect(await settings.load() == LabSettings(consentGiven: false, caps: .defaults, scenario: .defaults))
        await settings.grantConsent()
        await settings.setCaps(SpendCaps(perRunMicros: 10_000, monthlyMicros: 2_000_000))
        await settings.setScenario(CostScenario(plansPerMonth: 1, notesPerMonth: 10))
        #expect(await settings.load() == LabSettings(
            consentGiven: true, caps: SpendCaps(perRunMicros: 10_000, monthlyMicros: 2_000_000), scenario: CostScenario(plansPerMonth: 1, notesPerMonth: 10)
        ))
    }

    @Test func dollarInput() {
        #expect(DollarInput.micros("0.25") == 250_000)
        #expect(DollarInput.micros("5") == 5_000_000)
        #expect(DollarInput.micros("$1,50") == 1_500_000)
        #expect(DollarInput.micros("0.01") == 10_000)
        #expect(DollarInput.micros("0") == nil)
        #expect(DollarInput.micros("abc") == nil)
        #expect(DollarInput.micros("-1") == nil)
        #expect(DollarInput.text(micros: 250_000) == "0.25")
        #expect(DollarInput.text(micros: 5_000_000) == "5.00")
    }
}

@Suite("Anthropic key")
struct AnthropicKeyTests {
    @Test func saveExposesOnlyTheLastFourAndRemoveDeletes() async throws {
        let secrets = MemorySecrets()
        let keys = ManageAnthropicKey(secrets: secrets)
        #expect(await keys.status() == .none)
        #expect(APIKeyStatus.none.text == "No key saved")
        let status = try await keys.save("  sk-ant-api03-secretsecret-a1b2\n")
        #expect(status == .saved(lastFour: "a1b2"))
        #expect(status.text == "Saved · ends \u{2026}a1b2")
        #expect(await secrets.values[.anthropicAPIKey] == "sk-ant-api03-secretsecret-a1b2")
        #expect(await keys.status() == .saved(lastFour: "a1b2"))
        await #expect(throws: ManageAnthropicKey.Failure.empty) { try await keys.save("   ") }
        try await keys.remove()
        #expect(await secrets.values.isEmpty)
        #expect(await keys.status() == .none)
    }

    @Test func theKeyTestIsRecorded() async throws {
        let harness = Harness(consent: false)
        let result = try await TestAnthropicKey(gate: harness.gate, tester: FakeKeyTesting(meter: harness.meter)).execute()
        #expect(result.latencyMs == 400)
        #expect(result.costMicros == Int64(1 + 1))
        let record = try #require(await harness.ledger.stored.first)
        #expect(record.purpose == .keyTest && record.modelId == "claude-haiku-5-5" && record.success)

        await #expect(throws: LLMError.authenticationFailed) {
            try await TestAnthropicKey(gate: harness.gate, tester: FakeKeyTesting(meter: harness.meter, failure: .authenticationFailed)).execute()
        }
        await #expect(throws: LLMError.unavailable(.needsAPIKey)) {
            try await TestAnthropicKey(gate: Harness(key: nil).gate, tester: FakeKeyTesting(meter: harness.meter)).execute()
        }
    }

    @Test func errorSentences() {
        let text = LLMErrorText(calendar: utc, locale: Locale(identifier: "en_GB"), now: { FixedClock().now() })
        #expect(text.message(.unavailable(.needsAPIKey)) == "Add your Anthropic API key to run Claude models.")
        #expect(text.message(.authenticationFailed) == "Anthropic rejected the API key.")
        #expect(text.message(.rateLimited(retryAfter: 20)) == "Anthropic is rate limiting requests. Try again in 20 s.")
        #expect(text.message(.rateLimited(retryAfter: nil)) == "Anthropic is rate limiting requests. Try again in a moment.")
        #expect(text.message(.billingProblem) == "Your Anthropic credit balance is too low. Add credits in the Claude Console.")
        #expect(text.message(.providerUnavailable) == "Anthropic is temporarily unavailable.")
        #expect(text.message(.spendLimit("Allow Claude runs first.")) == "Allow Claude runs first.")
    }
}
