import Foundation

/// How hard the Private Cloud Compute model thinks before answering.
public enum ReasoningLevel: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case light, moderate, deep
}

/// Who runs a model: Apple (on-device or Private Cloud Compute, free) or Anthropic (paid per token).
public enum LLMProvider: String, Sendable, Equatable, Hashable, Codable {
    case apple, anthropic
}

/// The Claude models the Model Lab offers.
public enum AnthropicModel: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case haiku55, sonnet55, opus55, fable51

    /// The Anthropic API model id, as the Console and Prices.json name it.
    public var apiId: String {
        switch self {
        case .haiku55: "claude-haiku-5-5"
        case .sonnet55: "claude-sonnet-5-5"
        case .opus55: "claude-opus-5-5"
        case .fable51: "claude-fable-5-1"
        }
    }

    /// "Haiku 5.5", "Sonnet 5.5", "Opus 5.5", "Fable 5.1".
    public var displayName: String {
        switch self {
        case .haiku55: "Haiku 5.5"
        case .sonnet55: "Sonnet 5.5"
        case .opus55: "Opus 5.5"
        case .fable51: "Fable 5.1"
        }
    }

    public init?(apiId: String) {
        guard let match = Self.allCases.first(where: { $0.apiId == apiId }) else { return nil }
        self = match
    }
}

/// Which model runs a request: one of Apple's, or Claude.
public enum ModelChoice: Sendable, Equatable, Hashable, Codable {
    case onDevice
    case privateCloud(reasoning: ReasoningLevel)
    case anthropic(AnthropicModel)

    /// Apple's models, in the Lab's order.
    public static let apple: [ModelChoice] = [.onDevice] + ReasoningLevel.allCases.map { .privateCloud(reasoning: $0) }
    /// Claude models, in the Lab's order.
    public static let claude: [ModelChoice] = AnthropicModel.allCases.map { .anthropic($0) }
    /// Every choice the Model Lab offers, in order.
    public static let all: [ModelChoice] = apple + claude

    /// "onDevice", "pcc.light", "pcc.moderate", "pcc.deep", "anthropic.sonnet55".
    public var id: String {
        switch self {
        case .onDevice: "onDevice"
        case .privateCloud(let level): "pcc.\(level.rawValue)"
        case .anthropic(let model): "anthropic.\(model.rawValue)"
        }
    }

    public init?(id: String) {
        guard let match = Self.all.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    /// The plan's generatedBy tag: "on-device-v1", "pcc-moderate-v1", "claude-sonnet-5-5-v1".
    public var generatedBy: String {
        switch self {
        case .onDevice: "on-device-v1"
        case .privateCloud(let level): "pcc-\(level.rawValue)-v1"
        case .anthropic(let model): "\(model.apiId)-v1"
        }
    }

    /// "On-device", "PCC moderate", "Sonnet 5.5".
    public var displayName: String {
        switch self {
        case .onDevice: "On-device"
        case .privateCloud(let level): "PCC \(level.rawValue)"
        case .anthropic(let model): model.displayName
        }
    }

    public var provider: LLMProvider {
        if case .anthropic = self { return .anthropic }
        return .apple
    }

    public var isPrivateCloud: Bool {
        if case .privateCloud = self { return true }
        return false
    }

    /// The model id the usage ledger stores: the API id for Claude (as the Console
    /// shows it), the choice id for Apple.
    public var ledgerModelId: String {
        if case .anthropic(let model) = self { return model.apiId }
        return id
    }

    /// The display name for a ledger model id; the id itself when unknown.
    public static func displayName(ledgerModelId: String) -> String {
        all.first { $0.ledgerModelId == ledgerModelId }?.displayName ?? ledgerModelId
    }
}

/// Whether a model can run right now.
public enum ModelAvailability: Sendable, Equatable, Codable {
    case available
    /// The device cannot run Apple Intelligence.
    case notEligible
    /// Apple Intelligence is off or still downloading.
    case notReady
    /// This build lacks what the model needs (the Private Cloud Compute managed entitlement).
    case notEnabledForBuild
    /// A Claude model without a saved API key.
    case needsAPIKey
    case unavailable(String)

    public var isAvailable: Bool { self == .available }

    /// The readable sentence the Lab and the error UI show.
    public var message: String {
        switch self {
        case .available: "Available"
        case .notEligible: "This device can't run Apple Intelligence models."
        case .notReady: "Apple Intelligence isn't ready. Turn it on in Settings, or wait for the model to finish downloading."
        case .notEnabledForBuild:
            "Private Cloud Compute isn't enabled for this build. Request access at developer.apple.com/private-cloud-compute."
        case .needsAPIKey: "Add your Anthropic API key to run Claude models."
        case .unavailable(let reason): "The model is unavailable: \(reason)"
        }
    }

