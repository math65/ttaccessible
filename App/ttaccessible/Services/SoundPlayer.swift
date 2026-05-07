//
//  SoundPlayer.swift
//  ttaccessible
//

import AVFoundation
import Foundation

enum NotificationSound: String, CaseIterable, Codable {
    case newUser = "newuser"
    case removeUser = "removeuser"
    case userMessage = "user_msg"
    case userMessageSent = "user_msg_sent"
    case channelMessage = "channel_msg"
    case channelMessageSent = "channel_msg_sent"
    case serverLost = "serverlost"
    case loggedOn = "logged_on"
    case loggedOff = "logged_off"
    case broadcastMessage = "broadcast_msg"
    case fileUpdate = "fileupdate"
    case fileTxComplete = "filetx_complete"
    case questionMode = "questionmode"
    case hotkey = "hotkey"
    case voiceActOn = "voiceact_on"
    case voiceActOff = "voiceact_off"
    case muteAll = "mute_all"
    case unmuteAll = "unmute_all"
    case intercept = "intercept"
    case interceptEnd = "interceptEnd"
    case txQueueStart = "txqueue_start"
    case txQueueStop = "txqueue_stop"
    case voxEnable = "vox_enable"
    case voxDisable = "vox_disable"
    case voxMeEnable = "vox_me_enable"
    case voxMeDisable = "vox_me_disable"

    var localizationKey: String {
        "sound.event.\(rawValue)"
    }

    var soundPackFileName: String {
        "\(rawValue).wav"
    }
}

final class SoundPlayer {
    static let shared = SoundPlayer()
    static let defaultPack = "Default"
    private static let deletedBuiltInPacksKey = "soundPlayer.deletedBuiltInPacks"

    static var availablePacks: [String] {
        let deletedBuiltInPacks = Set(UserDefaults.standard.stringArray(forKey: deletedBuiltInPacksKey) ?? [])
        let bundled = builtInPacks.filter { !deletedBuiltInPacks.contains($0) }
        let custom = customPackDirectories().map(\.lastPathComponent)
        return Set(bundled + custom).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static var customSoundPacksDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Sound Packs", isDirectory: true)
    }

    private var players: [NotificationSound: AVAudioPlayer] = [:]
    private let queue = DispatchQueue(label: "com.math65.ttaccessible.soundplayer")
    var isEnabled = true
    var disabledSounds: Set<NotificationSound> = []
    private(set) var currentPack: String = defaultPack

    private init() {
        // Don't load sounds here — AppPreferencesStore will call loadPack() with the user's preferred pack.
    }

    func loadPack(_ packName: String) {
        let resolvedPackName = Self.availablePacks.contains(packName)
            ? packName
            : (Self.availablePacks.first ?? Self.defaultPack)
        let resolvedURLs = NotificationSound.allCases.compactMap { sound -> (NotificationSound, URL)? in
            guard let url = soundURL(for: sound, pack: resolvedPackName) else { return nil }
            return (sound, url)
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.currentPack = resolvedPackName
            self.players.removeAll()
            for (sound, url) in resolvedURLs {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    self.players[sound] = player
                }
            }
        }
    }

    func play(_ sound: NotificationSound) {
        guard isEnabled, !disabledSounds.contains(sound) else { return }
        queue.async { [weak self] in
            guard let player = self?.players[sound] else { return }
            if player.isPlaying {
                player.stop()
            }
            player.currentTime = 0
            player.prepareToPlay()
            player.play()
        }
    }

    @discardableResult
    static func ensureCustomSoundPacksDirectory() -> URL {
        let directory = customSoundPacksDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func importCustomPack(from sourceURL: URL) throws -> String {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationRoot = ensureCustomSoundPacksDirectory()
        let packName = sourceURL.lastPathComponent
        let destinationURL = destinationRoot.appendingPathComponent(packName, isDirectory: true)
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            return packName
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return packName
    }

    static func isCustomPack(_ packName: String) -> Bool {
        FileManager.default.fileExists(atPath: customPackDirectory(named: packName).path)
            && !builtInPacks.contains(packName)
    }

    static func canDeletePack(_ packName: String) -> Bool {
        availablePacks.count > 1 && availablePacks.contains(packName)
    }

    static func createCustomPack(named rawName: String) throws -> String {
        let packName = sanitizedPackName(rawName)
        let destinationURL = customPackDirectory(named: packName)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        return packName
    }

    static func deletePack(named packName: String) throws {
        guard canDeletePack(packName) else { return }

        if isCustomPack(packName) {
            try FileManager.default.removeItem(at: customPackDirectory(named: packName))
        } else if builtInPacks.contains(packName) {
            var deletedBuiltInPacks = Set(UserDefaults.standard.stringArray(forKey: deletedBuiltInPacksKey) ?? [])
            deletedBuiltInPacks.insert(packName)
            UserDefaults.standard.set(Array(deletedBuiltInPacks), forKey: deletedBuiltInPacksKey)
        }
    }

    static func customPackDirectory(named packName: String) -> URL {
        customSoundPacksDirectory.appendingPathComponent(sanitizedPackName(packName), isDirectory: true)
    }

    static func setCustomSound(_ sound: NotificationSound, in packName: String, from sourceURL: URL) throws {
        let packDirectory = try existingCustomPackDirectory(named: packName)
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = packDirectory.appendingPathComponent(sound.soundPackFileName)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    static func removeCustomSound(_ sound: NotificationSound, from packName: String) throws {
        let packDirectory = try existingCustomPackDirectory(named: packName)
        let url = packDirectory.appendingPathComponent(sound.soundPackFileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func hasCustomSound(_ sound: NotificationSound, in packName: String) -> Bool {
        FileManager.default.fileExists(
            atPath: customPackDirectory(named: packName).appendingPathComponent(sound.soundPackFileName).path
        )
    }

    private static let packPrefixes: [String: String] = [
        "Majorly-G": "majorlyg_",
        "Old": "old_",
    ]
    private static var builtInPacks: [String] {
        [defaultPack] + Array(packPrefixes.keys)
    }

    private static func customPackDirectories() -> [URL] {
        let directory = customSoundPacksDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !builtInPacks.contains(url.lastPathComponent)
        }
    }

    private static func existingCustomPackDirectory(named packName: String) throws -> URL {
        let directory = customPackDirectory(named: packName)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory
    }

    private static func sanitizedPackName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = trimmed.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Custom Pack" : cleaned
    }

    private func soundURL(for sound: NotificationSound, pack: String) -> URL? {
        if pack != SoundPlayer.defaultPack {
            let customURL = Self.customPackDirectory(named: pack).appendingPathComponent(sound.soundPackFileName)
            if FileManager.default.fileExists(atPath: customURL.path) {
                return customURL
            }
        }

        // Try the selected pack first (prefixed files).
        if pack != SoundPlayer.defaultPack,
           let prefix = Self.packPrefixes[pack],
           let url = Bundle.main.url(forResource: "\(prefix)\(sound.rawValue)", withExtension: "wav") {
            return url
        }
        // Fall back to Default (unprefixed).
        guard Self.availablePacks.contains(Self.defaultPack) || pack == Self.defaultPack else {
            return nil
        }
        return Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")
    }
}
