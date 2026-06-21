//
//  TTFileService.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 18/03/2026.
//

import Foundation

struct TTFilePayload {
    struct Auth: Equatable {
        var username: String
        var password: String
        var nickname: String
        var statusMessage: String
    }

    struct Join: Equatable {
        var channelPath: String
        var password: String
        var joinLastChannel: Bool
    }

    struct ClientSetup: Equatable {
        var nickname: String
        var gender: TeamTalkGender?
        var voiceActivated: Bool?
        var unsupportedFields: [String]

        var hasSupportedSettings: Bool {
            nickname.isEmpty == false || gender != nil || voiceActivated != nil
        }

        var hasAnySettings: Bool {
            hasSupportedSettings || unsupportedFields.isEmpty == false
        }
    }

    var fileURL: URL
    var version: String
    var name: String
    var host: String
    var tcpPort: Int
    var udpPort: Int
    var encrypted: Bool
    var auth: Auth
    var join: Join?
    var clientSetup: ClientSetup?
}

final class TTFileService {
    enum TTFileError: LocalizedError {
        case unreadableFile
        case invalidFormat
        case incompatibleVersion
        case missingHostInformation

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return L10n.text("ttFile.error.unreadable")
            case .invalidFormat:
                return L10n.text("ttFile.error.invalid")
            case .incompatibleVersion:
                return L10n.text("ttFile.error.incompatible")
            case .missingHostInformation:
                return L10n.text("ttFile.error.missingHost")
            }
        }
    }

    private let supportedVersion = "5.0"

    /// Loads the first server defined in a .tt file. Used when opening a file to connect directly.
    func load(from url: URL) throws -> TTFilePayload {
        guard let payload = try loadAll(from: url).first else {
            throw TTFileError.missingHostInformation
        }
        return payload
    }

    /// Loads every `<host>` entry defined in a .tt file. A single file can hold multiple servers
    /// (the Qt TeamTalk client exports them as sibling `<host>` elements under `<teamtalk>`).
    func loadAll(from url: URL) throws -> [TTFilePayload] {
        guard let data = try? Data(contentsOf: url) else {
            throw TTFileError.unreadableFile
        }

        let document = try xmlDocument(from: data)
        guard let root = document.rootElement(), root.name == "teamtalk" else {
            throw TTFileError.invalidFormat
        }

        let version = root.attribute(forName: "version")?.stringValue ?? supportedVersion
        guard versionSameOrLater(version, than: supportedVersion) else {
            throw TTFileError.incompatibleVersion
        }

        let hostElements = root.elements(forName: "host")
        guard hostElements.isEmpty == false else {
            throw TTFileError.missingHostInformation
        }

        let payloads = hostElements.compactMap { payload(from: $0, fileURL: url, version: version) }
        guard payloads.isEmpty == false else {
            throw TTFileError.missingHostInformation
        }

        return payloads
    }

    private func payload(from hostElement: XMLElement, fileURL: URL, version: String) -> TTFilePayload? {
        let name = value(in: hostElement, named: "name")
        let host = value(in: hostElement, named: "address")
        let tcpPort = Int(value(in: hostElement, named: "tcpport")) ?? 10333
        let udpPort = Int(value(in: hostElement, named: "udpport")) ?? tcpPort

        guard name.isEmpty == false, host.isEmpty == false else {
            return nil
        }

        let encrypted = Self.parseBool(value(in: hostElement, named: "encrypted"))
        let auth = parseAuth(from: hostElement)
        let join = parseJoin(from: hostElement)
        let clientSetup = parseClientSetup(from: hostElement)

        return TTFilePayload(
            fileURL: fileURL,
            version: version,
            name: name,
            host: host,
            tcpPort: tcpPort,
            udpPort: udpPort,
            encrypted: encrypted,
            auth: auth,
            join: join,
            clientSetup: clientSetup
        )
    }

    func generateFileContents(
        record: SavedServerRecord,
        password: String,
        defaultJoinChannelPath: String? = nil,
        defaultJoinPassword: String = "",
        defaultStatusMessage: String = "",
        defaultGender: TeamTalkGender? = nil
    ) -> Data? {
        let host = makeHostElement(
            record: record,
            password: password,
            defaultJoinChannelPath: defaultJoinChannelPath,
            defaultJoinPassword: defaultJoinPassword,
            defaultStatusMessage: defaultStatusMessage,
            defaultGender: defaultGender
        )
        return serialize(hosts: [host])
    }

    /// Generate a single .tt file holding every server (one `<host>` per server,
    /// the format the Qt client uses and that `loadAll` reads back).
    func generateAllServersFileContents(
        records: [(record: SavedServerRecord, password: String, channelPassword: String)],
        defaultStatusMessage: String = "",
        defaultGender: TeamTalkGender? = nil
    ) -> Data? {
        let hosts = records.map { entry in
            makeHostElement(
                record: entry.record,
                password: entry.password,
                defaultJoinChannelPath: entry.record.initialChannelPath.isEmpty ? nil : entry.record.initialChannelPath,
                defaultJoinPassword: entry.channelPassword,
                defaultStatusMessage: defaultStatusMessage,
                defaultGender: defaultGender
            )
        }
        return serialize(hosts: hosts)
    }

    private func makeHostElement(
        record: SavedServerRecord,
        password: String,
        defaultJoinChannelPath: String?,
        defaultJoinPassword: String,
        defaultStatusMessage: String,
        defaultGender: TeamTalkGender?
    ) -> XMLElement {
        let host = XMLElement(name: "host")
        appendChild(named: "name", value: record.name, to: host)
        appendChild(named: "address", value: record.host, to: host)
        appendChild(named: "tcpport", value: String(record.tcpPort), to: host)
        appendChild(named: "udpport", value: String(record.udpPort), to: host)
        appendChild(named: "encrypted", value: record.encrypted ? "true" : "false", to: host)

        if record.username.isEmpty == false || password.isEmpty == false || record.nickname.isEmpty == false || defaultStatusMessage.isEmpty == false {
            let auth = XMLElement(name: "auth")
            appendChild(named: "username", value: record.username, to: auth)
            appendChild(named: "password", value: password, to: auth)
            appendChild(named: "nickname", value: record.nickname, to: auth)
            appendChild(named: "statusmsg", value: defaultStatusMessage, to: auth)
            host.addChild(auth)
        }

        if let defaultJoinChannelPath, defaultJoinChannelPath.isEmpty == false {
            let join = XMLElement(name: "join")
            appendChild(named: "channel", value: defaultJoinChannelPath, to: join)
            appendChild(named: "password", value: defaultJoinPassword, to: join)
            appendChild(named: "join-last-channel", value: "false", to: join)
            host.addChild(join)
        }

        if record.nickname.isEmpty == false || defaultGender != nil {
            let client = XMLElement(name: "clientsetup")
            appendChild(named: "nickname", value: record.nickname, to: client)
            if let defaultGender {
                appendChild(named: "gender", value: String(defaultGender.rawValue), to: client)
            }
            host.addChild(client)
        }

        return host
    }

    private func serialize(hosts: [XMLElement]) -> Data? {
        let root = XMLElement(name: "teamtalk")
        if let versionAttr = XMLNode.attribute(withName: "version", stringValue: supportedVersion) as? XMLNode {
            root.addAttribute(versionAttr)
        }
        hosts.forEach { root.addChild($0) }

        let document = XMLDocument(rootElement: root)
        document.characterEncoding = "UTF-8"
        document.version = "1.0"
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private func xmlDocument(from data: Data) throws -> XMLDocument {
        do {
            return try XMLDocument(data: data, options: [.nodePreserveAll])
        } catch {
            throw TTFileError.invalidFormat
        }
    }

    private func parseAuth(from hostElement: XMLElement) -> TTFilePayload.Auth {
        guard let auth = hostElement.elements(forName: "auth").first else {
            return TTFilePayload.Auth(username: "", password: "", nickname: "", statusMessage: "")
        }

        return TTFilePayload.Auth(
            username: value(in: auth, named: "username"),
            password: value(in: auth, named: "password"),
            nickname: value(in: auth, named: "nickname"),
            statusMessage: value(in: auth, named: "statusmsg")
        )
    }

    private func parseJoin(from hostElement: XMLElement) -> TTFilePayload.Join? {
        guard let join = hostElement.elements(forName: "join").first else {
            return nil
        }

        let channelPath = value(in: join, named: "channel")
        let password = value(in: join, named: "password")
        let joinLastChannel = Self.parseBool(value(in: join, named: "join-last-channel"))
        guard channelPath.isEmpty == false || joinLastChannel else {
            return nil
        }

        return TTFilePayload.Join(channelPath: channelPath, password: password, joinLastChannel: joinLastChannel)
    }

    private func parseClientSetup(from hostElement: XMLElement) -> TTFilePayload.ClientSetup? {
        guard let client = hostElement.elements(forName: "clientsetup").first else {
            return nil
        }

        var unsupported: [String] = []
        if client.elements(forName: "mac-hotkey").isEmpty == false {
            unsupported.append("mac-hotkey")
        }
        if client.elements(forName: "videoformat").isEmpty == false {
            unsupported.append("videoformat")
        }
        if client.elements(forName: "videocodec").isEmpty == false {
            unsupported.append("videocodec")
        }

        let nickname = value(in: client, named: "nickname")
        let gender = Int(value(in: client, named: "gender")).flatMap { $0 > 0 ? TeamTalkGender(ttFileValue: $0) : nil }
        let voiceActivatedRaw = value(in: client, named: "voice-activated")
        let voiceActivated: Bool?
        if voiceActivatedRaw.isEmpty {
            voiceActivated = nil
        } else {
            voiceActivated = (Int(voiceActivatedRaw) ?? 0) > 0
        }

        let setup = TTFilePayload.ClientSetup(
            nickname: nickname,
            gender: gender,
            voiceActivated: voiceActivated,
            unsupportedFields: unsupported
        )
        return setup.hasAnySettings ? setup : nil
    }

    private func value(in element: XMLElement, named childName: String) -> String {
        element.childText(named: childName)
    }

    private func appendChild(named name: String, value: String, to parent: XMLElement) {
        let child = XMLElement(name: name, stringValue: value)
        parent.addChild(child)
    }

    private func versionSameOrLater(_ candidate: String, than baseline: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = baseline.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return true
    }

    private static func parseBool(_ value: String) -> Bool {
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}
