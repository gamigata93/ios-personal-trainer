import Foundation
import Testing
import FoundationModels
import ClaudeForFoundationModels
import GRDB
import Application
import Domain
@testable import Infrastructure

private struct TestClock: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 1_793_178_000) } // Wed 28 Oct 2026, 09:00 UTC
}

/// Stands in for the package's `package`-internal `APIError`: same description shape.
private struct FakeAPIError: LocalizedError {
    let errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

@Suite("Anthropic error mapping")
struct AnthropicErrorMappingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func map(_ error: any Error) -> LLMError {
        FoundationModelsMapping.llmError(error, provider: .anthropic, now: now)
    }

    @Test func keyRejected() {
        #expect(map(ClaudeError.missingCredential) == .authenticationFailed)
        #expect(map(FakeAPIError("authentication_error: invalid x-api-key (request_id: req_1)")) == .authenticationFailed)
        #expect(map(FakeAPIError("permission_error: Your API key does not have permission")) == .authenticationFailed)
    }

    @Test func rateLimitsAndOverload() {
        #expect(map(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "Number of requests has exceeded your rate limit"))) == .rateLimited(retryAfter: nil))
        #expect(map(LanguageModelError.rateLimited(.init(resetDate: now.addingTimeInterval(20), debugDescription: "slow down"))) == .rateLimited(retryAfter: 20))
        #expect(map(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "Overloaded (request_id: req_2)"))) == .providerUnavailable)
        #expect(map(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "HTTP 529: <html>"))) == .providerUnavailable)
        #expect(map(FakeAPIError("rate_limit_error: HTTP 429: too many")) == .rateLimited(retryAfter: nil))
    }

    @Test func billingAndServerErrors() {
        #expect(map(FakeAPIError("invalid_request_error: Your credit balance is too low to access the Anthropic API.")) == .billingProblem)
        #expect(map(FakeAPIError("api_error: Internal server error")) == .providerUnavailable)
        #expect(map(FakeAPIError("api_error: HTTP 503: upstream unavailable")) == .providerUnavailable)
        #expect(map(FakeAPIError("overloaded_error: Overloaded")) == .providerUnavailable)
    }

    @Test func networkAndSharedCases() {
        #expect(map(URLError(.notConnectedToInternet)) == .networkUnavailable)
        #expect(map(URLError(.networkConnectionLost)) == .networkUnavailable)
        #expect(map(URLError(.timedOut)) == .timedOut)
        #expect(map(LanguageModelError.timeout(.init(debugDescription: "slow"))) == .timedOut)
        #expect(map(LanguageModelError.contextSizeExceeded(.init(contextSize: 0, tokenCount: 0, debugDescription: "big"))) == .contextTooLarge)
        #expect(map(CancellationError()) == .cancelled)
        #expect(map(FakeAPIError("not_found_error: model: claude-x")) == .other("not_found_error: model: claude-x"))
    }

    @Test func appleKeepsItsOwnMeaning() {
        let reset = now.addingTimeInterval(60)
        #expect(FoundationModelsMapping.llmError(LanguageModelError.rateLimited(.init(resetDate: reset, debugDescription: "x"))) == .quotaLimitReached(resetDate: reset))
        #expect(FoundationModelsMapping.llmError(ClaudeError.missingCredential) != .authenticationFailed)
    }

    @Test func modelsMapToThePackageConstants() {
        for model in AnthropicModel.allCases {
            #expect(FoundationModelFactory.claudeModel(model).id == model.apiId)
            #expect(FoundationModelFactory.claudeModel(model).capabilities.structuredOutput)
        }
        let options = FoundationModelFactory.generationOptions(for: .anthropic(.sonnet55), task: .planDraft)
        #expect(options.maximumResponseTokens == 4_000)
        #expect(FoundationModelFactory.generationOptions(for: .onDevice, task: .planDraft).maximumResponseTokens == nil)
    }
}

@Suite("Claude adapters without a key")
struct ClaudeWithoutKeyTests {
    @Test func noKeyMeansNothingIsSentOrRecorded() async throws {
        let ledger = InMemoryLLMUsageLedger()
        let meter = LLMCallMeter(prices: BundledPriceTableProvider(), recorder: ledger, clock: TestClock())
        let coaching = FoundationModelsCoachingModel(secrets: InMemorySecretStore(), meter: meter)
        await #expect(throws: LLMError.unavailable(.needsAPIKey)) {
            try await coaching.writeWorkoutNote(WorkoutNoteFixture.samplePrompt, model: .anthropic(.haiku55), purpose: .labCoachNote)
        }
        await #expect(throws: LLMError.unavailable(.needsAPIKey)) {
            try await ClaudeKeyTester(secrets: InMemorySecretStore(), meter: meter).testKey()
        }
        #expect(try await ledger.records(since: nil).isEmpty)
    }

    @Test func availabilityFollowsTheSavedKey() async throws {
        let secrets = InMemorySecretStore()
        let checker = FoundationModelAvailabilityChecker(secrets: secrets)
        #expect(await checker.status(for: .anthropic(.opus55)).availability == .needsAPIKey)
        try await secrets.setSecret("sk-ant-test", for: .anthropicAPIKey)
        #expect(await checker.status(for: .anthropic(.opus55)).availability == .available)
    }
}

