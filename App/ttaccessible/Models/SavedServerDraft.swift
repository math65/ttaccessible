//
//  SavedServerDraft.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
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
    var initialChannelPath: String
    var initialChannelPassword: String

    init(
        name: String = "",
        host: String = "",
        tcpPort: String = "10333",
        udpPort: String = "10333",
        encrypted: Bool = false,
        nickname: String = "TTAccessible",
        username: String = "",
        password: String = "",
        initialChannelPath: String = "",
        initialChannelPassword: String = ""
    ) {
        self.name = name
        self.host = host
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.encrypted = encrypted
        self.nickname = nickname
        self.username = username
        self.password = password
        self.initialChannelPath = initialChannelPath
        self.initialChannelPassword = initialChannelPassword
    }

    init(record: SavedServerRecord, password: String, initialChannelPassword: String? = nil) {
        self.init(
            name: record.name,
            host: record.host,
            tcpPort: String(record.tcpPort),
            udpPort: String(record.udpPort),
            encrypted: record.encrypted,
            nickname: record.nickname,
            username: record.username,
            password: password,
            initialChannelPath: record.initialChannelPath,
            initialChannelPassword: initialChannelPassword ?? record.initialChannelPassword
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
            username: sanitizedUsername,
            initialChannelPath: sanitizedInitialChannelPath,
            initialChannelPassword: initialChannelPassword
        )
    }

    private static func parsePort(_ value: String) -> Int? {
        guard let port = Int(value), (1...65535).contains(port) else {
            return nil
        }
        return port
    }
}
