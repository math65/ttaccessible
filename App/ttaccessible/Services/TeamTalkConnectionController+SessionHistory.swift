//
//  TeamTalkConnectionController+SessionHistory.swift
//  ttaccessible
//
//  Extracted from TeamTalkConnectionController.swift
//

import Foundation

// MARK: - Session history

extension TeamTalkConnectionController {

    func appendHistoryLocked(
        kind: SessionHistoryEntry.Kind,
        message: String,
        channelID: Int32? = nil,
        userID: Int32? = nil,
        timestamp: Date = Date()
    ) {
        sessionHistory.append(
            SessionHistoryEntry(
                id: UUID(),
                kind: kind,
                message: message,
                timestamp: timestamp,
                channelID: channelID,
                userID: userID
            )
        )
    }

    func appendConnectedHistoryLocked(record: SavedServerRecord) {
        appendHistoryLocked(
            kind: .connected,
            message: L10n.format("history.connected", record.name)
        )
    }

    func appendDisconnectedHistoryLocked() {
        appendHistoryLocked(
            kind: .disconnected,
            message: L10n.text("history.disconnected")
        )
    }

    func appendConnectionLostHistoryLocked() {
        appendHistoryLocked(
            kind: .connectionLost,
            message: L10n.text("history.connectionLost")
        )
    }

    func appendAutoAwayActivatedHistoryLocked() {
        appendHistoryLocked(
            kind: .autoAwayActivated,
            message: L10n.text("history.autoAwayActivated")
        )
    }

    func appendAutoAwayDeactivatedHistoryLocked() {
        appendHistoryLocked(
            kind: .autoAwayDeactivated,
            message: L10n.text("history.autoAwayDeactivated")
        )
    }

    func saveLastChannelLocked(channelID: Int32, instance: UnsafeMutableRawPointer) {
        guard channelID > 0, let record = connectedRecord else { return }
        var pathBuffer = [TTCHAR](repeating: 0, count: Int(TT_STRLEN))
        guard TT_GetChannelPath(instance, channelID, &pathBuffer) != 0 else { return }
        let path = String(cString: pathBuffer)
        guard !path.isEmpty else { return }
        let serverKey = LastChannelStore.serverKey(host: record.host, tcpPort: record.tcpPort, username: record.username)
        lastChannelStore.setChannelPath(path, forServerKey: serverKey)
    }

    func appendJoinedChannelHistoryLocked(channelID: Int32, instance: UnsafeMutableRawPointer) {
        appendHistoryLocked(
            kind: .joinedChannel,
            message: L10n.format("history.joinedChannel", historyChannelNameLocked(channelID: channelID, instance: instance)),
            channelID: channelID
        )
    }

    func appendLeftChannelHistoryLocked(channelID: Int32, instance: UnsafeMutableRawPointer) {
        appendHistoryLocked(
            kind: .leftChannel,
            message: L10n.format("history.leftChannel", historyChannelNameLocked(channelID: channelID, instance: instance)),
            channelID: channelID
        )
    }

    func appendUserLoggedInHistoryLocked(_ user: User, currentUserID: Int32) {
        guard user.nUserID != currentUserID else {
            return
        }
        appendHistoryLocked(
            kind: .userLoggedIn,
            message: L10n.format("history.userLoggedIn", displayName(for: user)),
            userID: user.nUserID
        )
    }

    func appendUserLoggedOutHistoryLocked(_ user: User, currentUserID: Int32) {
        guard user.nUserID != currentUserID else {
            return
        }
        appendHistoryLocked(
            kind: .userLoggedOut,
            message: L10n.format("history.userLoggedOut", displayName(for: user)),
            userID: user.nUserID
        )
    }

    func appendUserJoinedChannelHistoryLocked(
        _ user: User,
        currentUserID: Int32,
        instance: UnsafeMutableRawPointer
    ) {
        guard user.nUserID != currentUserID else {
            return
        }
        appendHistoryLocked(
            kind: .userJoinedChannel,
            message: L10n.format(
                "history.userJoinedChannel",
                displayName(for: user),
                historyChannelNameLocked(channelID: user.nChannelID, instance: instance)
            ),
            channelID: user.nChannelID,
            userID: user.nUserID
        )
    }

    func appendUserLeftChannelHistoryLocked(
        _ user: User,
        currentUserID: Int32,
        instance: UnsafeMutableRawPointer
    ) {
        guard user.nUserID != currentUserID else {
            return
        }
        appendHistoryLocked(
            kind: .userLeftChannel,
            message: L10n.format(
                "history.userLeftChannel",
                displayName(for: user),
                historyChannelNameLocked(channelID: user.nChannelID, instance: instance)
            ),
            channelID: user.nChannelID,
            userID: user.nUserID
        )
    }

