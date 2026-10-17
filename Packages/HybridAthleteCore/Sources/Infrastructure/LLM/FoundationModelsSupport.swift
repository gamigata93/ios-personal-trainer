import Foundation
import FoundationModels
import ClaudeForFoundationModels
import Application
import Domain

/// Limits for Foundation Models calls.
public enum FoundationModelsLimits {
    /// A coach note gives up after this long.
    public static let coachNoteTimeoutSeconds: Double = 45
    /// A plan draft gives up after this long.
    public static let planDraftTimeoutSeconds: Double = 90
    /// The key test gives up after this long.
    public static let keyTestTimeoutSeconds: Double = 30
    /// Room kept free in the on-device context for the plan draft's answer.
    public static let planDraftOutputReserveTokens = 1_000
}

/// Whether this build may use Private Cloud Compute. It needs the managed
/// entitlement, which the app does not have yet; flip this only together with
/// adding the entitlement, or the build will not install.
public struct FoundationModelsConfiguration: Sendable {
    public let privateCloudComputeEnabled: Bool

    public init(privateCloudComputeEnabled: Bool) {
        self.privateCloudComputeEnabled = privateCloudComputeEnabled
    }

    /// No entitlement yet.
    public static let current = FoundationModelsConfiguration(privateCloudComputeEnabled: false)
}

/// Builds the framework model for a choice: Apple's on-device or Private Cloud
/// Compute model, or Claude through ClaudeForFoundationModels (same
/// `LanguageModel` protocol, so the adapters serve all of them unchanged).
struct FoundationModelFactory: Sendable {
    let configuration: FoundationModelsConfiguration
    /// Where the Claude key is read from, at call time only.
    let secrets: (any SecretStore)?

    /// The model, or `LLMError.unavailable` when it cannot run now.
    func model(for choice: ModelChoice, timeoutSeconds: Double) async throws(LLMError) -> any LanguageModel {
        switch choice {
        case .onDevice:
            let model = SystemLanguageModel.default
            let availability = FoundationModelsMapping.availability(model.availability)
            guard availability.isAvailable else { throw .unavailable(availability) }
            return model
        case .privateCloud:
            guard configuration.privateCloudComputeEnabled else { throw .unavailable(.notEnabledForBuild) }
            let model = PrivateCloudComputeLanguageModel()
            let availability = FoundationModelsMapping.availability(model.availability)
            guard availability.isAvailable else { throw .unavailable(availability) }
            return model
        case .anthropic(let claude):
            // Read for this call only; the value is not kept here afterwards.
            guard let key = try? await secrets?.secret(for: .anthropicAPIKey), !key.isEmpty else {
                throw .unavailable(.needsAPIKey)
            }
            return ClaudeLanguageModel(name: Self.claudeModel(claude), auth: .apiKey(key), timeout: timeoutSeconds)
        }
    }

    /// The package's compiled-in model constants.
    static func claudeModel(_ model: AnthropicModel) -> ClaudeModel {
        switch model {
        case .haiku55: .haiku5_5
        case .sonnet55: .sonnet5_5
        case .opus55: .opus5_5
        case .fable51: .fable5_1
        }
    }

    /// The schema goes in the prompt; Private Cloud Compute gets its reasoning
    /// level. Claude gets `.light`, which the package sends as effort "low", so
    /// adaptive thinking leaves room under the output ceiling.
    static func contextOptions(for choice: ModelChoice) -> ContextOptions {
        switch choice {
        case .onDevice:
            ContextOptions(includeSchemaInPrompt: true)
        case .privateCloud(let level):
            ContextOptions(includeSchemaInPrompt: true, reasoningLevel: reasoningLevel(level))
        case .anthropic:
            ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .light)
        }
    }

    /// Claude's output is capped at the task's ceiling (sent as max_tokens);
    /// Apple's models keep their defaults.
    static func generationOptions(for choice: ModelChoice, task: LLMTask) -> GenerationOptions {
        choice.provider == .anthropic ? GenerationOptions(maximumResponseTokens: task.maxOutputTokens) : GenerationOptions()
    }

    static func reasoningLevel(_ level: ReasoningLevel) -> ContextOptions.ReasoningLevel {
        switch level {
        case .light: .light
        case .moderate: .moderate
        case .deep: .deep
        }
    }
}

/// One attempt against a model: build it, run one session within the deadline,
/// and record the attempt (success or failure, with the usage the framework
/// reported) once a request was sent. Nothing is recorded when the model could
/// not be built (no key, unavailable) because nothing left the phone.
struct ModelCallRunner: Sendable {
    let factory: FoundationModelFactory
    let meter: LLMCallMeter?

