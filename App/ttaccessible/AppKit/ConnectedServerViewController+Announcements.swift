//
//  ConnectedServerViewController+Announcements.swift
//  ttaccessible
//

import AppKit

extension ConnectedServerViewController {
    func announceChannelChangeIfNeeded(previousChannelID: Int32, newChannelID: Int32) {
        guard previousChannelID != 0, previousChannelID != newChannelID else {
            return
        }

        if newChannelID > 0 {
            announce(L10n.text("connectedServer.accessibility.channelChanged"))
        } else {
            announce(L10n.text("connectedServer.accessibility.channelLeft"))
        }
    }

    func announceNewChannelMessageIfNeeded(
        previousSession: ConnectedServerSession,
        newSession: ConnectedServerSession,
        preserveSelection: Bool
    ) {
        guard preferencesStore.preferences.voiceOverAnnouncements.channelMessagesEnabled else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        guard preserveSelection else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        let previousCount = previousSession.channelChatHistory.count
        let newCount = newSession.channelChatHistory.count

        guard newCount > previousCount else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        let appendedMessages = newSession.channelChatHistory.suffix(newCount - previousCount)
        guard let latestIncomingMessage = appendedMessages.reversed().first(where: { $0.isOwnMessage == false }) else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        guard latestIncomingMessage.id != lastAnnouncedChannelMessageID else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        let isCurrentChannelChatVisible = isViewLoaded
            && view.window?.isVisible == true
            && NSApp.isActive
            && newSession.currentChannelID == latestIncomingMessage.channelID

        let announcementKey = isCurrentChannelChatVisible
            ? "connectedServer.chat.accessibility.messageSpoken"
            : "connectedServer.chat.accessibility.newMessage"

        announce(
            L10n.format(
                announcementKey,
                latestIncomingMessage.senderDisplayName,
                latestIncomingMessage.message
            )
        )
        lastAnnouncedChannelMessageID = latestIncomingMessage.id
    }

    func announceNewHistoryEntryIfNeeded(previousSession: ConnectedServerSession, newSession: ConnectedServerSession) {
        guard preferencesStore.preferences.voiceOverAnnouncements.sessionHistoryEnabled else {
            lastAnnouncedHistoryEntryID = newSession.sessionHistory.last?.id
            return
        }

        guard let latestEntry = SessionHistoryAnnouncementHelper.latestAppendedEntry(
            previous: previousSession.sessionHistory,
            current: newSession.sessionHistory,
            filter: { [preferencesStore] entry in
                SessionHistoryAnnouncementHelper.shouldAnnounceForegroundHistoryEntry(
                    entry,
                    broadcastMessagesEnabled: preferencesStore.preferences.voiceOverAnnouncements.broadcastMessagesEnabled
                )
            }
        ) else {
            lastAnnouncedHistoryEntryID = newSession.sessionHistory.last?.id
            return
        }

        guard latestEntry.id != lastAnnouncedHistoryEntryID else {
            lastAnnouncedHistoryEntryID = newSession.sessionHistory.last?.id
            return
        }

        announce(latestEntry.message)
        lastAnnouncedHistoryEntryID = latestEntry.id
    }

    func announce(_ message: String) {
        pendingAnnouncements.append(message)
        scheduleAnnouncementFlush()
    }

    func scheduleAnnouncementFlush() {
        guard announcementTimer == nil else { return }
        announcementTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.flushAnnouncements()
        }
    }

    func flushAnnouncements() {
        announcementTimer = nil
        guard pendingAnnouncements.isEmpty == false else { return }
        let combined = pendingAnnouncements.joined(separator: ". ")
        pendingAnnouncements.removeAll()

        let accessibilityElement = NSApp.accessibilityWindow() ?? view.window ?? view
        NSAccessibility.post(
            element: accessibilityElement,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: combined,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