    func appendKickHistoryLocked(_ message: TTMessage, instance: UnsafeMutableRawPointer) {
        let actorName: String
        if message.ttType == __USER {
            actorName = displayName(for: message.user)
        } else {
            actorName = L10n.text("history.unknownUser")
        }

        if message.nSource == 0 {
            appendHistoryLocked(
                kind: .kickedFromServer,
                message: L10n.format("history.kickedFromServer", actorName),
                userID: message.ttType == __USER ? message.user.nUserID : nil
            )
        } else {
            let channelID = TT_GetMyChannelID(instance)
            appendHistoryLocked(
                kind: .kickedFromChannel,
                message: L10n.format("history.kickedFromChannel", actorName),
                channelID: channelID > 0 ? channelID : nil,
                userID: message.ttType == __USER ? message.user.nUserID : nil
            )
        }
    }

    func appendFileHistoryLocked(
        _ file: RemoteFile,
        isAdded: Bool,
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord
    ) {
        guard isSuppressingFileHistoryLocked == false else {
            return
        }
        let username = ttString(from: file.szUsername)
        let actorName = historyActorNameLocked(username: username, instance: instance, record: record)
        let key = isAdded ? "history.fileAdded" : "history.fileRemoved"
        appendHistoryLocked(
            kind: isAdded ? .fileAdded : .fileRemoved,
            message: L10n.format(key, actorName, ttString(from: file.szFileName)),
            channelID: file.nChannelID,
            userID: userIDForUsernameLocked(username, instance: instance)
        )
        if file.nChannelID == TT_GetMyChannelID(instance) {
            SoundPlayer.shared.play(.fileUpdate)
        }
    }

    func appendTransmissionBlockedHistoryLocked() {
        appendHistoryLocked(
            kind: .transmissionBlocked,
            message: L10n.text("history.transmissionBlocked")
        )
    }

    func appendBroadcastSentHistoryLocked(senderName: String, content: String, userID: Int32?) {
        appendHistoryLocked(
            kind: .broadcastSent,
            message: L10n.format("history.broadcastSent", senderName, content),
            userID: userID
        )
    }

    func appendBroadcastReceivedHistoryLocked(
        senderName: String,
        content: String,
        userID: Int32?,
        timestamp: Date = Date()
    ) {
        appendHistoryLocked(
            kind: .broadcastReceived,
            message: L10n.format("history.broadcastReceived", senderName, content),
            userID: userID,
            timestamp: timestamp
        )
    }

    func appendSubscriptionHistoryLocked(
        _ option: UserSubscriptionOption,
        userName: String,
        enabled: Bool,
        userID: Int32?
    ) {
        appendHistoryLocked(
            kind: option.isIntercept ? .interceptSubscriptionChanged : .subscriptionChanged,
            message: L10n.format(
                option.historyKey,
                userName,
                L10n.text(option.localizationKey),
                L10n.text(enabled ? "common.state.on" : "common.state.off")
            ),
            userID: userID
        )
    }

    func appendSubscriptionHistoryIfNeededLocked(_ user: User) {
        let currentStates = Dictionary(uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
            (option, option.isPeerEnabled(for: user))
        })
        let previousStates = observedSubscriptionStates[user.nUserID] ?? [:]

        for option in UserSubscriptionOption.allCases {
            let currentValue = currentStates[option] ?? false
            if let previousValue = previousStates[option], previousValue != currentValue {
                appendSubscriptionHistoryLocked(
                    option,
                    userName: displayName(for: user),
                    enabled: currentValue,
                    userID: user.nUserID
                )
                if option.isIntercept {
                    SoundPlayer.shared.play(currentValue ? .intercept : .interceptEnd)
                }
            }
        }
        observedSubscriptionStates[user.nUserID] = currentStates
    }

    func historyChannelNameLocked(channelID: Int32, instance: UnsafeMutableRawPointer) -> String {
        guard channelID > 0 else {
            return L10n.text("connectedServer.channel.rootName")
        }

        var channel = Channel()
        guard TT_GetChannel(instance, channelID, &channel) != 0 else {
            return L10n.text("connectedServer.channel.rootName")
        }

        if channel.nChannelID == TT_GetRootChannelID(instance) {
            return L10n.text("connectedServer.channel.rootName")
        }

        let name = ttString(from: channel.szName)
        return name.isEmpty ? L10n.text("connectedServer.channel.rootName") : name
    }

    func historyActorNameLocked(
        username: String,
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord
    ) -> String {
        guard username.isEmpty == false else {
            return L10n.text("history.unknownUser")
        }

        if username == record.username {
            return L10n.text("chat.sender.you")
        }

        var user = User()
        if username.withCString({ TT_GetUserByUsername(instance, $0, &user) != 0 }) {
            return displayName(for: user)
        }
        return username
    }

    func userIDForUsernameLocked(_ username: String, instance: UnsafeMutableRawPointer) -> Int32? {
        guard username.isEmpty == false else {
            return nil
        }

        var user = User()
        guard username.withCString({ TT_GetUserByUsername(instance, $0, &user) != 0 }) else {
            return nil
        }
        return user.nUserID
    }
}
