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
    /// Bumped whenever a field is added to `Credentials`. Persisted so a record
    /// last written by an OLDER build is recognizable: that build re-encodes the
    /// whole blob without knowing about newer fields, silently dropping them
    /// (the per-channel map, today). The loss is self-healing — the next
    /// successful join re-persists — but it should be visible in the log rather
    /// than a mystery.
    private static let currentSchemaVersion = 2

    private struct Credentials: Codable {
        var server: String?
        var channel: String?
        /// Passwords for individual password-protected channels, keyed by the
        /// channel's full SDK path. Persisted so a channel joined once doesn't
        /// prompt again after quitting or leaving/rejoining the server.
        /// Optional + decodeIfPresent keeps old keychain items readable.
        var channels: [String: String]?
        var schemaVersion: Int?

        var isEmpty: Bool {
            (server?.isEmpty ?? true)
                && (channel?.isEmpty ?? true)
                && (channels?.isEmpty ?? true)
        }
    }

    enum PasswordStoreError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidPasswordData
        case accessBlocked(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return L10n.format("keychain.error.unexpectedStatus", status)
            case .invalidPasswordData:
                return L10n.text("keychain.error.invalidPasswordData")
            case .accessBlocked:
                return L10n.text("keychain.error.accessBlocked")
            }
        }
    }

    /// OSStatus codes indicating the Keychain ACL/auth state is blocking the
    /// operation (rather than a real "wrong password" / I/O failure). The most
    /// common trigger is a code-signature change between the binary that
    /// originally created the item and the one trying to read/update it.
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

    private let serviceName: String
    private let defaults: UserDefaults
    private var cache: [UUID: Credentials] = [:]
    private let cacheLock = NSLock()

    private static let cleanupDoneKey = "ServerPasswordStore.dpkResetCompleted.v3"

    init(
        serviceName: String = ProfileContext.current.keychainServiceName,
        defaults: UserDefaults = ProfileContext.current.userDefaults
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
        var credentials = loadCredentialsForUpdate(for: id)
        credentials.server = nonEmpty(password)
        try writeCredentials(credentials, for: id)
    }

    func setChannelPassword(_ password: String?, for id: UUID) throws {
        var credentials = loadCredentialsForUpdate(for: id)
        credentials.channel = nonEmpty(password)
        try writeCredentials(credentials, for: id)
    }

    func deletePassword(for id: UUID) throws {
        var credentials = loadCredentialsForUpdate(for: id)
        credentials.server = nil
        try writeCredentials(credentials, for: id)
    }

    func deleteChannelPassword(for id: UUID) throws {
        var credentials = loadCredentialsForUpdate(for: id)
        credentials.channel = nil
        // Also drop every per-channel password so removing a server leaves no
        // orphaned channel secrets in the keychain.
        credentials.channels = nil
        try writeCredentials(credentials, for: id)
    }

    /// Per-channel password persistence, keyed by the channel's full SDK path
    /// (`TT_GetChannelPath`). Resolved through the connection controller, which
    /// is the single accessor every join path goes through — see
    /// `TeamTalkConnectionController.knownChannelPasswordLocked`.

    func channelPassword(for id: UUID, channelPath: String) throws -> String? {
        nonEmpty(try loadCredentials(for: id).channels?[channelPath])
    }

    /// Every per-channel password for a server, for bulk copies (profile
    /// duplication). Empty when there are none or the item is unreadable.
    func allChannelPasswords(for id: UUID) throws -> [String: String] {
        try loadCredentials(for: id).channels ?? [:]
    }

    func setChannelPasswords(_ map: [String: String], for id: UUID) throws {
        var credentials = loadCredentialsForUpdate(for: id)
        credentials.channels = map.isEmpty ? nil : map
        try writeCredentials(credentials, for: id)
    }

    /// Drops every per-channel password without touching the server password.
    /// Used when a saved server is repointed at a different host, where the old
    /// host's channel secrets must not follow.
    func clearChannelPasswords(for id: UUID) throws {
        var credentials = loadCredentialsForUpdate(for: id)
        guard credentials.channels != nil else { return }
        credentials.channels = nil
        try writeCredentials(credentials, for: id)
    }

    func setChannelPassword(_ password: String?, for id: UUID, channelPath: String) throws {
        var credentials = loadCredentialsForUpdate(for: id)
        var map = credentials.channels ?? [:]
        if let password = nonEmpty(password) {
            map[channelPath] = password
        } else {
            map.removeValue(forKey: channelPath)
        }
        credentials.channels = map.isEmpty ? nil : map
        try writeCredentials(credentials, for: id)
    }

    /// Best-effort read for write operations: if the existing item is unreadable
    /// (broken ACL after a code-signature change, corrupted JSON, …), fall back
    /// to a blank record. The pending write will then overwrite the stale item
    /// instead of failing the whole flow before it gets the chance.
    private func loadCredentialsForUpdate(for id: UUID) -> Credentials {
        (try? loadCredentials(for: id)) ?? Credentials()
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
            if (credentials.schemaVersion ?? 1) < Self.currentSchemaVersion {
                AudioLogger.log(
                    "Keychain: credentials for %@ were last written by an older build (schema %d < %d) — newer fields may have been dropped",
                    id.uuidString, credentials.schemaVersion ?? 1, Self.currentSchemaVersion
                )
            }
            cacheCredentials(credentials, for: id)
            return credentials
        case errSecItemNotFound:
            let empty = Credentials()
            cacheCredentials(empty, for: id)
            return empty
        default:
            if Self.isAuthBlocked(status) {
                throw PasswordStoreError.accessBlocked(status)
            }
            throw PasswordStoreError.unexpectedStatus(status)
        }
    }

    private func writeCredentials(_ input: Credentials, for id: UUID) throws {
        var credentials = input
        credentials.schemaVersion = Self.currentSchemaVersion

        // Tolerate auth/ACL failures on delete: if the existing item is locked
        // behind a stale ACL we still want a shot at overwriting it via the
        // SecItemAdd → SecItemUpdate fallback below. Real failures resurface
        // through the add/update path.
        let deleteStatus = SecItemDelete(baseQuery(for: id) as CFDictionary)
        if deleteStatus != errSecSuccess,
           deleteStatus != errSecItemNotFound,
           !Self.isAuthBlocked(deleteStatus) {
            throw PasswordStoreError.unexpectedStatus(deleteStatus)
        }

        guard !credentials.isEmpty else {
            cacheCredentials(credentials, for: id)
            return
        }

        let data = try JSONEncoder().encode(credentials)
        var attributes = baseQuery(for: id)
        attributes[kSecValueData] = data
        // Per-device VoIP credentials have no business travelling in a keychain
        // migration to another Mac. Set only on ADD — kSecAttrAccessible in the
        // lookup query would stop matching items written before this.
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            cacheCredentials(credentials, for: id)
        case errSecDuplicateItem:
            // Delete was rejected by the ACL — the old item is still there.
            // Try to update its value in place, which works when the item's
            // ACL grants the current binary update access.
            let updateStatus = SecItemUpdate(
                baseQuery(for: id) as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                if Self.isAuthBlocked(updateStatus) {
                    throw PasswordStoreError.accessBlocked(updateStatus)
                }
                throw PasswordStoreError.unexpectedStatus(updateStatus)
            }
            cacheCredentials(credentials, for: id)
        default:
            if Self.isAuthBlocked(addStatus) {
                throw PasswordStoreError.accessBlocked(addStatus)
            }
            throw PasswordStoreError.unexpectedStatus(addStatus)
        }
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