@Suite("Bundled price table")
struct BundledPriceTableTests {
    @Test func theShippedFileHasTheVerifiedPrices() throws {
        let table = try #require(BundledPriceTableProvider().priceTable())
        #expect(table.lastVerified == LocalDate(year: 2026, month: 10, day: 14))
        #expect(table.source == "https://platform.claude.com/docs/en/about-claude/pricing")
        #expect(table.models.map(\.id) == ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"])
        func rates(_ id: String, _ tokens: Int = 1_000) throws -> [Decimal] {
            let rates = try #require(table.rates(modelApiId: id, promptTokens: tokens))
            return [rates.input, rates.output, rates.cacheWrite5m, rates.cacheWrite1h, rates.cacheRead]
        }
        let d = { (text: String) in Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? -1 }
        #expect(try rates("claude-haiku-5-5") == ["0.10", "0.50", "0.125", "0.20", "0.01"].map(d))
        #expect(try rates("claude-haiku-5-5", 100_001) == ["0.50", "2.50", "0.625", "1.00", "0.05"].map(d))
        #expect(try rates("claude-sonnet-5-5") == ["2", "10", "2.50", "4", "0.10"].map(d))
        #expect(try rates("claude-opus-5-5") == ["4", "20", "5", "8", "0.20"].map(d))
        #expect(try rates("claude-fable-5-1") == ["10", "50", "12.50", "20", "0.25"].map(d))
        // Every Lab model has a price.
        for model in AnthropicModel.allCases { #expect(table.rates(modelApiId: model.apiId, promptTokens: 1) != nil) }
    }

    @Test func aMissingOrMalformedFileGivesNoTable() throws {
        #expect(BundledPriceTableProvider(url: nil).priceTable() == nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"schemaVersion": 1, "models": [ { "id": "x", "rates": { "input": 2 } } ]}"#.utf8).write(to: url)
        #expect(BundledPriceTableProvider(url: url).priceTable() == nil)
    }
}

@Suite("GRDB usage ledger")
struct GRDBLLMUsageLedgerTests {
    let provider: DatabaseProvider
    let ledger: GRDBLLMUsageLedger

    init() throws {
        provider = try DatabaseProvider.inMemory()
        ledger = GRDBLLMUsageLedger(database: provider)
    }

    private func record(_ offsetDays: Int, cost: Int64?, model: String = "claude-sonnet-5-5", provider: LLMProvider = .anthropic) -> LLMCallRecord {
        LLMCallRecord(
            createdAt: TestClock().now().addingTimeInterval(Double(offsetDays) * 86_400),
            provider: provider, modelId: model, purpose: .labPlanDraft, success: cost != nil, errorKind: cost == nil ? "billingProblem" : nil,
            usage: TokenUsage(uncachedInput: 1_850, cacheRead: 10, cacheWrite: 0, output: 2_400, reasoning: provider == .apple ? 48 : nil),
            latencyMs: 3_200, costMicros: cost, priceTableVersion: "v1 2026-10-14"
        )
    }

    @Test func recordAndReadBack() async throws {
        let original = record(0, cost: 27_700)
        await ledger.record(original)
        await ledger.record(record(-1, cost: nil, model: "onDevice", provider: .apple))
        let all = try await ledger.records(since: nil)
        #expect(all.count == 2)
        #expect(all[0].modelId == "onDevice" && all[0].usage.reasoning == 48 && !all[0].success && all[0].errorKind == "billingProblem")
        let stored = try #require(all.last)
        #expect(stored.id != nil)
        #expect(stored.with(id: 0) == original.with(id: 0))
        #expect(try await ledger.firstRecordDate() == all[0].createdAt)
    }

    @Test func queryByPeriodAndClear() async throws {
        for offset in [-40, -5, -1, 0] { await ledger.record(record(offset, cost: 100)) }
        let since = TestClock().now().addingTimeInterval(-2 * 86_400)
        #expect(try await ledger.records(since: since).count == 2)
        try await ledger.clear()
        #expect(try await ledger.records(since: nil).isEmpty)
        #expect(try await ledger.firstRecordDate() == nil)
    }

