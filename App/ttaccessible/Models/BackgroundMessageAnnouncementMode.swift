//
//  BackgroundMessageAnnouncementMode.swift
//  ttaccessible
//

import Foundation

enum BackgroundMessageAnnouncementMode: String, Codable, Identifiable, CaseIterable {
    case nativeVoiceOver
    case systemNotification
    case macOSTextToSpeech
    case voiceOverAppleScript

    static var allCases: [BackgroundMessageAnnouncementMode] {
        [.systemNotification, .macOSTextToSpeech, .voiceOverAppleScript]
    }

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .nativeVoiceOver:
            return "preferences.notifications.backgroundMode.nativeVoiceOver"
        case .systemNotification:
            return "preferences.notifications.backgroundMode.systemNotification"
        case .macOSTextToSpeech:
            return "preferences.notifications.backgroundMode.macOSTextToSpeech"
        case .voiceOverAppleScript:
            return "preferences.notifications.backgroundMode.voiceOverAppleScript"
        }
    }

    var normalizedForBackground: BackgroundMessageAnnouncementMode {
        switch self {
        case .nativeVoiceOver:
            return .systemNotification
        case .systemNotification, .macOSTextToSpeech, .voiceOverAppleScript:
            return self
        }
    }
}

enum BackgroundMessageAnnouncementType: CaseIterable, Identifiable {
    case privateMessages
    case channelMessages
    case broadcastMessages
    case sessionHistory

    var id: String { titleLocalizationKey }

    var titleLocalizationKey: String {
        switch self {
        case .privateMessages:
            return "preferences.notifications.background.privateMessages"
        case .channelMessages:
            return "preferences.notifications.background.channelMessages"
        case .broadcastMessages:
            return "preferences.notifications.background.broadcastMessages"
        case .sessionHistory:
            return "preferences.notifications.background.sessionHistory"
        }
    }

    var nativeAnnouncementLocalizationKey: String {
        switch self {
        case .privateMessages:
            return "backgroundAnnouncement.privateMessage"
        case .channelMessages:
            return "backgroundAnnouncement.channelMessage"
        case .broadcastMessages:
            return "backgroundAnnouncement.broadcastMessage"
        case .sessionHistory:
            return "notification.sessionHistory.title"
        }
    }

    var systemNotificationTitleLocalizationKey: String {
        switch self {
        case .privateMessages:
            return "notification.privateMessage.title"
        case .channelMessages:
            return "notification.channelMessage.title"
        case .broadcastMessages:
            return "notification.broadcastMessage.title"
        case .sessionHistory:
            return "notification.sessionHistory.title"
        }
    }

    func mode(from preferences: AppPreferences) -> BackgroundMessageAnnouncementMode {
        switch self {
        case .privateMessages:
            return preferences.privateMessagesBackgroundMode
        case .channelMessages:
            return preferences.channelMessagesBackgroundMode
        case .broadcastMessages:
            return preferences.broadcastMessagesBackgroundMode
        case .sessionHistory:
            return preferences.sessionHistoryBackgroundMode
        }
    }
}
