// Why: ADR-0007 (BYOK) says the DeepSeek key on device lives only in the Keychain — never in
// UserDefaults, never in a file, never in code. This is the whole Keychain surface the app uses:
// one generic-password item per service, with every OSStatus surfaced instead of swallowed.

import Foundation
import Security

public enum KeychainError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case notUTF8
}

public struct APIKeyStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String = "deepseek-api-key") {
        self.service = service
        self.account = account
    }

    /// The app's default store. Test code uses a throwaway service name so it never touches this item.
    public static let liveSlice = APIKeyStore(service: "com.jiajiali.liveslice")

    /// Saves or replaces the key. Whitespace is trimmed; an empty key is rejected as a programming error upstream.
    public func save(_ key: String) throws {
        let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let status = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery()
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// The stored key, or `nil` when no item exists. Callers decide what a missing key means.
    public func load() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw KeychainError.notUTF8 }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the item. Deleting a missing item is not an error.
    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
