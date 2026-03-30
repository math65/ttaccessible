//
//  UserSubscriptionOption.swift
//  ttaccessible
//

import SwiftUI

enum UserSubscriptionOption: String, CaseIterable, Hashable {
    case privateMessages
    case channelMessages
    case broadcastMessages
    case voice
    case desktop
    case mediaFile
    case interceptPrivateMessages
    case interceptChannelMessages
    case interceptVoice
    case interceptDesktop
    case interceptMediaFile

    static let regularCases: [UserSubscriptionOption] = [
        .privateMessages,
        .channelMessages,
        .broadcastMessages,
        .voice,
        .desktop,
        .mediaFile
    ]

    static let interceptCases: [UserSubscriptionOption] = [
        .interceptPrivateMessages,
        .interceptChannelMessages,
        .interceptVoice,
        .interceptDesktop,
        .interceptMediaFile
    ]

    var isIntercept: Bool {
        switch self {
        case .interceptPrivateMessages, .interceptChannelMessages, .interceptVoice, .interceptDesktop, .interceptMediaFile:
            return true
        default:
            return false
        }
    }

    var localizationKey: String {
        switch self {
        case .privateMessages:
            return "subscriptions.privateMessages"
        case .channelMessages:
            return "subscriptions.channelMessages"
        case .broadcastMessages:
            return "subscriptions.broadcastMessages"
        case .voice:
            return "subscriptions.voice"
        case .desktop:
            return "subscriptions.desktop"
        case .mediaFile:
            return "subscriptions.mediaFile"
        case .interceptPrivateMessages:
            return "subscriptions.interceptPrivateMessages"
        case .interceptChannelMessages:
            return "subscriptions.interceptChannelMessages"
        case .interceptVoice:
            return "subscriptions.interceptVoice"
        case .interceptDesktop:
            return "subscriptions.interceptDesktop"
        case .interceptMediaFile:
            return "subscriptions.interceptMediaFile"
        }
    }

    var preferencesKey: String {
        switch self {
        case .privateMessages:
            return "preferences.connection.subscribePrivateMessages"
        case .channelMessages:
            return "preferences.connection.subscribeChannelMessages"
        case .broadcastMessages:
            return "preferences.connection.subscribeBroadcastMessages"
        case .voice:
            return "preferences.connection.subscribeVoice"
        case .desktop:
            return "preferences.connection.subscribeDesktop"
        case .mediaFile:
            return "preferences.connection.subscribeMediaFile"
        case .interceptPrivateMessages:
            return "preferences.connection.interceptPrivateMessages"
        case .interceptChannelMessages:
            return "preferences.connection.interceptChannelMessages"
        case .interceptVoice:
            return "preferences.connection.interceptVoice"
        case .interceptDesktop:
            return "preferences.connection.interceptDesktop"
        case .interceptMediaFile:
            return "preferences.connection.interceptMediaFile"
        }
    }

    var historyKey: String {
        isIntercept ? "history.interceptSubscriptionChanged" : "history.subscriptionChanged"
    }

    var subscriptionMask: UInt32 {
        switch self {
        case .privateMessages:
            return UInt32(SUBSCRIBE_USER_MSG.rawValue)
        case .channelMessages:
            return UInt32(SUBSCRIBE_CHANNEL_MSG.rawValue)
        case .broadcastMessages:
            return UInt32(SUBSCRIBE_BROADCAST_MSG.rawValue)
        case .voice:
            return UInt32(SUBSCRIBE_VOICE.rawValue)
        case .desktop:
            return UInt32(SUBSCRIBE_DESKTOP.rawValue)
        case .mediaFile:
            return UInt32(SUBSCRIBE_MEDIAFILE.rawValue)
        case .interceptPrivateMessages:
            return UInt32(SUBSCRIBE_INTERCEPT_USER_MSG.rawValue)
        case .interceptChannelMessages:
            return UInt32(SUBSCRIBE_INTERCEPT_CHANNEL_MSG.rawValue)
        case .interceptVoice:
            return UInt32(SUBSCRIBE_INTERCEPT_VOICE.rawValue)
        case .interceptDesktop:
            return UInt32(SUBSCRIBE_INTERCEPT_DESKTOP.rawValue)
        case .interceptMediaFile:
            return UInt32(SUBSCRIBE_INTERCEPT_MEDIAFILE.rawValue)
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .privateMessages, .interceptPrivateMessages:
            return "1"
        case .channelMessages, .interceptChannelMessages:
            return "2"
        case .broadcastMessages:
            return "3"
        case .voice, .interceptVoice:
            return "4"
        case .desktop, .interceptDesktop:
            return "5"
        case .mediaFile, .interceptMediaFile:
            return "6"
        }
    }

    var shortcutModifiers: EventModifiers {
        isIntercept ? [.control, .command, .shift] : [.control, .command]
    }

    func isLocallyEnabled(for user: User) -> Bool {
        (user.uLocalSubscriptions & subscriptionMask) != 0
    }

    func isPeerEnabled(for user: User) -> Bool {
        (user.uPeerSubscriptions & subscriptionMask) != 0
    }

    func isEnabled(for user: ConnectedServerUser) -> Bool {
        user.subscriptionStates[self] ?? false
    }
}
