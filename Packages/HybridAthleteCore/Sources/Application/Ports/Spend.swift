import Foundation
import Domain

/// Takes one ledger record per model call. Best effort: it never throws into
/// the caller, so a failed write never fails a model call.
public protocol LLMCallRecorder: Sendable {
    func record(_ record: LLMCallRecord) async
}

/// The stored usage ledger (token counts and costs, never prompts or outputs).
public protocol LLMUsageLedger: LLMCallRecorder {
    /// Records created at or after `date`, oldest first; every record when nil.
    func records(since date: Date?) async throws -> [LLMCallRecord]
    func clear() async throws
    func firstRecordDate() async throws -> Date?
}

/// The bundled price table; nil when it is missing or malformed (Claude runs are then blocked).
public protocol PriceTableProvider: Sendable {
    func priceTable() -> PriceTable?
}

/// The Lab's non-secret settings. Never holds the API key.
public struct LabSettings: Sendable, Equatable {
    /// "Send summaries to Anthropic?" was answered with Allow.
    public var consentGiven: Bool
    public var caps: SpendCaps
    public var scenario: CostScenario

    public init(consentGiven: Bool = false, caps: SpendCaps = .defaults, scenario: CostScenario = .defaults) {
        self.consentGiven = consentGiven
        self.caps = caps
        self.scenario = scenario
    }
}

public protocol LabSettingsStore: Sendable {
    func load() async -> LabSettings
    func save(_ settings: LabSettings) async
}

/// The name of one secret in the store.
public struct SecretKey: Sendable, Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The user's own Anthropic API key.
    public static let anthropicAPIKey = SecretKey(rawValue: "anthropic.apiKey")
}

/// Secrets live only here (the Keychain in the app). Never in source, Info.plist,
/// logs, analytics or any copied JSON.
public protocol SecretStore: Sendable {
    func secret(for key: SecretKey) async throws -> String?
    func hasSecret(_ key: SecretKey) async -> Bool
    func setSecret(_ value: String, for key: SecretKey) async throws
    func removeSecret(for key: SecretKey) async throws
}

/// The answer to a key test: how long it took and what it cost.
public struct KeyTestResult: Sendable, Equatable {
    public let latencyMs: Int
    public let costMicros: Int64?

    public init(latencyMs: Int, costMicros: Int64?) {
        self.latencyMs = latencyMs
        self.costMicros = costMicros
    }
}

/// Sends the tiny key-test request ("Reply with OK.", 8 output tokens at most) to
/// Claude with the saved key and records it (purpose keyTest). Throws `LLMError`.
public protocol AnthropicKeyTesting: Sendable {
    func testKey() async throws -> KeyTestResult
}
