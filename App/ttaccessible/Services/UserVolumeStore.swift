//
//  UserVolumeStore.swift
//  ttaccessible
//

import Foundation

final class UserVolumeStore {
    private let key = "userVoiceVolumeByUsername"
    private let mediaFileKey = "userMediaFileVolumeByUsername"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func volume(forUsername username: String) -> Int32? {
        guard !username.isEmpty,
              let dict = defaults.dictionary(forKey: key),
              let value = dict[username] as? Int else { return nil }
        return Int32(value)
    }

    func setVolume(_ volume: Int32, forUsername username: String) {
        setVolume(volume, forUsername: username, key: key)
    }

    func mediaFileVolume(forUsername username: String) -> Int32? {
        volume(forUsername: username, key: mediaFileKey)
    }

    func setMediaFileVolume(_ volume: Int32, forUsername username: String) {
        setVolume(volume, forUsername: username, key: mediaFileKey)
    }

    private func volume(forUsername username: String, key: String) -> Int32? {
        guard !username.isEmpty,
              let dict = defaults.dictionary(forKey: key),
              let value = dict[username] as? Int else { return nil }
        return Int32(value)
    }

    private func setVolume(_ volume: Int32, forUsername username: String, key: String) {
        guard !username.isEmpty else { return }
        var dict = defaults.dictionary(forKey: key) ?? [:]
        if volume == SOUND_VOLUME_DEFAULT.rawValue {
            dict.removeValue(forKey: username)
        } else {
            dict[username] = Int(volume)
        }
        defaults.set(dict, forKey: key)
    }

    // MARK: - Stereo Balance

    private let stereoKey = "userStereoBalanceByUsername"

    struct StereoBalance: Equatable {
        let left: Bool
        let right: Bool
        static let `default` = StereoBalance(left: true, right: true)
    }

    func stereoBalance(forUsername username: String) -> StereoBalance? {
        guard !username.isEmpty,
              let dict = defaults.dictionary(forKey: stereoKey),
              let entry = dict[username] as? [String: Bool],
              let left = entry["left"],
              let right = entry["right"] else { return nil }
        return StereoBalance(left: left, right: right)
    }

    func setStereoBalance(_ balance: StereoBalance, forUsername username: String) {
        guard !username.isEmpty else { return }
        var dict = defaults.dictionary(forKey: stereoKey) ?? [:]
        if balance == .default {
            dict.removeValue(forKey: username)
        } else {
            dict[username] = ["left": balance.left, "right": balance.right]
        }
        defaults.set(dict, forKey: stereoKey)
    }
}
