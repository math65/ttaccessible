//
//  ServerPasswordStore.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation
import Security

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

    private let combinedServiceName: String
    private let legacyServerServiceName: String
    private let legacyChannelServiceName: String
    private var cache: [UUID: Credentials] = [:]
    private let cacheLock = NSLock()

    /// Set to false once we discover at runtime that the data protection keychain
    /// is unavailable (missing entitlement). All subsequent operations fall back
    /// to the legacy file-based keychain for the rest of the session. As soon as
    /// the app ships with a real developer cert + `keychain-access-groups`
    /// entitlement, this stays true and items get migrated transparently.
    private var dataProtectionKeychainAvailable = true
    private let availabilityLock = NSLock()

    /// UserDefaults key holding the UUIDs whose legacy two-item migration has
    /// already been attempted. Once an id is in this list we never query the
    /// `legacyServerServiceName` / `legacyChannelServiceName` keychain items
    /// again, even if the underlying delete silently failed (which happens
    /// when the items were created under a different code signing ACL — common
    /// in development). Without this guard the user gets two keychain prompts
    /// every single launch.
    private static let migratedLegacyIDsKey = "ServerPasswordStore.migratedLegacyIDs"
    private static let migrationSchemaVersionKey = "ServerPasswordStore.migrationSchemaVersion"
    private static let currentMigrationSchemaVersion = 2
    private let defaults: UserDefaults

    init(
        serviceName: String = "com.math65.ttaccessible.saved-server-password",
        defaults: UserDefaults = .standard
    ) {
        self.combinedServiceName = serviceName + ".combined"
        self.legacyServerServiceName = serviceName
        self.legacyChannelServiceName = serviceName + ".channel"
        self.defaults = defaults
        resetMigrationMarkerIfSchemaChanged()
    }

    private func resetMigrationMarkerIfSchemaChanged() {
        let storedVersion = defaults.integer(forKey: Self.migrationSchemaVersionKey)
        guard storedVersion < Self.currentMigrationSchemaVersion else { return }
        defaults.removeObject(forKey: Self.migratedLegacyIDsKey)
        defaults.set(Self.currentMigrationSchemaVersion, forKey: Self.migrationSchemaVersionKey)
    }

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

    private func loadCredentials(for id: UUID) throws -> Credentials {
        cacheLock.lock()
        if let cached = cache[id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Modern path: data protection keychain (no user prompts ever for the
        // owning app). Only active when the build has the required entitlements
        // — see `isDataProtectionKeychainAvailable`. Silently falls back when
        // unavailable.
        if isDataProtectionKeychainAvailable {
            if let data = try fetchData(service: combinedServiceName, account: id.uuidString, dataProtection: true) {
                guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
                    throw PasswordStoreError.invalidPasswordData
                }
                cacheCredentials(credentials, for: id)
                return credentials
            }
        }

        // Legacy file-based "login" keychain — combined item first (beta 11+).
        if let data = try fetchData(service: combinedServiceName, account: id.uuidString, dataProtection: false) {
            guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
                throw PasswordStoreError.invalidPasswordData
            }
            // Promote to data protection keychain if available, then drop the legacy copy.
            if isDataProtectionKeychainAvailable {
                try writeCredentials(credentials, for: id)
                try? deleteRawItem(service: combinedServiceName, account: id.uuidString, dataProtection: false)
            } else {
                cacheCredentials(credentials, for: id)
            }
            return credentials
        }

        // Older legacy two-item format (pre-beta 11). We only ever attempt to
        // read these once per id — see `migratedLegacyIDsKey` — because the
        // delete that follows can silently fail under a stale code-signing ACL,
        // and we don't want to prompt the user twice on every launch forever.
        if hasMigratedLegacyItems(for: id) {
            cacheCredentials(Credentials(), for: id)
            return Credentials()
        }

        let legacyServer = try fetchString(service: legacyServerServiceName, account: id.uuidString)
        let legacyChannel = try fetchString(service: legacyChannelServiceName, account: id.uuidString)
        let migrated = Credentials(server: nonEmpty(legacyServer), channel: nonEmpty(legacyChannel))

        if !migrated.isEmpty {
            try writeCredentials(migrated, for: id)
            try? deleteRawItem(service: legacyServerServiceName, account: id.uuidString, dataProtection: false)
            try? deleteRawItem(service: legacyChannelServiceName, account: id.uuidString, dataProtection: false)
        } else {
            cacheCredentials(migrated, for: id)
        }
        markLegacyItemsMigrated(for: id)

        return migrated
    }

    private func hasMigratedLegacyItems(for id: UUID) -> Bool {
        let ids = defaults.stringArray(forKey: Self.migratedLegacyIDsKey) ?? []
        return ids.contains(id.uuidString)
    }

    private func markLegacyItemsMigrated(for id: UUID) {
        var ids = defaults.stringArray(forKey: Self.migratedLegacyIDsKey) ?? []
        let uuidString = id.uuidString
        guard !ids.contains(uuidString) else { return }
        ids.append(uuidString)
        defaults.set(ids, forKey: Self.migratedLegacyIDsKey)
    }

    private func writeCredentials(_ credentials: Credentials, for id: UUID) throws {
        let useDataProtection = isDataProtectionKeychainAvailable
        try deleteRawItem(service: combinedServiceName, account: id.uuidString, dataProtection: useDataProtection)

        guard !credentials.isEmpty else {
            cacheCredentials(credentials, for: id)
            return
        }

        let data = try JSONEncoder().encode(credentials)
        var attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: combinedServiceName,
            kSecAttrAccount: id.uuidString,
            kSecValueData: data
        ]
        if useDataProtection {
            // These attributes only exist for the data protection keychain.
            // Passing them to the legacy file-based login keychain causes
            // SecItemAdd to fail with errSecParam.
            attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            attributes[kSecAttrSynchronizable] = false
            attributes[kSecUseDataProtectionKeychain] = true
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if useDataProtection, status == errSecMissingEntitlement {
            // Cert/entitlement not in place yet. Disable DPK for the session and
            // retry on the legacy keychain so the user can keep using the app.
            markDataProtectionUnavailable()
            try writeCredentials(credentials, for: id)
            return
        }
        guard status == errSecSuccess else {
            throw PasswordStoreError.unexpectedStatus(status)
        }

        cacheCredentials(credentials, for: id)
    }

    private func fetchData(service: String, account: String, dataProtection: Bool) throws -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain] = true
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        case errSecMissingEntitlement where dataProtection:
            markDataProtectionUnavailable()
            return nil
        default:
            throw PasswordStoreError.unexpectedStatus(status)
        }
    }

    private func fetchString(service: String, account: String) throws -> String? {
        guard let data = try fetchData(service: service, account: account, dataProtection: false) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw PasswordStoreError.invalidPasswordData
        }
        return string
    }

    private func deleteRawItem(service: String, account: String, dataProtection: Bool) throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain] = true
        }

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecMissingEntitlement where dataProtection:
            markDataProtectionUnavailable()
            return
        default:
            throw PasswordStoreError.unexpectedStatus(status)
        }
    }

    private var isDataProtectionKeychainAvailable: Bool {
        availabilityLock.lock()
        defer { availabilityLock.unlock() }
        return dataProtectionKeychainAvailable
    }

    private func markDataProtectionUnavailable() {
        availabilityLock.lock()
        dataProtectionKeychainAvailable = false
        availabilityLock.unlock()
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
