// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

protocol NexusCredentialStoring: Sendable {
    func apiKey() -> String?
    func setAPIKey(_ value: String?) throws
}

extension NexusCredentialStoring {
    /// Migration is an app-startup operation, never a service-construction side effect.
    func migrateLegacyValueIfNeeded(defaults: UserDefaults = .standard) {
        let legacyKey = "nexusAPIKey"
        guard let legacyValue = defaults.string(forKey: legacyKey),
              !legacyValue.isEmpty else { return }
        if apiKey() != nil || (try? setAPIKey(legacyValue)) != nil {
            defaults.removeObject(forKey: legacyKey)
        }
    }
}

struct NexusCredentialStore: NexusCredentialStoring {
    enum CredentialError: Error, LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                return SecCopyErrorMessageString(status, nil) as String?
                    ?? "Keychain error \(status)"
            }
        }
    }

    private let service = "com.shailaric.BG3MacModManager.nexus"
    private let account = "api-key"

    func apiKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func setAPIKey(_ value: String?) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialError.keychain(addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
