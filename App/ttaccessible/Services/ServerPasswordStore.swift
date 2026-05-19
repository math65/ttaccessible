//
//  ServerPasswordStore.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation
import Security

/// Stores per-server credentials (server password + channel password) in the
/// macOS login keychain. For end users running the notarized release build,
/// the signing identity stays stable so items persist across launches. For
/// developers re-signing locally, the ACL may break on cert changes — in that
/// case `SavedServersViewController.handleLoginFailure` lets the user re-enter
/// the credentials, which simply rewrites the item with the new ACL.
final class ServerPasswordStore {
    private struct Credentials: Codable {
        var server: String?
        var channel: String?

        var isEmpty: Bool {
            (server?.isEmpty ?? true) && (channel?.isEmpty ?? true)
        }
    }

    enum PasswordStoreError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidPasswordData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return L10n.format("keychain.error.unexpectedStatus", status)
            case .invalidPasswordData:
                return L10n.text("keychain.error.invalidPasswordData")
            }
        }
    }

    private let serviceName: String
    private let defaults: UserDefaults
    private var cache: [UUID: Credentials] = [:]
    private let cacheLock = NSLock()

    private static let cleanupDoneKey = "ServerPasswordStore.dpkResetCompleted.v3"

    init(
        serviceName: String = "com.math65.ttaccessible.saved-server-password",
        defaults: UserDefaults = .standard
    ) {
        self.serviceName = serviceName
        self.defaults = defaults
        oneShotMigrationCleanup()
    }

    /// Clears markers from older keychain implementations so the app starts clean
    /// on the first launch after the DPK migration. Older login-keychain items
    /// (if any) become inaccessible after a signing-cert change anyway, so they
    /// don't need active deletion — they'll be flushed by macOS over time.
    private func oneShotMigrationCleanup() {
        guard !defaults.bool(forKey: Self.cleanupDoneKey) else { return }
        defaults.removeObject(forKey: "ServerPasswordStore.migratedLegacyIDs")
        defaults.removeObject(forKey: "ServerPasswordStore.migrationSchemaVersion")
        defaults.set(true, forKey: Self.cleanupDoneKey)
    }

    // MARK: - Public API

    func password(for id: UUID) throws -> String? {
        nonEmpty(try loadCredentials(for: id).server)
    }

    func channelPassword(for id: UUID) throws -> String? {
        nonEmpty(try loadCredentials(for: id).channel)
    }

    func setPassword(_ password: String?, for id: UUID) throws {
        var credentials = try loadCredentials(for: id)
        credentials.server = nonEmpty(password)
        try writeCredentials(credentials, for: id)
    }

    func setChannelPassword(_ password: String?, for id: UUID) throws {
        var credentials = try loadCredentials(for: id)
        credentials.channel = nonEmpty(password)
        try writeCredentials(credentials, for: id)
    }

    func deletePassword(for id: UUID) throws {
        var credentials = try loadCredentials(for: id)
        credentials.server = nil
        try writeCredentials(credentials, for: id)
    }

    func deleteChannelPassword(for id: UUID) throws {
        var credentials = try loadCredentials(for: id)
        credentials.channel = nil
        try writeCredentials(credentials, for: id)
    }

    // MARK: - Internals

    private func loadCredentials(for id: UUID) throws -> Credentials {
        cacheLock.lock()
        if let cached = cache[id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var query = baseQuery(for: id)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
                throw PasswordStoreError.invalidPasswordData
            }
            cacheCredentials(credentials, for: id)
            return credentials
        case errSecItemNotFound:
            let empty = Credentials()
            cacheCredentials(empty, for: id)
            return empty
        default:
            throw PasswordStoreError.unexpectedStatus(status)
        }
    }

    private func writeCredentials(_ credentials: Credentials, for id: UUID) throws {
        let deleteStatus = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw PasswordStoreError.unexpectedStatus(deleteStatus)
        }

        guard !credentials.isEmpty else {
            cacheCredentials(credentials, for: id)
            return
        }

        let data = try JSONEncoder().encode(credentials)
        var attributes = baseQuery(for: id)
        attributes[kSecValueData] = data

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PasswordStoreError.unexpectedStatus(addStatus)
        }
        cacheCredentials(credentials, for: id)
    }

    private func baseQuery(for id: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: id.uuidString
        ]
    }

    private func cacheCredentials(_ credentials: Credentials, for id: UUID) {
        cacheLock.lock()
        cache[id] = credentials
        cacheLock.unlock()
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else {
            return nil
        }
        return string
    }
}
