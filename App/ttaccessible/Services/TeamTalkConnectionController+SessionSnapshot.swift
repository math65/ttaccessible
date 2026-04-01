//
//  TeamTalkConnectionController+SessionSnapshot.swift
//  ttaccessible
//
//  Extracted from TeamTalkConnectionController.swift
//

import Foundation

extension TeamTalkConnectionController {

    func publishActiveTransfersLocked(currentChannelID: Int32) {
        let transfers = Array(activeTransferProgress.values)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didUpdateActiveTransfers: transfers, currentChannelID: currentChannelID)
        }
    }

    func publishAudioRuntimeUpdateLocked(instance: UnsafeMutableRawPointer) {
        let users = fetchServerUsersLocked(instance: instance)
        let update = ConnectedServerAudioRuntimeUpdate(
            userAudioStates: Dictionary(
                uniqueKeysWithValues: users.map { user in
                    let isTalking = user.nUserID == TT_GetMyUserID(instance)
                        ? voiceTransmissionEnabled
                        : (user.uUserState & UInt32(USERSTATE_VOICE.rawValue)) != 0
                    let isMuted = (user.uUserState & UInt32(USERSTATE_MUTE_VOICE.rawValue)) != 0
                    return (
                        user.nUserID,
                        ConnectedUserAudioState(userID: user.nUserID, isTalking: isTalking, isMuted: isMuted)
                    )
                }
            ),
            voiceTransmissionEnabled: voiceTransmissionEnabled,
            audioStatusText: makeAudioStatusText(),
            inputAudioReady: inputAudioReady,
            outputAudioReady: outputAudioReady
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didUpdateAudioRuntime: update)
        }
    }

    func publishSessionLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        invalidation: SessionPublishInvalidation = .all
    ) {
        let snapshot = makeSessionSnapshotLocked(instance: instance, record: record, invalidation: invalidation)
        lastBuiltSessionSnapshot = snapshot

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.sessionSnapshot = snapshot
            self.isConnected = true
            self.delegate?.teamTalkConnectionController(self, didUpdateSession: snapshot)
        }
    }

    func publishDisconnected(message: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.sessionSnapshot = nil
            self.isConnected = false
            self.delegate?.teamTalkConnectionController(self, didDisconnectWithMessage: message)
        }
    }

    func makeSessionSnapshotLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        invalidation: SessionPublishInvalidation
    ) -> ConnectedServerSession {
        let preferences = preferencesStore.preferences
        let currentChannelID = TT_GetMyChannelID(instance)
        let currentUserID = TT_GetMyUserID(instance)
        let rootChannelID = TT_GetRootChannelID(instance)
        let previousSnapshot = lastBuiltSessionSnapshot
        let requiresRootTree = previousSnapshot == nil || invalidation.contains(.rootTree) || invalidation.contains(.identity)

        let currentUser = requiresRootTree ? currentUserLocked(instance: instance) : nil
        var serverProperties = ServerProperties()
        let hasServerProperties = TT_GetServerProperties(instance, &serverProperties) != 0
        let fetchedServerDisplayName = hasServerProperties ? ttString(from: serverProperties.szServerName) : ""
        let serverDisplayName = fetchedServerDisplayName.isEmpty ? record.name : fetchedServerDisplayName

        let channels = requiresRootTree ? fetchServerChannelsLocked(instance: instance) : []
        let users = requiresRootTree ? fetchServerUsersLocked(instance: instance) : []

        // Single pass over users: build byID dict, byChannel dict, subscription states, and cache display names.
        var roots = previousSnapshot?.rootChannels ?? []
        var currentNickname = previousSnapshot?.currentNickname ?? effectiveNickname(for: record)
        var currentStatusMode = previousSnapshot?.currentStatusMode ?? .available
        var currentStatusMessage = previousSnapshot?.currentStatusMessage ?? ""
        var currentGender = previousSnapshot?.currentGender ?? .neutral
        var statusText = previousSnapshot?.statusText ?? ""

        if requiresRootTree {
            var onlineUsersByID = [INT32: User]()
            onlineUsersByID.reserveCapacity(users.count)
            var usersByChannel = [INT32: [User]]()
            var cachedDisplayNames = [INT32: String]()
            cachedDisplayNames.reserveCapacity(users.count)
            var newObservedSubscriptionStates = [INT32: [UserSubscriptionOption: Bool]]()
            newObservedSubscriptionStates.reserveCapacity(users.count)

            for user in users {
                onlineUsersByID[user.nUserID] = user
                usersByChannel[user.nChannelID, default: []].append(user)
                cachedDisplayNames[user.nUserID] = displayName(for: user)
                newObservedSubscriptionStates[user.nUserID] = Dictionary(
                    uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
                        (option, option.isPeerEnabled(for: user))
                    }
                )
            }
            observedSubscriptionStates = newObservedSubscriptionStates

            for (peerUserID, conversation) in privateConversations {
                var updatedConversation = conversation
                if let user = onlineUsersByID[peerUserID] {
                    updatedConversation.peerDisplayName = cachedDisplayNames[peerUserID] ?? displayName(for: user)
                    updatedConversation.isPeerCurrentlyOnline = true
                } else {
                    updatedConversation.isPeerCurrentlyOnline = false
                }
                privateConversations[peerUserID] = updatedConversation
            }

            let channelsByParent = Dictionary(grouping: channels, by: \.nParentID)
            var cachedChannelNames = [INT32: String]()
            cachedChannelNames.reserveCapacity(channels.count)
            for channel in channels {
                cachedChannelNames[channel.nChannelID] = channel.nChannelID == rootChannelID
                    ? serverDisplayName
                    : ttString(from: channel.szName)
            }

            func buildChannelTree(parentID: Int32, parentPathComponents: [String]) -> [ConnectedServerChannel] {
                let childChannels = (channelsByParent[parentID] ?? [])
                    .sorted { lhs, rhs in
                        let leftName = cachedChannelNames[lhs.nChannelID] ?? ""
                        let rightName = cachedChannelNames[rhs.nChannelID] ?? ""
                        if leftName.localizedCaseInsensitiveCompare(rightName) == .orderedSame {
                            return lhs.nChannelID < rhs.nChannelID
                        }
                        return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
                    }

                return childChannels.map { channel in
                    let channelName = cachedChannelNames[channel.nChannelID] ?? ""
                    let channelPathComponents = parentPathComponents + [channelName]
                    let channelUsers = (usersByChannel[channel.nChannelID] ?? [])
                        .sorted { lhs, rhs in
                            let leftName = cachedDisplayNames[lhs.nUserID] ?? ""
                            let rightName = cachedDisplayNames[rhs.nUserID] ?? ""
                            if leftName.localizedCaseInsensitiveCompare(rightName) == .orderedSame {
                                return lhs.nUserID < rhs.nUserID
                            }
                            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
                        }
                        .map { user in
                            let nickname = cachedDisplayNames[user.nUserID] ?? ""
                            return ConnectedServerUser(
                                id: user.nUserID,
                                username: ttString(from: user.szUsername),
                                nickname: nickname,
                                channelID: user.nChannelID,
                                statusMode: TeamTalkStatusMode(bitmask: user.nStatusMode),
                                statusMessage: ttString(from: user.szStatusMsg),
                                gender: TeamTalkGender(statusBitmask: user.nStatusMode),
                                isCurrentUser: user.nUserID == currentUserID,
                                isAdministrator: (user.uUserType & UInt32(USERTYPE_ADMIN.rawValue)) != 0,
                                isChannelOperator: TT_IsChannelOperator(instance, user.nUserID, user.nChannelID) != 0,
                                isTalking: user.nUserID == currentUserID
                                    ? voiceTransmissionEnabled
                                    : (user.uUserState & UInt32(USERSTATE_VOICE.rawValue)) != 0,
                                isMuted: (user.uUserState & UInt32(USERSTATE_MUTE_VOICE.rawValue)) != 0,
                                isAway: (user.nStatusMode & 0xFF) == 0x01,
                                isQuestion: (user.nStatusMode & 0xFF) == 0x02,
                                ipAddress: ttString(from: user.szIPAddress),
                                clientName: ttString(from: user.szClientName),
                                clientVersion: clientVersion(for: user),
                                volumeVoice: user.nVolumeVoice,
                                subscriptionStates: Dictionary(
                                    uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
                                        (option, option.isLocallyEnabled(for: user))
                                    }
                                ),
                                channelPathComponents: channelPathComponents
                            )
                        }

                    return ConnectedServerChannel(
                        id: channel.nChannelID,
                        parentID: channel.nParentID,
                        name: channelName,
                        topic: ttString(from: channel.szTopic),
                        isPasswordProtected: channel.bPassword != 0,
                        isHidden: (channel.uChannelType & UInt32(CHANNEL_HIDDEN.rawValue)) != 0,
                        isCurrentChannel: channel.nChannelID == currentChannelID,
                        pathComponents: channelPathComponents,
                        children: buildChannelTree(parentID: channel.nChannelID, parentPathComponents: channelPathComponents),
                        users: channelUsers
                    )
                }
            }

            roots = buildChannelTree(parentID: 0, parentPathComponents: [])
            let effectiveRecordNickname = effectiveNickname(for: record)
            currentNickname = currentUser.map { cachedDisplayNames[$0.nUserID] ?? displayName(for: $0) } ?? effectiveRecordNickname
            currentStatusMode = TeamTalkStatusMode(bitmask: currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue)
            currentStatusMessage = currentUser.map { ttString(from: $0.szStatusMsg) } ?? ""
            currentGender = TeamTalkGender(statusBitmask: currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue)
            statusText = makeStatusText(
                currentChannelID: currentChannelID,
                nickname: currentNickname,
                currentStatusMode: currentStatusMode,
                currentStatusMessage: currentStatusMessage,
                channels: channels,
                rootChannelID: rootChannelID
            )
        }

        var channelFiles = previousSnapshot?.channelFiles ?? []
        if previousSnapshot == nil || invalidation.contains(.channelFiles) || invalidation.contains(.rootTree) {
            channelFiles = []
            if currentChannelID > 0 {
            var fileCount: INT32 = 0
            if TT_GetChannelFiles(instance, currentChannelID, nil, &fileCount) != 0, fileCount > 0 {
                var files = Array(repeating: RemoteFile(), count: Int(fileCount))
                if TT_GetChannelFiles(instance, currentChannelID, &files, &fileCount) != 0 {
                    channelFiles = Array(files.prefix(Int(fileCount))).map { file in
                        ChannelFile(
                            id: file.nFileID,
                            channelID: file.nChannelID,
                            name: ttString(from: file.szFileName),
                            size: file.nFileSize,
                            uploader: ttString(from: file.szUsername)
                        )
                    }
                }
            }
        }
        }

        var myAccount = UserAccount()
        let hasMyAccount = TT_GetMyUserAccount(instance, &myAccount) != 0
        let myIsAdmin = hasMyAccount
            && (myAccount.uUserType & UInt32(USERTYPE_ADMIN.rawValue)) != 0
        let canSendBroadcast = hasMyAccount
            && (myAccount.uUserRights & UInt32(USERRIGHT_TEXTMESSAGE_BROADCAST.rawValue)) != 0

        return ConnectedServerSession(
            savedServer: record,
            displayName: record.name,
            currentNickname: currentNickname,
            currentStatusMode: currentStatusMode,
            currentStatusMessage: currentStatusMessage,
            currentGender: currentGender,
            statusText: statusText,
            currentChannelID: currentChannelID,
            isAdministrator: myIsAdmin,
            rootChannels: roots,
            channelChatHistory: previousSnapshot == nil || invalidation.contains(.chat) ? channelChatHistory : (previousSnapshot?.channelChatHistory ?? channelChatHistory),
            sessionHistory: previousSnapshot == nil || invalidation.contains(.history) ? sessionHistory : (previousSnapshot?.sessionHistory ?? sessionHistory),
            privateConversations: previousSnapshot == nil || invalidation.contains(.privateConversations) || invalidation.contains(.rootTree)
                ? privateConversations.values.sorted { lhs, rhs in
                    if lhs.lastActivityAt == rhs.lastActivityAt {
                        return lhs.peerDisplayName.localizedCaseInsensitiveCompare(rhs.peerDisplayName) == .orderedAscending
                    }
                    return lhs.lastActivityAt > rhs.lastActivityAt
                }
                : (previousSnapshot?.privateConversations ?? []),
            selectedPrivateConversationUserID: selectedPrivateConversationUserID,
            channelFiles: channelFiles,
            activeTransfers: previousSnapshot == nil || invalidation.contains(.activeTransfers)
                ? Array(activeTransferProgress.values)
                : (previousSnapshot?.activeTransfers ?? Array(activeTransferProgress.values)),
            outputAudioReady: outputAudioReady,
            inputAudioReady: inputAudioReady,
            voiceTransmissionEnabled: voiceTransmissionEnabled,
            canSendBroadcast: canSendBroadcast,
            audioStatusText: makeAudioStatusText(),
            inputGainDB: preferences.inputGainDB,
            outputGainDB: preferences.outputGainDB,
            recordingActive: recordingMuxedActive
        )
    }

    func makeStatusText(
        currentChannelID: Int32,
        nickname: String,
        currentStatusMode: TeamTalkStatusMode,
        currentStatusMessage: String,
        channels: [Channel],
        rootChannelID: Int32
    ) -> String {
        let statusLabel = L10n.text(currentStatusMode.localizationKey)
        let identity = currentStatusMessage.isEmpty
            ? L10n.format("connectedServer.identity.summary.modeOnly", nickname, statusLabel)
            : L10n.format("connectedServer.identity.summary.withMessage", nickname, statusLabel, currentStatusMessage)

        guard currentChannelID > 0,
              let channel = channels.first(where: { $0.nChannelID == currentChannelID }) else {
            return L10n.format("connectedServer.status.connected", identity)
        }

        let channelName: String
        if channel.nChannelID == rootChannelID {
            channelName = L10n.text("connectedServer.channel.rootName")
        } else {
            channelName = ttString(from: channel.szName)
        }

        return L10n.format("connectedServer.status.inChannel", identity, channelName)
    }
}
