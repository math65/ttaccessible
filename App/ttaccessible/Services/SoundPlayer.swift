//
//  SoundPlayer.swift
//  ttaccessible
//

import AVFoundation
import Foundation

enum NotificationSound: String, CaseIterable {
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
}

final class SoundPlayer {
    static let shared = SoundPlayer()

    private var players: [NotificationSound: AVAudioPlayer] = [:]
    private let queue = DispatchQueue(label: "com.math65.ttaccessible.soundplayer")
    var isEnabled = true

    private init() {
        preload()
    }

    private func preload() {
        for sound in NotificationSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            } catch {
                // Sound unavailable — silently skip
            }
        }
    }

    func play(_ sound: NotificationSound) {
        guard isEnabled else { return }
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
}
