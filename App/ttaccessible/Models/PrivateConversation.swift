//
//  PrivateConversation.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct PrivateConversation: Equatable, Identifiable {
    var id: Int32 { peerUserID }

    let peerUserID: Int32
    var peerDisplayName: String
    var messages: [PrivateChatMessage]
    var hasUnreadMessages: Bool
    var isPeerCurrentlyOnline: Bool
    var lastActivityAt: Date

    var lastMessagePreview: String {
        messages.last?.message ?? ""
    }
}
