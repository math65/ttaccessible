//
//  PrivateChatMessage.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct PrivateChatMessage: Equatable, Identifiable {
    let id: UUID
    let peerUserID: Int32
    let peerDisplayName: String
    let senderUserID: Int32
    let senderDisplayName: String
    let message: String
    let isOwnMessage: Bool
    let receivedAt: Date
}
