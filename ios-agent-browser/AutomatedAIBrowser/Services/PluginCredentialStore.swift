import Foundation
import Security

/// Keychain-only storage for optional plugin credentials. There is deliberately no
/// UserDefaults or file fallback for a token that can spend money or reach a paid
/// service: if Keychain is unavailable, the plugin stays unconfigured.
struct PluginCredentialStore {
    enum Account: String {
        case browserAct = "browseract.api-key.v1"
        case crawl4AIServer = "crawl4ai.server-token.v1"
        case crawl4AICloud = "crawl4ai.cloud-token.v1"
    }

    let service: String

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.rork.agentbrowser") {
        service = "\(bundleID).plugins"
    }

    func read(_ account: Account) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw PluginCredentialError.keychain(status)
        }
    }

    func save(_ value: String, for account: Account) throws {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            try remove(account)
            return
        }
        guard clean.utf8.count <= 4_096,
              clean.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw PluginCredentialError.malformed }
        guard let data = clean.data(using: .utf8) else {
            throw PluginCredentialError.encoding
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let update = SecItemUpdate(
            query as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ] as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw PluginCredentialError.keychain(update) }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw PluginCredentialError.keychain(status) }
    }

    func remove(_ account: Account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PluginCredentialError.keychain(status)
        }
    }
}

enum PluginCredentialError: LocalizedError {
    case encoding
    case malformed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encoding:
            "The API key could not be encoded."
        case .malformed:
            "The API key contains unsupported characters or is too long."
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            return "The API key could not be stored securely: \(detail)"
        }
    }
}
