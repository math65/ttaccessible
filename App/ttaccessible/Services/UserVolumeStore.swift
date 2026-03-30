//
//  UserVolumeStore.swift
//  ttaccessible
//

import Foundation

final class UserVolumeStore {
    private let key = "userVoiceVolumeByUsername"
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
        guard !username.isEmpty else { return }
        var dict = defaults.dictionary(forKey: key) ?? [:]
        dict[username] = Int(volume)
        defaults.set(dict, forKey: key)
    }
}