    /// The short chip text: "Available", "Not eligible", "Not ready", "Not enabled", "No key", "Unavailable".
    public var chipText: String {
        switch self {
        case .available: "Available"
        case .notEligible: "Not eligible"
        case .notReady: "Not ready"
        case .notEnabledForBuild: "Not enabled"
        case .needsAPIKey: "No key"
        case .unavailable: "Unavailable"
        }
    }
}

/// Tokens, time and (Claude only) the estimated cost of one model call. Unknown parts stay nil.
public struct LLMUsage: Sendable, Equatable, Codable {
    /// The whole prompt, cached parts included.
    public let inputTokens: Int?
    /// Cache reads.
    public let cachedInputTokens: Int?
    public let cacheWriteTokens: Int?
    public let outputTokens: Int?
    public let reasoningTokens: Int?
    public let latencyMs: Int
    /// Estimated from the price table, in micro-dollars; nil for Apple's models.
    public let costMicros: Int64?

    public init(
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        latencyMs: Int,
        costMicros: Int64? = nil
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.latencyMs = latencyMs
        self.costMicros = costMicros
    }

    /// The Lab's view of billed tokens.
    public init(_ usage: TokenUsage, latencyMs: Int, costMicros: Int64?) {
        self.init(
            inputTokens: usage.promptTokens,
            cachedInputTokens: usage.cacheRead,
            cacheWriteTokens: usage.cacheWrite,
            outputTokens: usage.output,
            reasoningTokens: usage.reasoning,
            latencyMs: latencyMs,
            costMicros: costMicros
        )
    }

    /// "cache read 800 · cache write 0", or nil when neither happened.
    public var cacheLine: String? {
        let read = cachedInputTokens ?? 0
        let write = cacheWriteTokens ?? 0
        guard read > 0 || write > 0 else { return nil }
        return "cache read \(read) · cache write \(write)"
    }

    /// "in 812 · out 140 · reasoning 96 · cached 0", omitting unknown parts.
    public var line: String {
        [
            inputTokens.map { "in \($0)" },
            outputTokens.map { "out \($0)" },
            reasoningTokens.map { "reasoning \($0)" },
            cachedInputTokens.map { "cached \($0)" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// "3.2 s".
    public var latencyText: String {
        String(format: "%.1f s", Double(latencyMs) / 1000)
    }
}

/// Why a model call failed.
public enum LLMError: Error, Sendable, Equatable {
    case unavailable(ModelAvailability)
    case quotaLimitReached(resetDate: Date?)
    case networkUnavailable
    case guardrailViolation
    case contextTooLarge
    case timedOut
    case cancelled
    case malformedOutput(String)
    case invalidPlan([String])
    /// Anthropic refused the key (401, or a key not allowed to use the API).
    case authenticationFailed
    /// Anthropic's 429 (or overloaded). The package does not pass Retry-After on, so it is usually nil.
    case rateLimited(retryAfter: TimeInterval?)
    /// The credit balance is too low, or another billing problem.
    case billingProblem
    /// Anthropic's 5xx.
    case providerUnavailable
    /// Blocked before sending: a spend cap, no consent, or no price table. The text is the sentence to show.
    case spendLimit(String)
    case other(String)

    /// Worth one more attempt with revision notes: the output broke a rule.
    public var isRetryable: Bool {
        switch self {
        case .malformedOutput, .invalidPlan: true
        default: false
        }
    }

    /// The case name the usage ledger stores ("authenticationFailed"); never any detail text.
    public var kind: String {
        switch self {
        case .unavailable: "unavailable"
        case .quotaLimitReached: "quotaLimitReached"
        case .networkUnavailable: "networkUnavailable"
        case .guardrailViolation: "guardrailViolation"
        case .contextTooLarge: "contextTooLarge"
        case .timedOut: "timedOut"
        case .cancelled: "cancelled"
        case .malformedOutput: "malformedOutput"
        case .invalidPlan: "invalidPlan"
        case .authenticationFailed: "authenticationFailed"
        case .rateLimited: "rateLimited"
        case .billingProblem: "billingProblem"
        case .providerUnavailable: "providerUnavailable"
        case .spendLimit: "spendLimit"
        case .other: "other"
        }
    }
}
