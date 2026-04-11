//
//  SessionHistoryEntry.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct SessionHistoryEntry: Equatable, Identifiable {
    enum Kind: String, Equatable, CaseIterable, Codable, Hashable {
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

        var localizationKey: String {
            "preferences.historyEvent.\(rawValue)"
        }

        /// Event kinds that can be individually toggled for announcements.
        /// Excludes message types (those have their own dedicated toggles).
        static let announceable: [Kind] = Kind.allCases.filter { kind in
            switch kind {
            case .privateMessageReceived, .channelMessageReceived, .broadcastSent, .broadcastReceived:
                return false
            default:
                return true
            }
        }

        struct Group: Identifiable {
            let id: String
            let localizationKey: String
            let kinds: [Kind]
        }

        static let announcementGroups: [Group] = [
            Group(id: "connection", localizationKey: "preferences.historyEvents.group.connection",
                  kinds: [.connected, .disconnected, .connectionLost]),
            Group(id: "ownChannel", localizationKey: "preferences.historyEvents.group.ownChannel",
                  kinds: [.joinedChannel, .leftChannel]),
            Group(id: "userPresence", localizationKey: "preferences.historyEvents.group.userPresence",
                  kinds: [.userLoggedIn, .userLoggedOut, .userJoinedChannel, .userLeftChannel]),
            Group(id: "moderation", localizationKey: "preferences.historyEvents.group.moderation",
                  kinds: [.kickedFromServer, .kickedFromChannel, .transmissionBlocked]),
            Group(id: "status", localizationKey: "preferences.historyEvents.group.status",
                  kinds: [.autoAwayActivated, .autoAwayDeactivated]),
            Group(id: "subscriptions", localizationKey: "preferences.historyEvents.group.subscriptions",
                  kinds: [.subscriptionChanged, .interceptSubscriptionChanged]),
            Group(id: "files", localizationKey: "preferences.historyEvents.group.files",
                  kinds: [.fileAdded, .fileRemoved]),
        ]
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
        broadcastMessagesEnabled: Bool,
        disabledKinds: Set<SessionHistoryEntry.Kind> = []
    ) -> Bool {
        if disabledKinds.contains(entry.kind) { return false }
        switch entry.kind {
        case .privateMessageReceived, .channelMessageReceived:
            return false
        case .broadcastReceived:
            return broadcastMessagesEnabled
        default:
            return true
        }
    }

    static func shouldAnnounceBackgroundHistoryEntry(
        _ entry: SessionHistoryEntry,
        disabledKinds: Set<SessionHistoryEntry.Kind> = []
    ) -> Bool {
        if disabledKinds.contains(entry.kind) { return false }
        switch entry.kind {
        case .privateMessageReceived, .channelMessageReceived, .broadcastReceived, .broadcastSent:
            return false
        default:
            return true
        }
    }
}