    @Test func theSchemaHasNoPromptOrOutputText() async throws {
        let columns = try await provider.writer.read { db in try db.columns(in: "llm_usage").map(\.name) }
        #expect(columns == [
            "id", "createdAt", "provider", "modelId", "purpose", "success", "errorKind", "uncachedInput", "cacheRead",
            "cacheWrite", "output", "reasoning", "latencyMs", "costMicros", "priceTableVersion",
        ])
        #expect(!columns.contains { $0.lowercased().contains("prompt") || $0.lowercased().contains("text") || $0.lowercased().contains("key") })
    }

    @Test func v2RunsOnceAfterV1AndKeepsThePlan() async throws {
        let queue = try DatabaseQueue()
        try PlanDatabaseMigrations.migrator.migrate(queue, upTo: "v1_plan")
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO plan (id, schemaVersion, createdAt, generatedBy, planKind, raceDistanceKm, raceElevationM, raceDate,
                    planStart, trainingDays, isActive)
                VALUES ('p1', 1, '2026-10-01T00:00:00.000Z', 'template-v1', 'tenK', 10, 0, '2026-12-06', '2026-10-12', 'monday', 1)
                """)
        }
        try PlanDatabaseMigrations.migrator.migrate(queue)
        try PlanDatabaseMigrations.migrator.migrate(queue)
        let applied = try await queue.read { db in try PlanDatabaseMigrations.migrator.appliedMigrations(db) }
        #expect(applied == ["v1_plan", "v2_llm_usage", "v3_coach_note", "v4_workout_analysis"])
        let plans = try await queue.read { db in try String.fetchAll(db, sql: "SELECT id FROM plan") }
        #expect(plans == ["p1"])
        let usageRows = try await queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM llm_usage") }
        #expect(usageRows == 0)
    }
}

@Suite("Lab settings store")
struct LabSettingsStoreTests {
    @Test func roundTripWithoutTheKey() async throws {
        let suite = "lab-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsLabSettingsStore(defaults: defaults)
        #expect(await store.load() == LabSettings())
        let changed = LabSettings(consentGiven: true, caps: SpendCaps(perRunMicros: 10_000, monthlyMicros: 2_000_000), scenario: CostScenario(plansPerMonth: 4, notesPerMonth: 12))
        await store.save(changed)
        #expect(await store.load() == changed)
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("lab.") }
        #expect(!keys.contains { $0.lowercased().contains("key") && !$0.lowercased().contains("consent") })
    }
}

@Suite("Fake Claude scenarios")
struct FakeClaudeScenarioTests {
    private func harness(_ scenario: FakeLLMScenario) -> (FakeLanguageModel, InMemoryLLMUsageLedger) {
        let ledger = InMemoryLLMUsageLedger()
        let meter = LLMCallMeter(prices: BundledPriceTableProvider(), recorder: ledger, clock: TestClock())
        return (FakeLanguageModel(scenario: scenario, clock: TestClock(), meter: meter), ledger)
    }

    @Test func okPricesSonnetAndHaikuAsTheSpecSays() async throws {
        let (fake, ledger) = harness(.anthropicOk)
        let draft = try await fake.draftPlan(SeedPlan.request, model: .anthropic(.sonnet55), purpose: .labPlanDraft)
        #expect(draft.usage.costMicros == 27_700)
        let note = try await fake.writeWorkoutNote(WorkoutNoteFixture.samplePrompt, model: .anthropic(.haiku55), purpose: .labCoachNote)
        #expect(note.usage.costMicros == 135)
        _ = try await fake.writeWorkoutNote(WorkoutNoteFixture.samplePrompt, model: .onDevice, purpose: .labCoachNote)
        let records = try await ledger.records(since: nil)
        #expect(records.map(\.costMicros) == [27_700, 135, nil])
    }

    @Test func failuresAreRecordedWithTheirKind() async throws {
        for (scenario, error) in [(FakeLLMScenario.badKey, LLMError.authenticationFailed), (.credits, .billingProblem), (.rateLimited, .rateLimited(retryAfter: 20))] {
            let (fake, ledger) = harness(scenario)
            await #expect(throws: error) { try await fake.draftPlan(SeedPlan.request, model: .anthropic(.sonnet55), purpose: .labPlanDraft) }
            #expect(try await ledger.records(since: nil).map(\.errorKind) == [error.kind])
        }
        let (fake, ledger) = harness(.noKey)
        await #expect(throws: LLMError.unavailable(.needsAPIKey)) { try await fake.draftPlan(SeedPlan.request, model: .anthropic(.sonnet55), purpose: .labPlanDraft) }
        #expect(try await ledger.records(since: nil).isEmpty)
    }
}
