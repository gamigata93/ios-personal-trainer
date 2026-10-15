import Foundation
import Security

/// Deletes the Keychain items an earlier build stored under its own service
/// name, so nothing stale stays on the device after that feature was removed.
/// Deleting is idempotent: once the items are gone, later runs find nothing.
///
/// TODO: remove this type and its call in the composition root in a later release.
public enum LegacyKeychainCleanup {
    private static let service = "HybridAthlete.auth"

    public static func run() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        // errSecItemNotFound just means there was nothing left to remove.
        _ = SecItemDelete(query as CFDictionary)
    }
}
