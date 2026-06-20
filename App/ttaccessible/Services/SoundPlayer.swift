//
//  SoundPlayer.swift
//  ttaccessible
//

import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio
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
        let deletedBuiltInPacks = Set(ProfileContext.current.userDefaults.stringArray(forKey: deletedBuiltInPacksKey) ?? [])
        let bundled = builtInPacks.filter { !deletedBuiltInPacks.contains($0) }
        let custom = customPackDirectories().map(\.lastPathComponent)
        return Set(bundled + custom).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static var customSoundPacksDirectory: URL {
        ProfileContext.current.customSoundPacksDirectory
    }

    // App notification sounds play through an AVAudioEngine (rather than NSSound)
    // so the sound-effects + master gain can AMPLIFY a sound past its authored
    // level — NSSound.volume hard-caps at 1.0, so it can never make a sound louder
    // than the file itself. Each sound gets a preloaded buffer + its own player
    // node (so different sounds overlap and replaying one restarts it, matching the
    // old behavior). Gain up to +12 dB is applied via node volume (≤ unity) or by
    // scaling the sample buffer (boost, clamped to avoid runaway clipping). The
    // engine output is pinned to the user's selected device and only runs while
    // sounds are actually playing (stopped after a short idle), so it never holds
    // the output device open the way a perpetually-running engine would.
    private let engine = AVAudioEngine()
    private var players: [NotificationSound: AVAudioPlayerNode] = [:]
    private var buffers: [NotificationSound: AVAudioPCMBuffer] = [:]
    private var graphReady = false
    // Resolved CoreAudio device the engine output is pinned to. nil = follow the
    // current system default output (re-resolved each time the engine starts).
    private var outputDeviceID: AudioDeviceID?
    private var appliedDeviceID: AudioDeviceID?
    private var idleStop: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.math65.ttaccessible.soundplayer")
    // Maximum amplification above a sound's authored level: +12 dB ≈ 3.98×.
    private static let maxBoostLinear: Float = 3.981_071_7
    // Sound-effects level, in dB, split into the dedicated "sound effects" slider
    // (base) and the output (master) volume. Master scales the effects too. The
    // combined gain is clamped to [0, maxBoostLinear]. All accessed only on `queue`.
    private var effectsGainDB: Double = 0
    private var masterGainDB: Double = 0
    private var effectsGainLinear: Float = 1
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
            self.recomputeEffectsGain()
        }
    }

    /// Set the output (master) level (dB), which also scales the sound effects.
    func setMasterGainDB(_ db: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.masterGainDB = db
            self.recomputeEffectsGain()
        }
    }

    /// Set both the sound-effects base level and the master level at once.
    func setGains(effectsDB: Double, masterDB: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.effectsGainDB = effectsDB
            self.masterGainDB = masterDB
            self.recomputeEffectsGain()
        }
    }

    /// Recompute the combined linear gain (clamped to allow up to +12 dB of boost).
    /// Must run on `queue`.
    private func recomputeEffectsGain() {
        let linear = Float(pow(10.0, (effectsGainDB + masterGainDB) / 20.0))
        effectsGainLinear = min(Self.maxBoostLinear, max(0, linear))
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
            var newBuffers: [NotificationSound: AVAudioPCMBuffer] = [:]
            for (sound, url) in resolvedURLs {
                if let buffer = Self.loadBuffer(url: url) {
                    newBuffers[sound] = buffer
                }
            }
            self.buffers = newBuffers
            self.rebuildGraphLocked()
        }
    }

    /// Route notification sounds to a specific output device (by CoreAudio UID).
    /// Pass the user's preferred output preference; nil/empty follows the system
    /// default. Resolves the TeamTalk/preference identity to a CoreAudio device.
    func updateOutputDevice(persistentID: String?, displayName: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            var deviceID: AudioDeviceID?
            if let persistentID, persistentID.isEmpty == false,
               let info = InputAudioDeviceResolver.resolveOutputDevice(
                   persistentID: persistentID,
                   displayName: displayName
               ) {
                deviceID = info.deviceID
            }
            self.outputDeviceID = deviceID
            // Re-pin the device. The CurrentDevice property can only be changed
            // while the engine is stopped, so if it's running, bounce it.
            if self.engine.isRunning {
                self.engine.stop()
                self.appliedDeviceID = nil
                self.startEngineLocked()
            } else {
                self.appliedDeviceID = nil
            }
        }
    }

    func play(_ sound: NotificationSound) {
        guard isEnabled, !disabledSounds.contains(sound) else { return }
        queue.async { [weak self] in
            guard let self,
                  let node = self.players[sound],
                  let buffer = self.buffers[sound] else { return }
            self.startEngineLocked()
            guard self.engine.isRunning else { return }

            let gain = self.effectsGainLinear
            let bufferToPlay: AVAudioPCMBuffer
            if gain > 1.0 {
                // Boost beyond unity by scaling the samples (node volume caps at 1).
                bufferToPlay = Self.scaledBuffer(buffer, gain: gain) ?? buffer
                node.volume = 1.0
            } else {
                bufferToPlay = buffer
                node.volume = gain
            }

            // Restart this sound if it's already playing (matches NSSound).
            node.stop()
            node.scheduleBuffer(bufferToPlay, at: nil, options: [.interrupts], completionHandler: nil)
            node.play()
            self.scheduleIdleStop()
        }
    }

    // MARK: - Engine plumbing (all on `queue`)

    private static func loadBuffer(url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        return buffer
    }

    /// Amplified copy of a buffer (float samples × gain, hard-clamped to ±1).
    private static func scaledBuffer(_ source: AVAudioPCMBuffer, gain: Float) -> AVAudioPCMBuffer? {
        guard let sourceData = source.floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameCapacity),
              let destData = copy.floatChannelData else { return nil }
        copy.frameLength = source.frameLength
        let channels = Int(source.format.channelCount)
        let frames = Int(source.frameLength)
        for channel in 0..<channels {
            let src = sourceData[channel]
            let dst = destData[channel]
            for index in 0..<frames {
                let value = src[index] * gain
                dst[index] = value > 1.0 ? 1.0 : (value < -1.0 ? -1.0 : value)
            }
        }
        return copy
    }

    /// Rebuild the engine graph for the currently-loaded buffers.
    private func rebuildGraphLocked() {
        let wasRunning = engine.isRunning
        engine.stop()
        for node in players.values {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        players.removeAll()
        for (sound, buffer) in buffers {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            players[sound] = node
        }
        graphReady = true
        appliedDeviceID = nil
        if wasRunning {
            startEngineLocked()
        }
    }

    /// Pin the engine output to the resolved device and start it if needed.
    private func startEngineLocked() {
        guard graphReady, !players.isEmpty else { return }
        applyDeviceLocked()
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("SoundPlayer: AVAudioEngine start failed: \(error.localizedDescription)")
        }
    }

    /// Set the output node's CurrentDevice. Engine must be stopped before calling.
    private func applyDeviceLocked() {
        let target = outputDeviceID
            ?? InputAudioDeviceResolver.defaultOutputDeviceUID()
                .flatMap { InputAudioDeviceResolver.audioDeviceID(forUID: $0) }
        guard let target, target != appliedDeviceID,
              let outputUnit = engine.outputNode.audioUnit else { return }
        var deviceID = target
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            appliedDeviceID = target
        }
    }

    /// Stop the engine ~5 s after the last sound so we don't hold the device open.
    private func scheduleIdleStop() {
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.players.values.contains(where: { $0.isPlaying }) {
                self.scheduleIdleStop()   // something is still playing; check again later
            } else {
                self.engine.stop()
                self.appliedDeviceID = nil
            }
        }
        idleStop = work
        queue.asyncAfter(deadline: .now() + 5.0, execute: work)
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
            let defaults = ProfileContext.current.userDefaults
            var deletedBuiltInPacks = Set(defaults.stringArray(forKey: deletedBuiltInPacksKey) ?? [])
            deletedBuiltInPacks.insert(packName)
            defaults.set(Array(deletedBuiltInPacks), forKey: deletedBuiltInPacksKey)
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
