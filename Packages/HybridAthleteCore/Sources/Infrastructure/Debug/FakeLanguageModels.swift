#if DEBUG
import Foundation
import Application
import Domain

/// The `-fakeLLM <scenario>` launch argument: canned model answers without
/// FoundationModels, for UI tests and the simulator. DEBUG builds only.
public enum FakeLLMScenario: String, Sendable, CaseIterable {
    /// Every model is available and answers well. The plan draft is the
    /// template's own structure, so it validates.
    case ok
    /// A plan draft without revision notes breaks one rule (a Tuesday session in
    /// week 1); with notes it is valid. So the Lab (one attempt) shows 1 issue
    /// and the real flow (two attempts) succeeds.
    case invalidPlan
    /// No model is available (Apple Intelligence not ready).
    case unavailable
    /// Every call hits the daily limit, resetting in 3 hours.
    case quota
    /// Like ok, but each answer takes 3 s.
    case slow
    /// Claude answers: plan drafts report 1,850 uncached input and 2,400 output
    /// tokens, coach notes 600 and 150. Apple's models behave as in ok.
    case anthropicOk
    /// Claude calls fail as if the key were missing.
    case noKey
    /// Anthropic rejects the key.
    case badKey
    /// The credit balance is too low.
    case credits
    /// Anthropic rate limits every call (try again in 20 s).
    case rateLimited

    /// What a Claude call does in this scenario; Apple-only scenarios answer.
    var claudeFailure: LLMError? {
        switch self {
        case .noKey: .unavailable(.needsAPIKey)
        case .badKey: .authenticationFailed
        case .credits: .billingProblem
        case .rateLimited: .rateLimited(retryAfter: 20)
        case .ok, .invalidPlan, .unavailable, .quota, .slow, .anthropicOk: nil
        }
    }
}

/// Canned availability: on-device 4,096 and PCC 32,768 tokens of context; a
/// Claude model is available once a key is saved in the (in-memory) store.
public struct FakeModelAvailabilityChecker: ModelAvailabilityChecker {
    static let onDeviceContext = 4_096
    static let privateCloudContext = 32_768

    private let scenario: FakeLLMScenario
    private let clock: any Clock
    private let secrets: (any SecretStore)?

    public init(scenario: FakeLLMScenario, clock: any Clock, secrets: (any SecretStore)? = nil) {
        self.scenario = scenario
        self.clock = clock
        self.secrets = secrets
    }

    public func status(for model: ModelChoice) async -> ModelStatus {
        if case .anthropic = model {
            let hasKey = await secrets?.hasSecret(.anthropicAPIKey) ?? false
            return ModelStatus(availability: hasKey ? .available : .needsAPIKey)
        }
        if scenario == .unavailable { return ModelStatus(availability: .notReady) }
        switch model {
        case .onDevice:
            return ModelStatus(availability: .available, contextSize: Self.onDeviceContext)
        case .privateCloud:
            let quota = scenario == .quota
                ? QuotaStatus(state: .limitReached, resetDate: FakeLanguageModel.resetDate(clock))
                : QuotaStatus(state: .belowLimit, resetDate: nil)
            return ModelStatus(availability: .available, contextSize: Self.privateCloudContext, quota: quota)
        case .anthropic:
            return ModelStatus(availability: .needsAPIKey)
        }
    }
}

/// Canned coach notes and plan drafts. Like the real adapters, every answered or
/// failed attempt is recorded through the meter (with the canned usage).
public struct FakeLanguageModel: CoachingModel, PlanDraftingModel {
    static let claudePlanDraftUsage = TokenUsage(uncachedInput: 1_850, output: 2_400)
    static let claudeCoachNoteUsage = TokenUsage(uncachedInput: 600, output: 150)

    private let scenario: FakeLLMScenario
    private let clock: any Clock
    private let meter: LLMCallMeter?

    public init(scenario: FakeLLMScenario, clock: any Clock, meter: LLMCallMeter? = nil) {
        self.scenario = scenario
        self.clock = clock
        self.meter = meter
    }

    static func resetDate(_ clock: any Clock) -> Date {
        clock.now().addingTimeInterval(3 * 3_600)
    }

