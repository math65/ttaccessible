//
//  YtDlpUpdater.swift
//  ttaccessible
//
//  Keeps the yt-dlp that Stream URL uses current without anyone lifting a finger: yt-dlp follows
//  sites that change every week, while the copy inside the app only moves with app updates.
//
//  A minute after launch, at most once a day, and at once whenever a page won't resolve, it asks
//  GitHub for yt-dlp's latest release. When that is newer than the copy in use, it downloads the
//  release's `yt-dlp` file (a ~3 MB zip of Python code — data the embedded Python reads, never a
//  program anything launches), checks it against the release's own SHA2-256SUMS, keeps it in a
//  folder of its own, and switches the running Python to it (EmbeddedPython). If the new copy
//  won't import, the previous one stays loaded and the update is forgotten. Everything lives in
//  the app-wide Application Support folder, so every profile shares one copy.
//

import CryptoKit
import Foundation

actor YtDlpUpdater {

    static let shared = YtDlpUpdater()

    struct State: Codable, Equatable {
        var lastCheck: Date?
        /// The downloaded version to use in place of the bundled one.
        var activeVersion: String?
    }

    struct Release: Equatable, Sendable {
        let version: String
        let zipURL: URL
        let checksumsURL: URL
    }

    enum UpdateError: Error {
        case badResponse(Int)
        case missingAsset(String)
        case missingChecksum
        case checksumMismatch
        case noDirectory
    }

    nonisolated static let checkInterval: TimeInterval = 24 * 60 * 60

    // MARK: - Rules (pure, tested)

    /// yt-dlp versions are dates, sometimes with a hotfix number: 2026.08.19, 2026.08.19.1.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0 ..< max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The checksum SHA2-256SUMS gives for the file named exactly `name` ("<hex>  <name>" per
    /// line; a leading "*" marks binary mode).
    nonisolated static func checksum(for name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            var file = parts[1].trimmingCharacters(in: .whitespaces)
            if file.hasPrefix("*") { file.removeFirst() }
            if file == name { return String(parts[0]).lowercased() }
        }
        return nil
    }

    /// Once a day. A last check in the future means the clock moved back: check now.
    nonisolated static func isCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        return now < lastCheck || now.timeIntervalSince(lastCheck) >= interval
    }

    // MARK: - Where things live

    /// `…/Application Support/ttaccessible/yt-dlp/` — the same app-wide base as
    /// ProfileContext.applicationSupportBase (inside the container when sandboxed), worked out
    /// here because that one belongs to the main actor and this runs off it.
    nonisolated static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ttaccessible/yt-dlp", isDirectory: true)
    }

    nonisolated static func zipURL(version: String, in directory: URL? = directory) -> URL? {
        directory?.appendingPathComponent(version, isDirectory: true).appendingPathComponent("yt-dlp.zip")
    }

    nonisolated static func loadState() -> State {
        guard let file = directory?.appendingPathComponent("state.json"),
              let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    nonisolated static func saveState(_ state: State) {
        guard let directory, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }

    /// The downloaded yt-dlp to load instead of the bundled one: only when it is there and newer.
    nonisolated static func preferredZip() -> (version: String, url: URL)? {
        guard let version = loadState().activeVersion,
              let url = zipURL(version: version),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let bundled = EmbeddedPython.bundledYtDlpVersion, isNewer(version, than: bundled) == false {
            return nil
        }
        return (version, url)
    }

    /// Called when a downloaded copy fails to import: back to the bundled one.
    nonisolated static func forgetActiveVersion() {
        var state = loadState()
        state.activeVersion = nil
        saveState(state)
    }

    nonisolated static func currentVersion() -> String? {
        preferredZip()?.version ?? EmbeddedPython.bundledYtDlpVersion
    }

    // MARK: - Checking

    private var checking = false

    /// A minute after launch, off the main thread, never in the way of startup.
    nonisolated func scheduleLaunchCheck() {
        Task.detached(priority: .utility) {
            // Task.sleep(for:) is macOS 13+, and the app supports 12.
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            _ = await self.checkIfDue()
        }
    }

    func checkIfDue() async -> String? {
        guard Self.isCheckDue(lastCheck: Self.loadState().lastCheck, now: Date()) else { return nil }
        return await checkNow(reason: "daily check")
    }

    /// Checks GitHub now. Returns the new version when yt-dlp was updated, nil otherwise.
    func checkNow(reason: String) async -> String? {
        guard checking == false else { return nil }
        checking = true
        defer { checking = false }

        var state = Self.loadState()
        state.lastCheck = Date()
        Self.saveState(state)

        do {
            let release = try await Self.fetchLatestRelease()
            let current = Self.currentVersion() ?? "none"
            guard Self.isNewer(release.version, than: current) else {
                AudioLogger.log("yt-dlp updater (%@): %@ is current", reason, current)
                return nil
            }
            guard let directory = Self.directory else { throw UpdateError.noDirectory }
            let zip = try await Self.download(release, into: directory)
            let previousActive = Self.loadState().activeVersion
            state = Self.loadState()
            state.activeVersion = release.version
            Self.saveState(state)

            switch await EmbeddedPython.shared.switchYtDlp(to: zip) {
            case .failed(let message):
                // The shim already put the working copy back; forget this one.
                state = Self.loadState()
                state.activeVersion = previousActive
                Self.saveState(state)
                AudioLogger.log("yt-dlp updater (%@): %@ didn't load (%@) — staying on %@",
                                reason, release.version, message, current)
                return nil
            case .switched(let loaded):
                AudioLogger.log("yt-dlp updater (%@): %@ → %@, loaded", reason, current, loaded)
            case .notRunning:
                AudioLogger.log("yt-dlp updater (%@): %@ → %@, used from the next lookup", reason, current, release.version)
            }
            Self.pruneVersions(in: directory, keeping: [release.version, current])
            return release.version
        } catch {
            AudioLogger.log("yt-dlp updater (%@): %@", reason, String(describing: error))
            return nil
        }
    }

    // MARK: - Network

    nonisolated static func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ttaccessible", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }

        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let downloadURL: URL
                enum CodingKeys: String, CodingKey {
                    case name
                    case downloadURL = "browser_download_url"
                }
            }
            let tagName: String
            let assets: [Asset]
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case assets
            }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let zip = payload.assets.first(where: { $0.name == "yt-dlp" })?.downloadURL else {
            throw UpdateError.missingAsset("yt-dlp")
        }
        guard let sums = payload.assets.first(where: { $0.name == "SHA2-256SUMS" })?.downloadURL else {
            throw UpdateError.missingAsset("SHA2-256SUMS")
        }
        return Release(version: payload.tagName, zipURL: zip, checksumsURL: sums)
    }

    /// Downloads the release's yt-dlp into `<directory>/<version>/yt-dlp.zip`, refusing anything
    /// whose SHA-256 isn't the one the release publishes.
    nonisolated static func download(_ release: Release, into directory: URL) async throws -> URL {
        let sums = try await fetch(release.checksumsURL)
        guard let expected = checksum(for: "yt-dlp", in: String(decoding: sums, as: UTF8.self)) else {
            throw UpdateError.missingChecksum
        }
        let zipData = try await fetch(release.zipURL)
        let actual = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch }
        guard let destination = zipURL(version: release.version, in: directory) else { throw UpdateError.noDirectory }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try zipData.write(to: destination, options: .atomic)
        return destination
    }

    private nonisolated static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("ttaccessible", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }
        return data
    }

    /// Keeps the new version and the one before it; older folders go.
    private nonisolated static func pruneVersions(in directory: URL, keeping versions: [String]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if versions.contains(entry.lastPathComponent) == false {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
