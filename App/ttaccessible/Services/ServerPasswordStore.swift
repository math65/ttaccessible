//
//  ServerPasswordStore.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation
import Security

final class ServerPasswordStore {
    private enum PasswordKind: String {
        case server
        case channel
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
    private let channelServiceName: String
    private var cachedPasswords: [UUID: String] = [:]
    private var cachedChannelPasswords: [UUID: String] = [:]

    init(serviceName: String = "com.math65.ttaccessible.saved-server-password") {
        self.serviceName = serviceName
        self.channelServiceName = serviceName + ".channel"
    }

    func password(for id: UUID) throws -> String? {
        try storedPassword(for: id, kind: .server)
    }

    func channelPassword(for id: UUID) throws -> String? {
        try storedPassword(for: id, kind: .channel)
    }

    func setPassword(_ password: String?, for id: UUID) throws {
        try setStoredPassword(password, for: id, kind: .server)
    }

    func setChannelPassword(_ password: String?, for id: UUID) throws {
        try setStoredPassword(password, for: id, kind: .channel)
    }

    func deletePassword(for id: UUID) throws {
        try deleteStoredPassword(for: id, kind: .server)
    }

    func deleteChannelPassword(for id: UUID) throws {
        try deleteStoredPassword(for: id, kind: .channel)
    }

    private func storedPassword(for id: UUID, kind: PasswordKind) throws -> String? {
        if let cached = cachedPassword(for: id, kind: kind) {
            return cached
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName(for: kind),
            kSecAttrAccount: id.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw PasswordStoreError.invalidPasswordData
            }
            cache(password: password, for: id, kind: kind)
            return password
        case errSecItemNotFound:
            clearCache(for: id, kind: kind)
            return nil
        default:
            throw PasswordStoreError.unexpectedStatus(status)
        }
    }

    private func setStoredPassword(_ password: String?, for id: UUID, kind: PasswordKind) throws {
        try deleteStoredPassword(for: id, kind: kind)

        guard let password, password.isEmpty == false else {
            clearCache(for: id, kind: kind)
            return
        }

        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName(for: kind),
            kSecAttrAccount: id.uuidString,
            kSecValueData: Data(password.utf8)
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PasswordStoreError.unexpectedStatus(status)
        }
        cache(password: password, for: id, kind: kind)
    }

    private func deleteStoredPassword(for id: UUID, kind: PasswordKind) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName(for: kind),
            kSecAttrAccount: id.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordStoreError.unexpectedStatus(status)
        }
        clearCache(for: id, kind: kind)
    }

    private func serviceName(for kind: PasswordKind) -> String {
        switch kind {
        case .server:
            return serviceName
        case .channel:
            return channelServiceName
        }
    }

    private func cachedPassword(for id: UUID, kind: PasswordKind) -> String? {
        switch kind {
        case .server:
            return cachedPasswords[id]
        case .channel:
            return cachedChannelPasswords[id]
        }
    }

    private func cache(password: String, for id: UUID, kind: PasswordKind) {
        switch kind {
        case .server:
            cachedPasswords[id] = password
        case .channel:
            cachedChannelPasswords[id] = password
        }
    }

    private func clearCache(for id: UUID, kind: PasswordKind) {
        switch kind {
        case .server:
            cachedPasswords.removeValue(forKey: id)
        case .channel:
            cachedChannelPasswords.removeValue(forKey: id)
        }
    }
}