    public func writeWorkoutNote(_ request: CoachNoteRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> CoachNoteResult {
        let latency = try await answerOrFail(model, purpose: purpose)
        let planned = SessionFormat.distanceText(km: request.plannedKm)
        let observation = request.doneKm.map { "You ran \(SessionFormat.distanceText(km: $0)) of the planned \(planned)." }
            ?? "No run was recorded for this session."
        let note = CoachNote(
            headline: "\(request.sessionName): good work",
            observation: observation + " Keep the easy days easy.",
            nextStep: "Keep your next run conversational."
        )
        let prompt = CoachNotePromptBuilder.build(request)
        let tokens = model.provider == .anthropic ? Self.claudeCoachNoteUsage : appleUsage(model, input: 312, output: 64)
        let usage = await recorded(model, purpose: purpose, tokens: tokens, latency: latency)
        return CoachNoteResult(note: note, usage: usage, promptText: prompt.fullText, model: model)
    }

    public func draftPlan(_ request: PlanRequest, model: ModelChoice, purpose: LLMCallPurpose) async throws -> PlanDraftResult {
        let latency = try await answerOrFail(model, purpose: purpose)
        let template = TemplatePlanGenerator.plan(for: request)
        var weeks = template.weeks.map { week in
            DraftWeek(
                index: week.index,
                phase: week.phase,
                sessions: week.sessions.map { DraftSession(weekday: $0.date.weekday, type: $0.type, distanceKm: $0.distanceKm) }
            )
        }
        if scenario == .invalidPlan, request.revisionNotes.isEmpty, let first = weeks.first, let session = first.sessions.first {
            // One broken rule: the first session moves to a Tuesday.
            let broken = DraftSession(weekday: .tuesday, type: session.type, distanceKm: session.distanceKm)
            weeks[0] = DraftWeek(index: first.index, phase: first.phase, sessions: [broken] + first.sessions.dropFirst())
        }
        let prompt = PlanPromptBuilder.build(request)
        let tokens = model.provider == .anthropic ? Self.claudePlanDraftUsage : appleUsage(model, input: 640, output: 520)
        let usage = await recorded(model, purpose: purpose, tokens: tokens, latency: latency)
        return PlanDraftResult(draft: PlanDraft(weeks: weeks), usage: usage, promptText: prompt.fullText)
    }

    /// The latency in ms, after waiting it out; or the scenario's failure (a Claude
    /// failure after a request was "sent" is recorded with no tokens).
    private func answerOrFail(_ model: ModelChoice, purpose: LLMCallPurpose) async throws -> Int {
        if model.provider == .anthropic {
            guard let failure = scenario.claudeFailure else { return 1_800 }
            if failure != .unavailable(.needsAPIKey) {
                await meter?.record(model: model, purpose: purpose, usage: .zero, latencyMs: 300, error: failure)
            }
            throw failure
        }
        switch scenario {
        case .unavailable: throw LLMError.unavailable(.notReady)
        case .quota: throw LLMError.quotaLimitReached(resetDate: Self.resetDate(clock))
        case .slow:
            try await Task.sleep(for: .seconds(3))
            return 3_000
        case .ok, .invalidPlan, .anthropicOk, .noKey, .badKey, .credits, .rateLimited:
            return 1_200
        }
    }

    private func appleUsage(_ model: ModelChoice, input: Int, output: Int) -> TokenUsage {
        TokenUsage(uncachedInput: input, output: output, reasoning: model.isPrivateCloud ? 48 : nil)
    }

    private func recorded(_ model: ModelChoice, purpose: LLMCallPurpose, tokens: TokenUsage, latency: Int) async -> LLMUsage {
        let record = await meter?.record(model: model, purpose: purpose, usage: tokens, latencyMs: latency, error: nil)
        return LLMUsage(tokens, latencyMs: latency, costMicros: record?.costMicros)
    }
}

/// `-fakeLLM`: the key test without a network. badKey fails; anything else answers.
public struct FakeKeyTester: AnthropicKeyTesting {
    private let scenario: FakeLLMScenario
    private let meter: LLMCallMeter?

    public init(scenario: FakeLLMScenario, meter: LLMCallMeter?) {
        self.scenario = scenario
        self.meter = meter
    }

    public func testKey() async throws -> KeyTestResult {
        let model = ModelChoice.anthropic(LLMSpendRules.keyTestModel)
        if let failure = scenario.claudeFailure {
            await meter?.record(model: model, purpose: .keyTest, usage: .zero, latencyMs: 300, error: failure)
            throw failure
        }
        let record = await meter?.record(model: model, purpose: .keyTest, usage: TokenUsage(uncachedInput: 12, output: 2), latencyMs: 400, error: nil)
        return KeyTestResult(latencyMs: 400, costMicros: record?.costMicros)
    }
}
#endif
