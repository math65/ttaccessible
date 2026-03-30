//
//  LastChannelStore.swift
//  ttaccessible
//

import Foundation

final class LastChannelStore {
    private let key = "lastChannelPathByServer"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func channelPath(forServerKey serverKey: String) -> String? {
        guard !serverKey.isEmpty,
              let dict = defaults.dictionary(forKey: key),
              let value = dict[serverKey] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    func setChannelPath(_ path: String, forServerKey serverKey: String) {
        guard !serverKey.isEmpty else { return }
        var dict = defaults.dictionary(forKey: key) ?? [:]
        dict[serverKey] = path
        defaults.set(dict, forKey: key)
    }

    static func serverKey(host: String, tcpPort: Int, username: String) -> String {
        "\(host):\(tcpPort):\(username)"
    }
}
