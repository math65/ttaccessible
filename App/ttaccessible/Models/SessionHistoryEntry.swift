//
//  SessionHistoryEntry.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct SessionHistoryEntry: Equatable, Identifiable {
    enum Kind: Equatable {
        case connected
        case disconnected
        case connectionLost
        case joinedChannel
        case leftChannel
        case userLoggedIn
        case userLoggedOut
        case userJoinedChannel
        case userLeftChannel
        case kickedFromServer
        case kickedFromChannel
        case privateMessageReceived
        case channelMessageReceived
        case broadcastSent
        case broadcastReceived
        case autoAwayActivated
        case autoAwayDeactivated
        case subscriptionChanged
        case interceptSubscriptionChanged
        case fileAdded
        case fileRemoved
        case transmissionBlocked
    }

    let id: UUID
    let kind: Kind
    let message: String
    let timestamp: Date
    let channelID: Int32?
    let userID: Int32?
}

enum SessionHistoryAnnouncementHelper {
    static func latestAppendedEntry(
        previous: [SessionHistoryEntry],
        current: [SessionHistoryEntry],
        filter: (SessionHistoryEntry) -> Bool
    ) -> SessionHistoryEntry? {
        guard current.count > previous.count else {
            return nil
        }

        let appendedEntries = current.suffix(current.count - previous.count)
        return appendedEntries.last(where: filter)
    }

    static func shouldAnnounceForegroundHistoryEntry(
        _ entry: SessionHistoryEntry,
        broadcastMessagesEnabled: Bool
    ) -> Bool {
        switch entry.kind {
        case .privateMessageReceived, .channelMessageReceived:
            return false
        case .broadcastReceived:
            return broadcastMessagesEnabled
        default:
            return true
        }
    }

    static func shouldAnnounceBackgroundHistoryEntry(_ entry: SessionHistoryEntry) -> Bool {
        switch entry.kind {
        case .privateMessageReceived, .channelMessageReceived, .broadcastReceived, .broadcastSent:
            return false
        default:
            return true
        }
    }
}
