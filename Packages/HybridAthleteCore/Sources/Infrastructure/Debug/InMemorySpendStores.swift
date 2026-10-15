#if DEBUG
import Foundation
import Application
import Domain

/// `-fakeLLM`: a usage ledger in memory, never the real database.
public actor InMemoryLLMUsageLedger: LLMUsageLedger {
    private var stored: [LLMCallRecord] = []
    private var nextId: Int64 = 1

    public init(records: [LLMCallRecord] = []) {
        stored = records.enumerated().map { $1.with(id: Int64($0 + 1)) }.sorted { $0.createdAt < $1.createdAt }
        nextId = Int64(records.count + 1)
    }

    public func record(_ record: LLMCallRecord) async {
        insert(record)
    }

    public func records(since date: Date?) async throws -> [LLMCallRecord] {
        guard let date else { return stored }
        return stored.filter { $0.createdAt >= date }
    }

    public func clear() async throws {
        stored = []
    }

    public func firstRecordDate() async throws -> Date? {
        stored.map(\.createdAt).min()
    }

    private func insert(_ record: LLMCallRecord) {
        stored.append(record.with(id: nextId))
        nextId += 1
        stored.sort { $0.createdAt < $1.createdAt }
    }
}

/// `-fakeLLM`: Lab settings in memory, starting from the defaults (no consent).
public actor InMemoryLabSettingsStore: LabSettingsStore {
    private var settings: LabSettings

    public init(_ settings: LabSettings = LabSettings()) {
        self.settings = settings
    }

    public func load() async -> LabSettings { settings }
    public func save(_ settings: LabSettings) async { self.settings = settings }
}

/// `-fakeLLM`: secrets in memory, never the Keychain. Starts empty.
public actor InMemorySecretStore: SecretStore {
    private var values: [SecretKey: String] = [:]

    public init() {}

    public func secret(for key: SecretKey) async throws -> String? { values[key] }
    public func hasSecret(_ key: SecretKey) async -> Bool { values[key] != nil }
    public func setSecret(_ value: String, for key: SecretKey) async throws { values[key] = value }
    public func removeSecret(for key: SecretKey) async throws { values[key] = nil }
}
#endif
