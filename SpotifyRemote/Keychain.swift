import Foundation
import Security

enum Keychain {
    private static let service = "SpotifyRemote"

    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        // Keep the refresh token on this device only, and out of backups.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Save failed with status \(status)")
        }
        return status == errSecSuccess
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            // errSecItemNotFound is expected before the first login.
            if status != errSecItemNotFound {
                print("[Keychain] Read failed with status \(status)")
            }
            return nil
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[Keychain] Delete failed with status \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
