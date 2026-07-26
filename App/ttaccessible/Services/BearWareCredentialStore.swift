//
//  BearWareCredentialStore.swift
//  ttaccessible
//
//  Stores the single bearware.dk web-login credential (username + nickname +
//  token) in the macOS keychain, one item per profile. Mirrors the keychain
//  approach of `ServerPasswordStore` but for a profile-wide identity rather than
//  a per-server password.
//

import Foundation
import Security

final class BearWareCredentialStore {
    private let serviceName: String
    private static let account = "bearware.weblogin"

    init(serviceName: String = ProfileContext.current.keychainServiceName) {
        self.serviceName = serviceName
    }

    /// Returns the stored credential, or nil when none is configured or the item
    /// is unreadable (e.g. broken ACL after a signing-cert change).
    func load() -> BearWareCredential? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let credential = try? JSONDecoder().decode(BearWareCredential.self, from: data) else {
            return nil
        }
        return credential
    }

    func save(_ credential: BearWareCredential) throws {
        let data = try JSONEncoder().encode(credential)

        // Replace any existing item: delete then add, falling back to update.
        // Tolerate auth/ACL failures on delete (a stale code signature can lock
        // the old item) so the add → update fallback still gets a chance.
        let deleteStatus = SecItemDelete(baseQuery() as CFDictionary)
        if deleteStatus != errSecSuccess,
           deleteStatus != errSecItemNotFound,
           !Self.isAuthBlocked(deleteStatus) {
            throw StoreError.unexpectedStatus(deleteStatus)
        }

        var attributes = baseQuery()
        attributes[kSecValueData] = data

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Delete was rejected by the ACL — update the value in place.
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                if Self.isAuthBlocked(updateStatus) {
                    throw StoreError.accessBlocked(updateStatus)
                }
                throw StoreError.unexpectedStatus(updateStatus)
            }
        default:
            if Self.isAuthBlocked(addStatus) {
                throw StoreError.accessBlocked(addStatus)
            }
            throw StoreError.unexpectedStatus(addStatus)
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: Self.account
        ]
    }

    /// OSStatus codes indicating the Keychain ACL/auth state is blocking the
    /// operation (typically a code-signature change between the binary that
    /// created the item and the one accessing it) rather than a real failure.
    private static func isAuthBlocked(_ status: OSStatus) -> Bool {
        switch status {
        case errSecAuthFailed,
             errSecInteractionNotAllowed,
             errSecInteractionRequired,
             errSecNotAvailable,
             errSecUserCanceled,
             errSecMissingEntitlement:
            return true
        default:
            return false
        }
    }

    enum StoreError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case accessBlocked(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return L10n.format("keychain.error.unexpectedStatus", status)
            case .accessBlocked:
                return L10n.text("keychain.error.accessBlocked")
            }
        }
    }
}
