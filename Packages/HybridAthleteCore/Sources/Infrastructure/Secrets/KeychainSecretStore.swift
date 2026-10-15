import Foundation
import Security
import Application

/// Secrets in the Keychain (generic passwords, this device only, readable while
/// unlocked). Values are never logged; errors carry the OSStatus only.
public struct KeychainSecretStore: SecretStore {
    public struct Failure: Error, Sendable, Equatable {
        public let status: OSStatus
    }

    /// Distinct from the service `LegacyKeychainCleanup` deletes.
    public static let defaultService = "HybridAthlete.secrets"

    private let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    public func secret(for key: SecretKey) async throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func hasSecret(_ key: SecretKey) async -> Bool {
        var query = baseQuery(key)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func setSecret(_ value: String, for key: SecretKey) async throws {
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure(status: status) }
        var add = baseQuery(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
    }

    public func removeSecret(for key: SecretKey) async throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
