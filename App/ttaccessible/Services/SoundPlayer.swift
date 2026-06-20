//
//  SoundPlayer.swift
//  ttaccessible
//

import AppKit
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

    private var sounds: [NotificationSound: NSSound] = [:]
    // CoreAudio UID of the user's selected output device, so app notification
    // sounds play through the same device as TeamTalk audio instead of the
    // system default. nil = follow system default.
    private var outputDeviceUID: String?
    private let queue = DispatchQueue(label: "com.math65.ttaccessible.soundplayer")
    // Sound-effects level, in dB, split into the dedicated "sound effects" slider
    // (base) and the output (master) volume. Master scales the effects too. The
    // combined gain is clamped to a 0...1 linear NSSound volume. All three are
    // accessed only on `queue`.
    private var effectsGainDB: Double = 0
    private var masterGainDB: Double = 0
    private var effectsVolume: Float = 1
    var isEnabled = true
    var disabledSounds: Set<NotificationSound> = []
    private(set) var currentPack: String = defaultPack

    private init() {
        // Don't load sounds here — AppPreferencesStore will call loadPack() with the user's preferred pack.
    }

    /// Set the dedicated sound-effects base level (dB).
    func setEffectsGainDB(_ db: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.effectsGainDB = db
            self.recomputeEffectsVolume()
        }
    }

    /// Set the output (master) level (dB), which also scales the sound effects.
    func setMasterGainDB(_ db: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.masterGainDB = db
            self.recomputeEffectsVolume()
        }
    }

    /// Set both the sound-effects base level and the master level at once.
    func setGains(effectsDB: Double, masterDB: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.effectsGainDB = effectsDB
            self.masterGainDB = masterDB
            self.recomputeEffectsVolume()
        }
    }

    /// Recompute the linear NSSound volume (0...1) from the combined gain and
    /// apply it to the loaded sounds. Must run on `queue`.
    private func recomputeEffectsVolume() {
        let linear = pow(10.0, (effectsGainDB + masterGainDB) / 20.0)
        effectsVolume = Float(min(1.0, max(0.0, linear)))
        let vol = effectsVolume
        for nsSound in sounds.values {
            nsSound.volume = vol
        }
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
            let uid = self.outputDeviceUID
            self.sounds.removeAll()
            for (sound, url) in resolvedURLs {
                if let nsSound = NSSound(contentsOf: url, byReference: false) {
                    nsSound.playbackDeviceIdentifier = uid
                    nsSound.volume = self.effectsVolume
                    self.sounds[sound] = nsSound
                }
            }
        }
    }

    /// Route notification sounds to a specific output device (by CoreAudio UID).
    /// Pass the user's preferred output preference; nil/empty follows the system
    /// default. Resolves the TeamTalk/preference identity to a CoreAudio device.
    func updateOutputDevice(persistentID: String?, displayName: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            let uid: String?
            if let persistentID, persistentID.isEmpty == false {
                uid = InputAudioDeviceResolver.resolveOutputDevice(
                    persistentID: persistentID,
                    displayName: displayName
                )?.uid
            } else {
                uid = nil
            }
            self.outputDeviceUID = uid
            for nsSound in self.sounds.values {
                nsSound.playbackDeviceIdentifier = uid
            }
        }
    }

    func play(_ sound: NotificationSound) {
        guard isEnabled, !disabledSounds.contains(sound) else { return }
        queue.async { [weak self] in
            guard let self, let nsSound = self.sounds[sound] else { return }
            let uid = self.outputDeviceUID
            let vol = self.effectsVolume
            DispatchQueue.main.async {
                if nsSound.isPlaying {
                    nsSound.stop()
                }
                nsSound.playbackDeviceIdentifier = uid
                nsSound.volume = vol
                nsSound.play()
            }
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
        let packName = sanitizedPackName(sourceURL.lastPathComponent)
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
