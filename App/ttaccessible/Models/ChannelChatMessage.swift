//
//  ChannelChatMessage.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct ChannelChatMessage: Equatable, Identifiable, Codable {
    let id: UUID
    let channelID: Int32
    let senderUserID: Int32
    let senderDisplayName: String
    let message: String
    let isOwnMessage: Bool
    let receivedAt: Date
}
