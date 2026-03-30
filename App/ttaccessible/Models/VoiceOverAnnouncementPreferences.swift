//
//  VoiceOverAnnouncementPreferences.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct VoiceOverAnnouncementPreferences: Codable, Equatable {
    var channelMessagesEnabled: Bool
    var privateMessagesEnabled: Bool
    var broadcastMessagesEnabled: Bool
    var sessionHistoryEnabled: Bool

    init(
        channelMessagesEnabled: Bool = true,
        privateMessagesEnabled: Bool = true,
        broadcastMessagesEnabled: Bool = true,
        sessionHistoryEnabled: Bool = true
    ) {
        self.channelMessagesEnabled = channelMessagesEnabled
        self.privateMessagesEnabled = privateMessagesEnabled
        self.broadcastMessagesEnabled = broadcastMessagesEnabled
        self.sessionHistoryEnabled = sessionHistoryEnabled
    }
}
