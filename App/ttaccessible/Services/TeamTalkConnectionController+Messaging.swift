//
//  TeamTalkConnectionController+Messaging.swift
//  ttaccessible
//
//  Extracted from TeamTalkConnectionController.swift
//

import Foundation

// MARK: - Messaging

extension TeamTalkConnectionController {

    // MARK: Public

    func rememberedChannelPassword(for channelID: Int32) -> String {
        queue.sync {
            channelPasswords[channelID] ?? ""
        }
    }

    func openPrivateConversation(
        withUserID userID: Int32,
        displayName: String,
        activate: Bool = true
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                return
            }

            self.ensurePrivateConversationLocked(
                peerUserID: userID,
                peerDisplayName: self.privatePeerDisplayName(forUserID: userID, fallback: displayName, instance: instance)
            )
            self.selectedPrivateConversationUserID = userID
            self.publishSessionLocked(instance: instance, record: record)
            self.publishPrivateMessagesWindowRequest(
                userID: userID,
                reason: activate ? .userInitiated : .incomingMessage
            )
        }
    }

    func updatePrivateMessagesConsultation(isWindowVisible: Bool, selectedUserID: Int32?) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.isPrivateMessagesWindowVisible = isWindowVisible
            self.visiblePrivateConversationUserID = isWindowVisible ? selectedUserID : nil
        }
    }

    func markPrivateConversationAsRead(_ userID: Int32) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord,
                  var conversation = self.privateConversations[userID] else {
                return
            }

            conversation.hasUnreadMessages = false
            self.privateConversations[userID] = conversation
            self.selectedPrivateConversationUserID = userID
            if self.isPrivateMessagesWindowVisible {
                self.visiblePrivateConversationUserID = userID
            }
            self.publishSessionLocked(instance: instance, record: record)
        }
    }

    func sendPrivateMessage(
        toUserID userID: Int32,
        text: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("privateMessages.error.emptyMessage"))))
                }
                return
            }

            let myUserID = TT_GetMyUserID(instance)
            let peerName = self.privatePeerDisplayName(
                forUserID: userID,
                fallback: L10n.format("connectedServer.chat.sender.unknown", String(userID)),
                instance: instance
            )
            let baseMessage = self.makeOutgoingPrivateTextMessage(toUserID: userID, fromUserID: myUserID)
            let parts = self.buildTextMessages(from: baseMessage, content: trimmed)

            guard parts.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("privateMessages.error.sendFailed"))))
                }
                return
            }

            self.ensurePrivateConversationLocked(peerUserID: userID, peerDisplayName: peerName)

            for part in parts {
                var mutablePart = part
                let commandID = withUnsafeMutablePointer(to: &mutablePart) { pointer in
                    TT_DoTextMessage(instance, pointer)
                }
                guard commandID > 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(TeamTalkConnectionError.internalError(L10n.text("privateMessages.error.sendFailed"))))
                    }
                    return
                }
            }

            if var conversation = self.privateConversations[userID] {
                let now = Date()
                conversation.peerDisplayName = peerName
                conversation.isPeerCurrentlyOnline = self.isUserOnlineLocked(userID: userID, instance: instance)
                conversation.lastActivityAt = now
                conversation.hasUnreadMessages = false
                conversation.messages.append(
                    PrivateChatMessage(
                        id: UUID(),
                        peerUserID: userID,
                        peerDisplayName: peerName,
                        senderUserID: myUserID,
                        senderDisplayName: self.currentUserLocked(instance: instance).map(self.displayName(for:)) ?? self.connectedRecord?.nickname ?? "",
                        message: trimmed,
                        isOwnMessage: true,
                        receivedAt: now
                    )
                )
                self.privateConversations[userID] = conversation
            }

            self.selectedPrivateConversationUserID = userID
            if self.isPrivateMessagesWindowVisible {
                self.visiblePrivateConversationUserID = userID
            }
            SoundPlayer.shared.play(.userMessageSent)
            self.publishSessionLocked(instance: instance, record: record)
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    func sendChannelMessage(_ text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.chat.error.emptyMessage"))))
                }
                return
            }

            let currentChannelID = TT_GetMyChannelID(instance)
            guard currentChannelID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.chat.error.notInChannel"))))
                }
                return
            }

            let myUserID = TT_GetMyUserID(instance)
            let baseMessage = self.makeOutgoingChannelTextMessage(channelID: currentChannelID, fromUserID: myUserID)
            let parts = self.buildTextMessages(from: baseMessage, content: trimmed)

            guard parts.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.chat.error.sendFailed"))))
                }
                return
            }

            for part in parts {
                var mutablePart = part
                let commandID = withUnsafeMutablePointer(to: &mutablePart) { pointer in
                    TT_DoTextMessage(instance, pointer)
                }
                guard commandID > 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.chat.error.sendFailed"))))
                    }
                    return
                }
                self.pendingChannelMessageCommandIDs.insert(commandID)
            }

            self.publishSessionLocked(instance: instance, record: record)

            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    func sendBroadcastMessage(_ text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("broadcast.error.emptyMessage"))))
                }
                return
            }

            let myUserID = TT_GetMyUserID(instance)
            let baseMessage = self.makeOutgoingBroadcastTextMessage(fromUserID: myUserID)
            let parts = self.buildTextMessages(from: baseMessage, content: trimmed)
            guard parts.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("broadcast.error.sendFailed"))))
                }
                return
            }

            do {
                for part in parts {
                    var mutablePart = part
                    let commandID = withUnsafeMutablePointer(to: &mutablePart) { pointer in
                        TT_DoTextMessage(instance, pointer)
                    }
                    guard commandID > 0 else {
                        throw TeamTalkConnectionError.internalError(L10n.text("broadcast.error.sendFailed"))
                    }
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                }

                let senderName = self.displayName(forUserID: myUserID, instance: instance)
                self.appendBroadcastSentHistoryLocked(senderName: senderName, content: trimmed, userID: myUserID)
                SoundPlayer.shared.play(.broadcastMessage)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: Internal

    @discardableResult
    func handleTextMessageEventLocked(
        _ textMessage: TextMessage,
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord
    ) -> Bool {
        guard let mergedText = mergeTextMessageLocked(textMessage),
              mergedText.isEmpty == false else {
            return false
        }

        let myUserID = TT_GetMyUserID(instance)

        switch textMessage.nMsgType {
        case MSGTYPE_CHANNEL:
            let messageDate = Date()
            let senderName = displayName(forUserID: textMessage.nFromUserID, instance: instance)
            let isOwnMessage = textMessage.nFromUserID == myUserID
            channelChatHistory.append(
                ChannelChatMessage(
                    id: UUID(),
                    channelID: textMessage.nChannelID,
                    senderUserID: textMessage.nFromUserID,
                    senderDisplayName: senderName,
                    message: mergedText,
                    isOwnMessage: isOwnMessage,
                    receivedAt: messageDate
                )
            )
            if isOwnMessage {
                SoundPlayer.shared.play(.channelMessageSent)
            } else {
                appendHistoryLocked(
                    kind: .channelMessageReceived,
                    message: L10n.format("history.channelMessageReceived", senderName),
                    channelID: textMessage.nChannelID,
                    userID: textMessage.nFromUserID,
                    timestamp: messageDate
                )
                SoundPlayer.shared.play(.channelMessage)
                publishIncomingTextMessage(
                    IncomingTextMessageEvent(
                        kind: .channelMessage,
                        senderName: senderName,
                        content: mergedText
                    )
                )
            }
            return true
        case MSGTYPE_BROADCAST:
            let messageDate = Date()
            let senderName = displayName(forUserID: textMessage.nFromUserID, instance: instance)
            let isOwnMessage = textMessage.nFromUserID == myUserID
            if isOwnMessage == false {
                appendBroadcastReceivedHistoryLocked(
                    senderName: senderName,
                    content: mergedText,
                    userID: textMessage.nFromUserID,
                    timestamp: messageDate
                )
                SoundPlayer.shared.play(.broadcastMessage)
                publishIncomingTextMessage(
                    IncomingTextMessageEvent(
                        kind: .broadcastMessage,
                        senderName: senderName,
                        content: mergedText
                    )
                )
            }
            return true
        case MSGTYPE_USER:
            let isOwnMessage = textMessage.nFromUserID == myUserID
            let peerUserID = isOwnMessage ? textMessage.nToUserID : textMessage.nFromUserID
            let peerName = privatePeerDisplayName(
                forUserID: peerUserID,
                fallback: L10n.format("connectedServer.chat.sender.unknown", String(peerUserID)),
                instance: instance
            )
            let senderName = displayName(forUserID: textMessage.nFromUserID, instance: instance)
            let messageDate = Date()

            ensurePrivateConversationLocked(peerUserID: peerUserID, peerDisplayName: peerName)
            if var conversation = privateConversations[peerUserID] {
                if isOwnMessage,
                   let lastMessage = conversation.messages.last,
                   lastMessage.isOwnMessage,
                   lastMessage.senderUserID == textMessage.nFromUserID,
                   lastMessage.message == mergedText {
                    conversation.peerDisplayName = peerName
                    conversation.isPeerCurrentlyOnline = isUserOnlineLocked(userID: peerUserID, instance: instance)
                    conversation.lastActivityAt = max(conversation.lastActivityAt, lastMessage.receivedAt)
                    conversation.hasUnreadMessages = false
                    privateConversations[peerUserID] = conversation
                    if isPrivateMessagesWindowVisible,
                       visiblePrivateConversationUserID == peerUserID {
                        selectedPrivateConversationUserID = peerUserID
                    }
                    return true
                }
                conversation.peerDisplayName = peerName
                conversation.messages.append(
                    PrivateChatMessage(
                        id: UUID(),
                        peerUserID: peerUserID,
                        peerDisplayName: peerName,
                        senderUserID: textMessage.nFromUserID,
                        senderDisplayName: senderName,
                        message: mergedText,
                        isOwnMessage: isOwnMessage,
                        receivedAt: messageDate
                    )
                )
                conversation.lastActivityAt = messageDate
                conversation.isPeerCurrentlyOnline = isUserOnlineLocked(userID: peerUserID, instance: instance)
                let isActivelyConsulted = isPrivateMessagesWindowVisible && visiblePrivateConversationUserID == peerUserID
                conversation.hasUnreadMessages = isOwnMessage ? false : !isActivelyConsulted
                privateConversations[peerUserID] = conversation
            }
            if isOwnMessage == false {
                appendHistoryLocked(
                    kind: .privateMessageReceived,
                    message: L10n.format("history.privateMessageReceived", senderName),
                    userID: textMessage.nFromUserID,
                    timestamp: messageDate
                )
                SoundPlayer.shared.play(.userMessage)
                publishIncomingTextMessage(
                    IncomingTextMessageEvent(
                        kind: .privateMessage,
                        senderName: senderName,
                        content: mergedText
                    )
                )
            }
            if isOwnMessage || isPrivateMessagesWindowVisible == false || selectedPrivateConversationUserID == nil {
                selectedPrivateConversationUserID = peerUserID
            }
            publishPrivateMessagesWindowRequest(userID: peerUserID, reason: .incomingMessage)
            return true
        default:
            return false
        }
    }

    func mergeTextMessageLocked(_ textMessage: TextMessage) -> String? {
        let key = textMessageMergeKey(for: textMessage)
        pendingTextMessages[key, default: []].append(textMessage)

        if textMessage.bMore != 0 {
            if pendingTextMessages[key]?.count ?? 0 > 1000 {
                pendingTextMessages.removeValue(forKey: key)
            }
            return nil
        }

        let merged = (pendingTextMessages[key] ?? []).map { ttString(from: $0.szMessage) }.joined()
        pendingTextMessages.removeValue(forKey: key)
        return merged
    }

    func textMessageMergeKey(for textMessage: TextMessage) -> UInt64 {
        let type = UInt64(UInt32(textMessage.nMsgType.rawValue))
        let fromUserID = UInt64(UInt32(bitPattern: textMessage.nFromUserID))
        let toUserID = UInt64(UInt32(bitPattern: textMessage.nToUserID))
        return (type << 32) | (fromUserID << 16) | toUserID
    }

    func makeOutgoingChannelTextMessage(channelID: Int32, fromUserID: Int32) -> TextMessage {
        var message = TextMessage()
        message.nMsgType = MSGTYPE_CHANNEL
        message.nFromUserID = fromUserID
        message.nChannelID = channelID
        message.nToUserID = 0
        message.bMore = 0
        return message
    }

    func makeOutgoingBroadcastTextMessage(fromUserID: Int32) -> TextMessage {
        var message = TextMessage()
        message.nMsgType = MSGTYPE_BROADCAST
        message.nFromUserID = fromUserID
        message.nToUserID = 0
        message.nChannelID = 0
        message.bMore = 0
        return message
    }

    func makeOutgoingPrivateTextMessage(toUserID: Int32, fromUserID: Int32) -> TextMessage {
        var message = TextMessage()
        message.nMsgType = MSGTYPE_USER
        message.nFromUserID = fromUserID
        message.nToUserID = toUserID
        message.nChannelID = 0
        message.bMore = 0
        return message
    }

    func buildTextMessages(from baseMessage: TextMessage, content: String) -> [TextMessage] {
        guard content.isEmpty == false else {
            return []
        }

        if content.utf8.count <= Int(TT_STRLEN - 1) {
            var message = baseMessage
            copyTTString(content, into: &message.szMessage)
            message.bMore = 0
            return [message]
        }

        var message = baseMessage
        message.bMore = 1

        var currentLength = content.count
        while String(content.prefix(currentLength)).utf8.count > Int(TT_STRLEN - 1) {
            currentLength /= 2
        }

        var half = Int(TT_STRLEN / 2)
        while half > 0 {
            let candidateLength = min(content.count, currentLength + half)
            let candidate = String(content.prefix(candidateLength))
            let utf8Count = candidate.utf8.count
            if utf8Count <= Int(TT_STRLEN - 1) {
                currentLength = candidateLength
            }
            if utf8Count == Int(TT_STRLEN - 1) {
                break
            }
            half /= 2
        }

        let prefix = String(content.prefix(currentLength))
        let remainder = String(content.dropFirst(currentLength))
        copyTTString(prefix, into: &message.szMessage)

        return [message] + buildTextMessages(from: baseMessage, content: remainder)
    }

    func ensurePrivateConversationLocked(peerUserID: Int32, peerDisplayName: String) {
        if var conversation = privateConversations[peerUserID] {
            conversation.peerDisplayName = peerDisplayName
            privateConversations[peerUserID] = conversation
            return
        }

        privateConversations[peerUserID] = PrivateConversation(
            peerUserID: peerUserID,
            peerDisplayName: peerDisplayName,
            messages: [],
            hasUnreadMessages: false,
            isPeerCurrentlyOnline: true,
            lastActivityAt: Date.distantPast
        )
    }

    func isUserOnlineLocked(userID: Int32, instance: UnsafeMutableRawPointer) -> Bool {
        var user = User()
        return TT_GetUser(instance, userID, &user) != 0
    }

    func privatePeerDisplayName(
        forUserID userID: Int32,
        fallback: String,
        instance: UnsafeMutableRawPointer
    ) -> String {
        var user = User()
        if TT_GetUser(instance, userID, &user) != 0 {
            return displayName(for: user)
        }
        return fallback
    }

    func publishPrivateMessagesWindowRequest(userID: Int32?, reason: PrivateMessagesPresentationReason) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didRequestPrivateMessagesWindowFor: userID, reason: reason)
        }
    }

    func publishIncomingTextMessage(_ event: IncomingTextMessageEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didReceiveIncomingTextMessage: event)
        }
    }
}
