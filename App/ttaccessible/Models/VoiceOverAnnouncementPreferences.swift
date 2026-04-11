//
//  VoiceOverAnnouncementPreferences.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct VoiceOverAnnouncementPreferences: Codable, Equatable {
    var channelMessagesEnabled: Bool
    var privateMessagesEnabled: Bool
    var broadcastMessagesEnabled: Bool
    var disabledSessionHistoryKinds: Set<SessionHistoryEntry.Kind>

    /// Backward-compatible computed property. Returns true when at least one event is enabled.
    var sessionHistoryEnabled: Bool {
        get {
            disabledSessionHistoryKinds.count < SessionHistoryEntry.Kind.announceable.count
        }
        set {
            if newValue {
                disabledSessionHistoryKinds.removeAll()
            } else {
                disabledSessionHistoryKinds = Set(SessionHistoryEntry.Kind.announceable)
            }
        }
    }

    init(
        channelMessagesEnabled: Bool = true,
        privateMessagesEnabled: Bool = true,
        broadcastMessagesEnabled: Bool = true,
        disabledSessionHistoryKinds: Set<SessionHistoryEntry.Kind> = []
    ) {
        self.channelMessagesEnabled = channelMessagesEnabled
        self.privateMessagesEnabled = privateMessagesEnabled
        self.broadcastMessagesEnabled = broadcastMessagesEnabled
        self.disabledSessionHistoryKinds = disabledSessionHistoryKinds
    }

    // MARK: - Codable migration

    private enum CodingKeys: String, CodingKey {
        case channelMessagesEnabled
        case privateMessagesEnabled
        case broadcastMessagesEnabled
        case disabledSessionHistoryKinds
        case sessionHistoryEnabled // legacy key for migration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .channelMessagesEnabled) ?? true
        privateMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .privateMessagesEnabled) ?? true
        broadcastMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .broadcastMessagesEnabled) ?? true

        if let kinds = try container.decodeIfPresent(Set<SessionHistoryEntry.Kind>.self, forKey: .disabledSessionHistoryKinds) {
            disabledSessionHistoryKinds = kinds
        } else {
            // Migrate from legacy boolean
            let legacyEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionHistoryEnabled) ?? true
            disabledSessionHistoryKinds = legacyEnabled ? [] : Set(SessionHistoryEntry.Kind.announceable)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channelMessagesEnabled, forKey: .channelMessagesEnabled)
        try container.encode(privateMessagesEnabled, forKey: .privateMessagesEnabled)
        try container.encode(broadcastMessagesEnabled, forKey: .broadcastMessagesEnabled)
        try container.encode(disabledSessionHistoryKinds, forKey: .disabledSessionHistoryKinds)
    }
}
