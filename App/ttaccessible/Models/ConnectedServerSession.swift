//
//  ConnectedServerSession.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct ConnectedServerUser: Equatable, Identifiable {
    let id: Int32
    let username: String
    let nickname: String
    let channelID: Int32
    let statusMode: TeamTalkStatusMode
    let statusMessage: String
    let gender: TeamTalkGender
    let isCurrentUser: Bool
    let isAdministrator: Bool
    let isChannelOperator: Bool
    let isTalking: Bool
    let isMuted: Bool
    let isAway: Bool
    let isQuestion: Bool
    let ipAddress: String
    let clientName: String
    let clientVersion: String
    let volumeVoice: Int32
    let subscriptionStates: [UserSubscriptionOption: Bool]
    let channelPathComponents: [String]

    var displayName: String {
        if username.isEmpty {
            return nickname
        }
        return "\(nickname) (\(username))"
    }

    func isSubscriptionEnabled(_ option: UserSubscriptionOption) -> Bool {
        option.isEnabled(for: self)
    }
}

struct ConnectedServerChannel: Equatable, Identifiable {
    let id: Int32
    let parentID: Int32
    let name: String
    let topic: String
    let isPasswordProtected: Bool
    let isHidden: Bool
    let isCurrentChannel: Bool
    let pathComponents: [String]
    let children: [ConnectedServerChannel]
    let users: [ConnectedServerUser]

    var directUserCount: Int {
        users.count
    }

    var totalUserCount: Int {
        directUserCount + children.reduce(0) { $0 + $1.totalUserCount }
    }
}

extension ConnectedServerSession {
    var currentUser: ConnectedServerUser? {
        findUser(in: rootChannels)
    }

    private func findUser(in channels: [ConnectedServerChannel]) -> ConnectedServerUser? {
        for ch in channels {
            if let u = ch.users.first(where: { $0.isCurrentUser }) { return u }
            if let u = findUser(in: ch.children) { return u }
        }
        return nil
    }

    var currentChannelName: String? {
        guard currentChannelID > 0 else { return nil }
        return findChannel(id: currentChannelID, in: rootChannels)?.name
    }

    private func findChannel(id: Int32, in channels: [ConnectedServerChannel]) -> ConnectedServerChannel? {
        for ch in channels {
            if ch.id == id { return ch }
            if let found = findChannel(id: id, in: ch.children) { return found }
        }
        return nil
    }
}

enum ServerTreeNode: Equatable {
    case channel(ConnectedServerChannel)
    case user(ConnectedServerUser)
}

struct FileTransferProgress: Equatable {
    let transferID: Int32
    let fileName: String
    let transferred: Int64
    let total: Int64
    let isDownload: Bool

    var percent: Int {
        guard total > 0 else { return 0 }
        return Int(min(transferred * 100 / total, 100))
    }
    var displayText: String { "\(percent) %" }
}

struct ChannelFile: Equatable, Identifiable {
    let id: Int32
    let channelID: Int32
    let name: String
    let size: Int64
    let uploader: String

    var formattedSize: String {
        let bytes = Double(size)
        if bytes < 1024 {
            return "\(size) o"
        } else if bytes < 1_048_576 {
            return String(format: "%.1f Ko", bytes / 1024)
        } else {
            return String(format: "%.1f Mo", bytes / 1_048_576)
        }
    }
}

struct ConnectedServerSession: Equatable {
    let savedServer: SavedServerRecord
    let displayName: String
    let currentNickname: String
    let currentStatusMode: TeamTalkStatusMode
    let currentStatusMessage: String
    let currentGender: TeamTalkGender
    let statusText: String
    let currentChannelID: Int32
    let isAdministrator: Bool
    let rootChannels: [ConnectedServerChannel]
    let channelChatHistory: [ChannelChatMessage]
    let sessionHistory: [SessionHistoryEntry]
    let privateConversations: [PrivateConversation]
    let selectedPrivateConversationUserID: Int32?
    let channelFiles: [ChannelFile]
    let activeTransfers: [FileTransferProgress]
    let outputAudioReady: Bool
    let inputAudioReady: Bool
    let voiceTransmissionEnabled: Bool
    let canSendBroadcast: Bool
    let audioStatusText: String
    let inputGainDB: Double
    let outputGainDB: Double
    let recordingActive: Bool
}

struct ConnectedUserAudioState: Equatable {
    let userID: Int32
    let isTalking: Bool
    let isMuted: Bool
}

struct ConnectedServerAudioRuntimeUpdate: Equatable {
    let userAudioStates: [Int32: ConnectedUserAudioState]
    let voiceTransmissionEnabled: Bool
    let audioStatusText: String
    let inputAudioReady: Bool
    let outputAudioReady: Bool
}