    func run<T: Sendable>(
        _ choice: ModelChoice,
        purpose: LLMCallPurpose,
        instructions: String?,
        timeoutSeconds: Double,
        prepare: (any LanguageModel) async throws -> Void = { _ in },
        respond: @escaping @Sendable (LanguageModelSession) async throws -> (T, LanguageModelSession.Usage)
    ) async throws(LLMError) -> (value: T, usage: LLMUsage) {
        let started = ContinuousClock.now
        let model: any LanguageModel
        do {
            model = try await factory.model(for: choice, timeoutSeconds: timeoutSeconds)
            try await prepare(model)
        } catch {
            throw FoundationModelsMapping.llmError(error, provider: choice.provider)
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let (value, usage) = try await withDeadline(seconds: timeoutSeconds) { try await respond(session) }
            try Task.checkCancellation()
            let tokens = FoundationModelsMapping.tokens(usage, provider: choice.provider)
            let latency = elapsedMs(since: started)
            let record = await meter?.record(model: choice, purpose: purpose, usage: tokens, latencyMs: latency, error: nil)
            return (value, LLMUsage(tokens, latencyMs: latency, costMicros: record?.costMicros))
        } catch {
            let mapped = FoundationModelsMapping.llmError(error, provider: choice.provider)
            // A failed or cancelled request may still be billed for what was used.
            await meter?.record(
                model: choice,
                purpose: purpose,
                usage: FoundationModelsMapping.tokens(session.usage, provider: choice.provider),
                latencyMs: elapsedMs(since: started),
                error: mapped
            )
            throw mapped
        }
    }
}

/// Framework values to domain values, in one place.
enum FoundationModelsMapping {
    /// The ONE mapping from framework errors to `LLMError`. For Claude, the
    /// package's own errors are read first (`AnthropicErrorMapping`).
    static func llmError(_ error: any Error, provider: LLMProvider = .apple, now: Date = .now) -> LLMError {
        if let error = error as? LLMError { return error }
        if error is CancellationError { return .cancelled }
        if provider == .anthropic, let mapped = AnthropicErrorMapping.llmError(error, now: now) { return mapped }
        if let error = error as? PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .networkFailure: return .networkUnavailable
            case .quotaLimitReached(let quota): return .quotaLimitReached(resetDate: quota.resetDate)
            case .serviceUnavailable(let service):
                return service.debugDescription.localizedCaseInsensitiveContains("entitlement")
                    ? .unavailable(.notEnabledForBuild)
                    : .unavailable(.unavailable(service.debugDescription))
            @unknown default: return .other(error.localizedDescription)
            }
        }
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .contextTooLarge
            case .rateLimited(let limit): return .quotaLimitReached(resetDate: limit.resetDate)
            case .guardrailViolation, .refusal: return .guardrailViolation
            case .timeout: return .timedOut
            case .unsupportedCapability(let detail): return .other(detail.debugDescription)
            case .unsupportedTranscriptContent(let detail): return .other(detail.debugDescription)
            case .unsupportedGenerationGuide(let detail): return .malformedOutput(detail.debugDescription)
            case .unsupportedLanguageOrLocale(let detail): return .other(detail.debugDescription)
            @unknown default: return .other(error.localizedDescription)
            }
        }
        if let error = error as? SystemLanguageModel.Error {
            switch error {
            case .assetsUnavailable: return .unavailable(.notReady)
            @unknown default: return .other(error.localizedDescription)
            }
        }
        if let error = error as? GeneratedContent.ParsingError {
            return .malformedOutput(error.localizedDescription)
        }
        // `LanguageModelSession.GenerationError` is deprecated in OS 27 (the minimum
        // now), replaced by `LanguageModelError` above; it is no longer mapped.
        return .other(error.localizedDescription)
    }

    static func availability(_ availability: SystemLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .notEligible
        case .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady): .notReady
        case .unavailable(let reason): .unavailable(String(describing: reason))
        }
    }

    static func availability(_ availability: PrivateCloudComputeLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .notEligible
        case .unavailable(.systemNotReady): .notReady
        case .unavailable(let reason): .unavailable(String(describing: reason))
        }
    }

    static func quota(_ usage: PrivateCloudComputeLanguageModel.QuotaUsage) -> QuotaStatus {
        switch usage.status {
        case .belowLimit(let below): QuotaStatus(state: below.isApproachingLimit ? .nearingLimit : .belowLimit, resetDate: usage.resetDate)
        case .limitReached: QuotaStatus(state: .limitReached, resetDate: usage.resetDate)
        @unknown default: QuotaStatus(state: usage.isLimitReached ? .limitReached : .belowLimit, resetDate: usage.resetDate)
        }
    }

    /// The framework's usage as billed tokens (see `UsageNormalizer`). The Claude
    /// package always reports 0 reasoning tokens although thinking is part of
    /// the output, so for Claude reasoning is unknown (nil), not 0.
    static func tokens(_ usage: LanguageModelSession.Usage, provider: LLMProvider) -> TokenUsage {
        UsageNormalizer.billing(
            inputTotal: usage.input.totalTokenCount,
            cachedInput: usage.input.cachedTokenCount,
            output: usage.output.totalTokenCount,
            reasoning: provider == .anthropic ? nil : usage.output.reasoningTokenCount
        )
    }
}

/// Runs `work` with a deadline; past it the work is cancelled and `LLMError.timedOut` thrown.
func withDeadline<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw LLMError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw LLMError.timedOut }
        return first
    }
}

/// Milliseconds since `start`.
func elapsedMs(since start: ContinuousClock.Instant) -> Int {
    let elapsed = ContinuousClock.now - start
    return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
}
