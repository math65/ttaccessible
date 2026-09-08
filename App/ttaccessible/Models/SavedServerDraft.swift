//
//  SavedServerDraft.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct SavedServerDraft: Equatable {
    var name: String
    var host: String
    var tcpPort: String
    var udpPort: String
    var encrypted: Bool
    var nickname: String
    var username: String
    var password: String
    var useWebLogin: Bool
    var initialChannelPath: String
    var initialChannelPassword: String
    var encryption: ServerEncryptionSettings
    /// Kept out of `encryption` because it is a secret: it round-trips through
    /// the keychain alongside the server password, not through UserDefaults.
    var clientPrivateKeyPEM: String

    init(
        name: String = "",
        host: String = "",
        tcpPort: String = "10333",
        udpPort: String = "10333",
        encrypted: Bool = false,
        nickname: String = AppPreferences.defaultNicknameFromAccount(),
        username: String = "",
        password: String = "",
        useWebLogin: Bool = false,
        initialChannelPath: String = "",
        initialChannelPassword: String = "",
        encryption: ServerEncryptionSettings = ServerEncryptionSettings(),
        clientPrivateKeyPEM: String = ""
    ) {
        self.name = name
        self.host = host
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.encrypted = encrypted
        self.nickname = nickname
        self.username = username
        self.password = password
        self.useWebLogin = useWebLogin
        self.initialChannelPath = initialChannelPath
        self.initialChannelPassword = initialChannelPassword
        self.encryption = encryption
        self.clientPrivateKeyPEM = clientPrivateKeyPEM
    }

    init(
        record: SavedServerRecord,
        password: String,
        initialChannelPassword: String? = nil,
        clientPrivateKeyPEM: String = ""
    ) {
        self.init(
            name: record.name,
            host: record.host,
            tcpPort: String(record.tcpPort),
            udpPort: String(record.udpPort),
            encrypted: record.encrypted,
            nickname: record.nickname,
            username: record.username,
            password: password,
            useWebLogin: record.useWebLogin,
            initialChannelPath: record.initialChannelPath,
            initialChannelPassword: initialChannelPassword ?? record.initialChannelPassword,
            encryption: record.encryption,
            clientPrivateKeyPEM: clientPrivateKeyPEM
        )
    }

    var isValid: Bool {
        sanitizedName.isEmpty == false &&
        sanitizedHost.isEmpty == false &&
        parsedTCPPort != nil &&
        parsedUDPPort != nil
    }

    var sanitizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedInitialChannelPath: String {
        initialChannelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var parsedTCPPort: Int? {
        Self.parsePort(tcpPort)
    }

    var parsedUDPPort: Int? {
        Self.parsePort(udpPort)
    }

    func makeRecord(id: UUID) -> SavedServerRecord? {
        guard let tcpPort = parsedTCPPort, let udpPort = parsedUDPPort else {
            return nil
        }

        return SavedServerRecord(
            id: id,
            name: sanitizedName,
            host: sanitizedHost,
            tcpPort: tcpPort,
            udpPort: udpPort,
            encrypted: encrypted,
            nickname: sanitizedNickname,
            username: useWebLogin ? BearWareWebLogin.username : sanitizedUsername,
            useWebLogin: useWebLogin,
            initialChannelPath: sanitizedInitialChannelPath,
            initialChannelPassword: initialChannelPassword,
            encryption: sanitizedEncryption
        )
    }

    /// Verification is meaningless on a plaintext connection, and the SDK cannot
    /// verify anything without a CA anyway. Normalising here keeps a stale
    /// "verify" flag from surviving an edit that turned encryption back off, and
    /// keeps the saved-server list's "secure" column honest.
    var sanitizedEncryption: ServerEncryptionSettings {
        guard encrypted else { return ServerEncryptionSettings() }
        var result = encryption
        if result.canVerify == false {
            result.verifyServerCertificate = false
        }
        return result
    }

    private static func parsePort(_ value: String) -> Int? {
        guard let port = Int(value), (1...65535).contains(port) else {
            return nil
        }
        return port
    }
}
