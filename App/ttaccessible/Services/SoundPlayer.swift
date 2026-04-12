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
}

final class SoundPlayer {
    static let shared = SoundPlayer()
    static let defaultPack = "Default"

    static let availablePacks: [String] = [defaultPack] + packPrefixes.keys.sorted()

    private var players: [NotificationSound: AVAudioPlayer] = [:]
    private let queue = DispatchQueue(label: "com.math65.ttaccessible.soundplayer")
    var isEnabled = true
    var disabledSounds: Set<NotificationSound> = []
    private(set) var currentPack: String = defaultPack

    private init() {
        // Don't load sounds here — AppPreferencesStore will call loadPack() with the user's preferred pack.
    }

    func loadPack(_ packName: String) {
        let resolvedURLs = NotificationSound.allCases.compactMap { sound -> (NotificationSound, URL)? in
            guard let url = soundURL(for: sound, pack: packName) else { return nil }
            return (sound, url)
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.currentPack = packName
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

    private static let packPrefixes: [String: String] = [
        "Majorly-G": "majorlyg_",
        "Old": "old_",
    ]

    private func soundURL(for sound: NotificationSound, pack: String) -> URL? {
        // Try the selected pack first (prefixed files).
        if pack != SoundPlayer.defaultPack,
           let prefix = Self.packPrefixes[pack],
           let url = Bundle.main.url(forResource: "\(prefix)\(sound.rawValue)", withExtension: "wav") {
            return url
        }
        // Fall back to Default (unprefixed).
        return Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")
    }
}
