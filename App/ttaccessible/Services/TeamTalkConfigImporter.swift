//
//  TeamTalkConfigImporter.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct TeamTalkImportResult {
    let sourceURL: URL
    let importedCount: Int
    let skippedCount: Int
    let importedServerNames: [String]
}

struct TeamTalkImportConflict {
    let existingRecord: SavedServerRecord
    let importedRecord: SavedServerRecord
}

enum TeamTalkImportDuplicatePolicy {
    case skipEndpointMatches
    case updateEndpointMatches
}

final class TeamTalkConfigImporter {
    enum ImportError: LocalizedError {
        case unsupportedFileType
        case unreadableConfig
        case noServersFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return L10n.text("teamTalkImport.error.unsupportedFileType")
            case .unreadableConfig:
                return L10n.text("teamTalkImport.error.unreadableConfig")
            case .noServersFound:
                return L10n.text("teamTalkImport.error.noServersFound")
            }
        }
    }

    private struct ImportedServer {
        let record: SavedServerRecord
        let password: String
        let channelPassword: String
    }

    private struct CandidateSource {
        let url: URL
        let priority: Int
    }

    private let fileManager: FileManager
    private let accessStore: TeamTalkConfigAccessStore
    private let ttFileService: TTFileService

    init(
        fileManager: FileManager = .default,
        accessStore: TeamTalkConfigAccessStore = TeamTalkConfigAccessStore(),
        ttFileService: TTFileService = TTFileService()
    ) {
        self.fileManager = fileManager
        self.accessStore = accessStore
        self.ttFileService = ttFileService
    }

    func defaultConfigURL() -> URL? {
        if let bookmarkedURL = accessStore.resolveURL() {
            return bookmarkedURL
        }

        return candidateSources()
            .filter { fileManager.fileExists(atPath: $0.url.path) }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.priority < rhs.priority
            }
            .first?
            .url
    }

    func defaultConfigDirectoryURL() -> URL {
        defaultConfigURL()?.deletingLastPathComponent()
        ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("BearWare.dk", isDirectory: true)
    }

    func rememberAccess(to url: URL) {
        try? accessStore.saveBookmark(for: url)
    }

    func importServers(
        from url: URL,
        into store: SavedServerStore,
        passwordStore: ServerPasswordStore,
        duplicatePolicy: TeamTalkImportDuplicatePolicy = .skipEndpointMatches
    ) throws -> TeamTalkImportResult {
        let importedServers = try loadServers(from: url)
        guard importedServers.isEmpty == false else {
            throw ImportError.noServersFound
        }

        var existingRecords = store.load()
        var importedCount = 0
        var skippedCount = 0
        var importedServerNames: [String] = []
        let shouldUpdateEndpointDuplicates = duplicatePolicy == .updateEndpointMatches

        for importedServer in importedServers {
            if let existingIndex = existingRecords.firstIndex(where: { $0.matchesImportIdentity(of: importedServer.record) }) {
                let existingID = existingRecords[existingIndex].id
                existingRecords[existingIndex] = importedServer.record.withID(existingID)
                try passwordStore.setPassword(importedServer.password, for: existingID)
                try passwordStore.setChannelPassword(importedServer.channelPassword, for: existingID)
                importedCount += 1
                importedServerNames.append(importedServer.record.name)
                continue
            }

            if let existingIndex = existingRecords.firstIndex(where: { $0.matchesEndpoint(of: importedServer.record) }) {
                guard shouldUpdateEndpointDuplicates else {
                    skippedCount += 1
                    continue
                }

                let existingID = existingRecords[existingIndex].id
                existingRecords[existingIndex] = importedServer.record.withID(existingID)
                try passwordStore.setPassword(importedServer.password, for: existingID)
                try passwordStore.setChannelPassword(importedServer.channelPassword, for: existingID)
                importedCount += 1
                importedServerNames.append(importedServer.record.name)
                continue
            }

            let newRecord = importedServer.record.withID(UUID())
            existingRecords.append(newRecord)
            try passwordStore.setPassword(importedServer.password, for: newRecord.id)
            try passwordStore.setChannelPassword(importedServer.channelPassword, for: newRecord.id)
            importedCount += 1
            importedServerNames.append(newRecord.name)
        }

        store.saveAll(existingRecords)
        return TeamTalkImportResult(
            sourceURL: url,
            importedCount: importedCount,
            skippedCount: skippedCount,
            importedServerNames: importedServerNames
        )
    }

    func firstExistingServerConflict(from url: URL, in store: SavedServerStore) throws -> TeamTalkImportConflict? {
        try existingServerConflicts(from: url, in: store).first
    }

    func existingServerConflicts(from url: URL, in store: SavedServerStore) throws -> [TeamTalkImportConflict] {
        let importedServers = try loadServers(from: url)
        let existingRecords = store.load()
        var conflicts: [TeamTalkImportConflict] = []
        for importedServer in importedServers {
            if let existingRecord = existingRecords.first(where: { existingRecord in
                existingRecord.matchesImportIdentity(of: importedServer.record)
                    || existingRecord.matchesEndpoint(of: importedServer.record)
            }) {
                conflicts.append(
                    TeamTalkImportConflict(
                        existingRecord: existingRecord,
                        importedRecord: importedServer.record
                    )
                )
            }
        }
        return conflicts
    }

    private func candidateSources() -> [CandidateSource] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            CandidateSource(
                url: home
                    .appendingPathComponent(".config", isDirectory: true)
                    .appendingPathComponent("BearWare.dk", isDirectory: true)
                    .appendingPathComponent("TeamTalk5.ini"),
                priority: 0
            ),
            CandidateSource(
                url: home
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Preferences", isDirectory: true)
                    .appendingPathComponent("BearWare.dk", isDirectory: true)
                    .appendingPathComponent("TeamTalk5.ini"),
                priority: 1
            ),
            CandidateSource(
                url: home
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Preferences", isDirectory: true)
                    .appendingPathComponent("dk.bearware.TeamTalk5.plist"),
                priority: 2
            )
        ]
    }

    private func loadServers(from url: URL) throws -> [ImportedServer] {
        switch url.pathExtension.lowercased() {
        case "ini":
            return try parseINI(at: url)
        case "plist":
            return try parsePlist(at: url)
        case "tt":
            return [importedServer(from: try ttFileService.load(from: url))]
        default:
            throw ImportError.unsupportedFileType
        }
    }

    private func importedServer(from payload: TTFilePayload) -> ImportedServer {
        let nickname = payload.auth.nickname.isEmpty
            ? payload.clientSetup?.nickname ?? ""
            : payload.auth.nickname
        let record = SavedServerRecord(
            id: UUID(),
            name: payload.name,
            host: payload.host,
            tcpPort: payload.tcpPort,
            udpPort: payload.udpPort,
            encrypted: payload.encrypted,
            nickname: nickname,
            username: payload.auth.username,
            initialChannelPath: payload.join?.channelPath ?? "",
            initialChannelPassword: payload.join?.password ?? ""
        )
        return ImportedServer(
            record: record,
            password: payload.auth.password,
            channelPassword: payload.join?.password ?? ""
        )
    }

    private func parseINI(at url: URL) throws -> [ImportedServer] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ImportError.unreadableConfig
        }

        var currentSection = ""
        var sections: [String: [String: String]] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            sections[currentSection, default: [:]][key] = value
        }

        let primary = importedServers(fromFlatKeys: sections["serverentries"] ?? [:])
        return primary.isEmpty ? importedServers(fromFlatKeys: sections["latesthosts"] ?? [:]) : primary
    }

    private func parsePlist(at url: URL) throws -> [ImportedServer] {
        guard let raw = NSDictionary(contentsOf: url) as? [String: Any] else {
            throw ImportError.unreadableConfig
        }

        let stringValues = raw.reduce(into: [String: String]()) { partialResult, entry in
            if let string = entry.value as? String {
                partialResult[entry.key] = string
            } else if let number = entry.value as? NSNumber {
                partialResult[entry.key] = number.stringValue
            }
        }

        let serverEntries = extractPrefixedKeys("serverentries/", from: stringValues)
        let primary = importedServers(fromFlatKeys: serverEntries)
        if primary.isEmpty == false {
            return primary
        }

        let latestHosts = extractPrefixedKeys("latesthosts/", from: stringValues)
        return importedServers(fromFlatKeys: latestHosts)
    }

    private func extractPrefixedKeys(_ prefix: String, from values: [String: String]) -> [String: String] {
        values.reduce(into: [String: String]()) { partialResult, entry in
            guard entry.key.hasPrefix(prefix) else {
                return
            }
            partialResult[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
    }

    private func importedServers(fromFlatKeys flatKeys: [String: String]) -> [ImportedServer] {
        let grouped = Dictionary(grouping: flatKeys) { entry -> Int? in
            guard let underscore = entry.key.firstIndex(of: "_"),
                  let index = Int(entry.key[..<underscore]) else {
                return nil
            }
            return index
        }

        return grouped
            .compactMap { index, entries -> (Int, ImportedServer)? in
                guard let index else {
                    return nil
                }

                let values = entries.reduce(into: [String: String]()) { partialResult, entry in
                    let components = entry.key.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
                    guard components.count == 2 else {
                        return
                    }
                    partialResult[String(components[1])] = entry.value
                }

                guard let host = values["hostaddr"], host.isEmpty == false else {
                    return nil
                }

                let name = values["name"].flatMap { $0.isEmpty ? nil : $0 } ?? host
                let tcpPort = Int(values["tcpport"] ?? "") ?? 10333
                let udpPort = Int(values["udpport"] ?? "") ?? tcpPort
                let encrypted = Self.parseBool(values["encrypted"])
                let nickname = values["nickname"] ?? ""
                let username = values["username"] ?? ""
                let password = values["password"] ?? ""

                let record = SavedServerRecord(
                    id: UUID(),
                    name: name,
                    host: host,
                    tcpPort: tcpPort,
                    udpPort: udpPort,
                    encrypted: encrypted,
                    nickname: nickname,
                    username: username,
                    initialChannelPath: values["channel"] ?? "",
                    initialChannelPassword: values["chanpassword"] ?? ""
                )

                let channelPassword = values["chanpassword"] ?? ""
                return (index, ImportedServer(record: record, password: password, channelPassword: channelPassword))
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    private static func parseBool(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}

extension SavedServerRecord {
    func withID(_ id: UUID) -> SavedServerRecord {
        SavedServerRecord(
            id: id,
            name: name,
            host: host,
            tcpPort: tcpPort,
            udpPort: udpPort,
            encrypted: encrypted,
            nickname: nickname,
            username: username,
            initialChannelPath: initialChannelPath,
            initialChannelPassword: initialChannelPassword
        )
    }

    func matchesImportIdentity(of other: SavedServerRecord) -> Bool {
        name == other.name &&
        host.caseInsensitiveCompare(other.host) == .orderedSame &&
        tcpPort == other.tcpPort &&
        udpPort == other.udpPort &&
        encrypted == other.encrypted &&
        nickname == other.nickname &&
        username == other.username &&
        initialChannelPath == other.initialChannelPath
    }

    func matchesEndpoint(of other: SavedServerRecord) -> Bool {
        host.caseInsensitiveCompare(other.host) == .orderedSame &&
        tcpPort == other.tcpPort &&
        udpPort == other.udpPort &&
        encrypted == other.encrypted &&
        username == other.username
    }
}
