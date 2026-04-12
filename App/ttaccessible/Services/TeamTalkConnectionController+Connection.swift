//
//  TeamTalkConnectionController+Connection.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 30/03/2026.
//

import AVFoundation
import Foundation

extension TeamTalkConnectionController {

    // MARK: - Public connection API

    func connect(
        to record: SavedServerRecord,
        password: String,
        options: TeamTalkConnectOptions = TeamTalkConnectOptions(),
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.sdkUnavailable))
                }
                return
            }

            do {
                self.resetLocked()
                let instance = try self.createInstanceLocked()
                try self.withSuppressedLoginHistoryLocked {
                    try self.connectAndLoginLocked(
                        instance: instance,
                        record: record,
                        password: password,
                        options: options
                    )
                }
                self.instance = instance
                self.connectedRecord = record
                self.autoJoinAfterLoginLocked(instance: instance, options: options)
                try self.applyPostLoginOptionsLocked(instance: instance, options: options)
                self.applyDefaultSubscriptionPreferencesLocked(instance: instance, preferences: self.preferencesStore.preferences)
                try self.ensureOutputAudioReadyLocked(instance: instance)
                self.reconnectPassword = password
                self.reconnectOptions = options
                self.appendConnectedHistoryLocked(record: record)
                self.publishSessionLocked(instance: instance, record: record)
                self.startPollingLocked()

                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.destroyLocked()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.cancelReconnectLocked()
            self.appendDisconnectedHistoryLocked()
            self.resetLocked()
            self.publishDisconnected(message: nil)
        }
    }

    func disconnectSynchronously() {
        queue.sync { [weak self] in
            self?.cancelReconnectLocked()
            self?.resetLocked()
        }
    }

    // MARK: - Instance creation

    func createInstanceLocked() throws -> UnsafeMutableRawPointer {
        guard let instance = TT_InitTeamTalkPoll() else {
            throw TeamTalkConnectionError.sdkUnavailable
        }
        return instance
    }

    // MARK: - History suppression

    func withSuppressedLoginHistoryLocked<T>(_ body: () throws -> T) rethrows -> T {
        suppressLoginHistoryDepth += 1
        defer {
            suppressLoginHistoryDepth = max(0, suppressLoginHistoryDepth - 1)
            suppressLoginHistoryUntil = max(suppressLoginHistoryUntil, Date().addingTimeInterval(1.5))
        }
        return try body()
    }

    func withSuppressedJoinHistoryLocked<T>(_ body: () throws -> T) rethrows -> T {
        suppressJoinHistoryDepth += 1
        defer {
            suppressJoinHistoryDepth = max(0, suppressJoinHistoryDepth - 1)
            suppressJoinHistoryUntil = max(suppressJoinHistoryUntil, Date().addingTimeInterval(1.5))
        }
        return try body()
    }

    var isSuppressingLoginHistoryLocked: Bool {
        suppressLoginHistoryDepth > 0 || Date() < suppressLoginHistoryUntil
    }

    var isSuppressingJoinHistoryLocked: Bool {
        suppressJoinHistoryDepth > 0 || Date() < suppressJoinHistoryUntil
    }

    var isSuppressingFileHistoryLocked: Bool {
        isSuppressingLoginHistoryLocked || isSuppressingJoinHistoryLocked
    }

    // MARK: - Reconnexion automatique

    func startReconnectTimerLocked() {
        cancelReconnectLocked()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.attemptReconnectLocked()
        }
        reconnectTimer = timer
        timer.resume()
    }

    func attemptReconnectLocked() {
        guard let record = reconnectRecord, let password = reconnectPassword else {
            cancelReconnectLocked()
            publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
            return
        }

        do {
            let instance = try createInstanceLocked()
            try withSuppressedLoginHistoryLocked {
                try connectAndLoginLocked(
                    instance: instance,
                    record: record,
                    password: password,
                    options: reconnectOptions
                )
            }

            // Success — restore state
            cancelReconnectLocked()
            self.applyDefaultSubscriptionPreferencesLocked(instance: instance, preferences: self.preferencesStore.preferences)
            try ensureOutputAudioReadyLocked(instance: instance)
            self.instance = instance
            self.connectedRecord = record

            // Rejoindre le dernier canal si possible
            let shouldRejoinLastChannel = preferencesStore.preferences.rejoinLastChannelOnReconnect
            let channelToJoin = shouldRejoinLastChannel ? lastChannelID : 0
            if channelToJoin > 0 {
                var channel = Channel()
                if TT_GetChannel(instance, channelToJoin, &channel) != 0 {
                    let pwd = channelPasswords[channelToJoin] ?? ""
                    _ = pwd.withCString { pwdPointer in
                        TT_DoJoinChannelByID(instance, channelToJoin, pwdPointer)
                    }
                } else {
                    autoJoinAfterLoginLocked(instance: instance, options: reconnectOptions)
                }
            } else {
                autoJoinAfterLoginLocked(instance: instance, options: reconnectOptions)
            }

            lastChannelID = 0
            publishSessionLocked(instance: instance, record: record)
            startPollingLocked()
        } catch {
            destroyLocked()
            // Le timer relancera une tentative dans 5 secondes
        }
    }

    func cancelReconnectLocked() {
        reconnectTimer?.setEventHandler {}
        reconnectTimer?.cancel()
        reconnectTimer = nil
        reconnectRecord = nil
        reconnectPassword = nil
        reconnectOptions = TeamTalkConnectOptions()
        lastChannelID = 0
    }

    func publishReconnecting() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.teamTalkConnectionControllerDidStartReconnecting(self)
        }
    }

    // MARK: - Auto-join

    func autoJoinAfterLoginLocked(instance: UnsafeMutableRawPointer) {
        autoJoinAfterLoginLocked(instance: instance, options: TeamTalkConnectOptions())
    }

    func autoJoinAfterLoginLocked(instance: UnsafeMutableRawPointer, options: TeamTalkConnectOptions) {
        if let initialChannelPath = options.initialChannelPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           initialChannelPath.isEmpty == false {
            let channelID = initialChannelPath.withCString { pathPointer in
                TT_GetChannelIDFromPath(instance, pathPointer)
            }
            if channelID > 0 {
                let password = options.initialChannelPassword
                channelPasswords[channelID] = password
                _ = password.withCString { pwdPointer in
                    TT_DoJoinChannelByID(instance, channelID, pwdPointer)
                }
                return
            }
        }

        if options.preferJoinLastChannelFromServer {
            if let record = connectedRecord {
                let serverKey = LastChannelStore.serverKey(host: record.host, tcpPort: record.tcpPort, username: record.username)
                if let lastPath = lastChannelStore.channelPath(forServerKey: serverKey) {
                    let channelID = lastPath.withCString { pathPointer in
                        TT_GetChannelIDFromPath(instance, pathPointer)
                    }
                    if channelID > 0 {
                        let pwd = channelPasswords[channelID] ?? ""
                        _ = pwd.withCString { pwdPointer in
                            TT_DoJoinChannelByID(instance, channelID, pwdPointer)
                        }
                        return
                    }
                }
            }
            return
        }

        // Priority 1: szInitChannel from the user account on the server
        var account = UserAccount()
        if TT_GetMyUserAccount(instance, &account) != 0 {
            let initChannel = ttString(from: account.szInitChannel)
            if initChannel.isEmpty == false {
                let channelID = initChannel.withCString { pathPointer in
                    TT_GetChannelIDFromPath(instance, pathPointer)
                }
                if channelID > 0 {
                    _ = TT_DoJoinChannelByID(instance, channelID, "")
                    return
                }
            }
        }

        // Priority 2: initial channel configured on the saved server
        let configuredChannelPath = connectedRecord?.initialChannelPath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if configuredChannelPath.isEmpty == false {
            let channelID = configuredChannelPath.withCString { pathPointer in
                TT_GetChannelIDFromPath(instance, pathPointer)
            }
            if channelID > 0 {
                let password = connectedRecord?.initialChannelPassword ?? ""
                channelPasswords[channelID] = password
                _ = password.withCString { pwdPointer in
                    TT_DoJoinChannelByID(instance, channelID, pwdPointer)
                }
                return
            }
        }

        // Priority 3: join root channel if the preference is enabled
        guard preferencesStore.preferences.autoJoinRootChannel else { return }
        let rootChannelID = TT_GetRootChannelID(instance)
        guard rootChannelID > 0 else { return }
        _ = TT_DoJoinChannelByID(instance, rootChannelID, "")
    }

    // MARK: - Connect and login

    func connectAndLoginLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        password: String,
        options: TeamTalkConnectOptions
    ) throws {
        let didStartConnection = record.host.withCString { hostPointer in
            TT_Connect(
                instance,
                hostPointer,
                INT32(record.tcpPort),
                INT32(record.udpPort),
                0,
                0,
                record.encrypted ? 1 : 0
            ) != 0
        }

        guard didStartConnection else {
            throw TeamTalkConnectionError.connectionStartFailed
        }

        let deadline = Date().addingTimeInterval(10)
        var loginCommandID: INT32 = -1

        while Date() < deadline {
            guard let message = nextMessageLocked(instance: instance, waitMSec: 250) else {
                continue
            }

            switch message.nClientEvent {
            case CLIENTEVENT_CON_SUCCESS:
                let nickname = effectiveNickname(for: record, override: options.nicknameOverride)
                loginCommandID = nickname.withCString { nicknamePointer in
                    record.username.withCString { usernamePointer in
                        password.withCString { passwordPointer in
                            clientName.withCString { clientNamePointer in
                                TT_DoLoginEx(instance, nicknamePointer, usernamePointer, passwordPointer, clientNamePointer)
                            }
                        }
                    }
                }

                if loginCommandID <= 0 {
                    throw TeamTalkConnectionError.loginStartFailed
                }

            case CLIENTEVENT_CMD_MYSELF_LOGGEDIN:
                return

            case CLIENTEVENT_CMD_ERROR:
                if loginCommandID == -1 || message.nSource == loginCommandID {
                    throw TeamTalkConnectionError.loginFailed(clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.loginFailed"))
                }

            case CLIENTEVENT_CON_CRYPT_ERROR:
                throw TeamTalkConnectionError.connectionFailed

            case CLIENTEVENT_CON_FAILED:
                throw TeamTalkConnectionError.connectionFailed

            case CLIENTEVENT_INTERNAL_ERROR:
                throw TeamTalkConnectionError.internalError(clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.internal"))

            default:
                continue
            }
        }

        throw TeamTalkConnectionError.connectionTimeout
    }

    // MARK: - Post-login options

    func applyPostLoginOptionsLocked(
        instance: UnsafeMutableRawPointer,
        options: TeamTalkConnectOptions
    ) throws {
        let statusMessage = (options.statusMessage ?? preferencesStore.preferences.defaultStatusMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let gender = options.genderOverride ?? preferencesStore.preferences.defaultGender
        let currentUser = currentUserLocked(instance: instance)
        let currentBitmask = currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue
        let mergedMode = TeamTalkStatusMode(bitmask: currentBitmask).merged(with: gender.merged(with: currentBitmask))

        guard statusMessage.isEmpty == false || mergedMode != currentBitmask else {
            return
        }

        let commandID = statusMessage.withCString { messagePointer in
            TT_DoChangeStatus(instance, mergedMode, messagePointer)
        }
        guard commandID > 0 else {
            return
        }

        try waitForCommandCompletionLocked(instance: instance, commandID: commandID)
    }

    // MARK: - Message polling

    func nextMessageLocked(
        instance: UnsafeMutableRawPointer,
        waitMSec: INT32
    ) -> TTMessage? {
        var timeout = waitMSec
        var message = TTMessage()

        guard TT_GetMessage(instance, &message, &timeout) != 0 else {
            return nil
        }

        return message
    }

    func startPollingLocked() {
        stopPollingLocked()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.drainMessagesLocked()
        }
        pollTimer = timer
        timer.resume()
    }

    func stopPollingLocked() {
        pollTimer?.setEventHandler {}
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Event loop

    func drainMessagesLocked() {
        guard let instance else {
            return
        }

        var waitMSec: INT32 = 0
        var publishInvalidation: SessionPublishInvalidation = []
        defer {
            // Poll active transfers for current progress (SDK only fires CLIENTEVENT_FILETRANSFER
            // at start/end, not during the transfer — we must poll TT_GetFileTransferInfo)
            if !activeTransferProgress.isEmpty, let _ = connectedRecord {
                for (transferID, current) in activeTransferProgress {
                    var ft = FileTransfer()
                    guard TT_GetFileTransferInfo(instance, transferID, &ft) != 0 else { continue }
                    let updated = FileTransferProgress(
                        transferID: transferID,
                        fileName: ttString(from: ft.szRemoteFileName),
                        transferred: ft.nTransferred,
                        total: ft.nFileSize,
                        isDownload: ft.bInbound != 0
                    )
                    if updated != current {
                        activeTransferProgress[transferID] = updated
                        publishInvalidation.insert(.activeTransfers)
                    }
                }
            }
            let now = CFAbsoluteTimeGetCurrent()
            if connectedRecord != nil,
               now - lastAutoAwayCheckTime >= 5.0 {
                lastAutoAwayCheckTime = now
                if updateAutoAwayIfNeededLocked(instance: instance) {
                    publishInvalidation = .all
                }
            }
            if publishInvalidation.contains(.activeTransfers),
               publishInvalidation.intersection([.rootTree, .chat, .history, .privateConversations, .channelFiles, .audio, .identity, .permissions]).isEmpty {
                publishActiveTransfersLocked(currentChannelID: TT_GetMyChannelID(instance))
            } else if !publishInvalidation.isEmpty, let connectedRecord {
                publishSessionLocked(instance: instance, record: connectedRecord, invalidation: publishInvalidation)
            }
        }

        while true {
            var message = TTMessage()
            guard TT_GetMessage(instance, &message, &waitMSec) != 0 else {
                return
            }

            switch message.nClientEvent {
            case CLIENTEVENT_CON_LOST:
                SoundPlayer.shared.play(.serverLost)
                appendConnectionLostHistoryLocked()
                let record = connectedRecord
                let password = reconnectPassword
                let lastChan = TT_GetMyChannelID(instance)
                destroyLocked()
                if preferencesStore.preferences.autoReconnect, let record, let password {
                    lastChannelID = lastChan
                    reconnectRecord = record
                    self.reconnectPassword = password
                    self.reconnectOptions = TeamTalkConnectOptions(
                        initialChannelPath: record.initialChannelPath,
                        initialChannelPassword: record.initialChannelPassword
                    )
                    startReconnectTimerLocked()
                    publishReconnecting()
                } else {
                    publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
                }
                return
            case CLIENTEVENT_CMD_MYSELF_LOGGEDOUT:
                appendConnectionLostHistoryLocked()
                destroyLocked()
                publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
                return
            case CLIENTEVENT_AUDIOINPUT:
                break
            case CLIENTEVENT_USER_AUDIOBLOCK:
                // Feed muxed audio to echo canceller as far-end reference.
                if let aec = advancedMicrophoneEngine.echoCanceller,
                   message.nSource == TT_MUXED_USERID {
                    if let block = TT_AcquireUserAudioBlock(instance, UInt32(STREAMTYPE_VOICE.rawValue), TT_MUXED_USERID) {
                        if let rawAudio = block.pointee.lpRawAudio {
                            let int16Ptr = rawAudio.assumingMemoryBound(to: Int16.self)
                            aec.feedReference(int16Ptr, count: Int(block.pointee.nSamples), channels: Int(block.pointee.nChannels), sampleRate: Int(block.pointee.nSampleRate))
                        }
                        TT_ReleaseUserAudioBlock(instance, block)
                    }
                }
            case CLIENTEVENT_CMD_MYSELF_KICKED:
                if connectedRecord != nil {
                    appendKickHistoryLocked(message, instance: instance)
                    publishInvalidation = .all
                }
            case CLIENTEVENT_CMD_USER_TEXTMSG:
                if let connectedRecord {
                    if handleTextMessageEventLocked(message.textmessage, instance: instance, record: connectedRecord) {
                        publishInvalidation.formUnion([.chat, .history, .privateConversations])
                    }
                }
            case CLIENTEVENT_CMD_FILE_NEW:
                if connectedRecord != nil {
                    if isSuppressingFileHistoryLocked == false {
                        appendFileHistoryLocked(message.remotefile, isAdded: true, instance: instance, record: connectedRecord!)
                    }
                    publishInvalidation.formUnion([.channelFiles, .history])
                }
            case CLIENTEVENT_CMD_FILE_REMOVE:
                if connectedRecord != nil {
                    if isSuppressingFileHistoryLocked == false {
                        appendFileHistoryLocked(message.remotefile, isAdded: false, instance: instance, record: connectedRecord!)
                    }
                    publishInvalidation.formUnion([.channelFiles, .history])
                }
            case CLIENTEVENT_CMD_SERVER_UPDATE:
                if connectedRecord != nil {
                    publishInvalidation = .all
                }
            case CLIENTEVENT_CMD_SERVERSTATISTICS:
                let stats = message.serverstatistics
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.teamTalkConnectionController(self, didReceiveServerStatistics: stats)
                }
            case CLIENTEVENT_FILETRANSFER:
                handleFileTransferEventLocked(message.filetransfer)
                if connectedRecord != nil {
                    publishInvalidation.insert(.activeTransfers)
                }
            case CLIENTEVENT_USER_STATECHANGE:
                if connectedRecord != nil {
                    publishAudioRuntimeUpdateLocked(instance: instance)
                }
            case CLIENTEVENT_USER_RECORD_MEDIAFILE:
                if connectedRecord != nil {
                    let status = message.mediafileinfo.nStatus
                    if status == MFS_ERROR || status == MFS_ABORTED {
                        recordingMuxedActive = false
                        publishInvalidation = .all
                    }
                }
            case CLIENTEVENT_CMD_USERACCOUNT:
                pendingUserAccounts.append(makeUserAccountProperties(from: message.useraccount))
            case CLIENTEVENT_CMD_BANNEDUSER:
                pendingBannedUsers.append(makeBannedUserProperties(from: message.banneduser))
            case CLIENTEVENT_CMD_SUCCESS:
                pendingChannelMessageCommandIDs.remove(message.nSource)
                if message.nSource == listUserAccountsCmdID {
                    let accounts = pendingUserAccounts
                    pendingUserAccounts = []
                    listUserAccountsCmdID = -1
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.teamTalkConnectionController(self, didReceiveUserAccounts: accounts)
                    }
                }
                if message.nSource == listBansCmdID {
                    let users = pendingBannedUsers
                    pendingBannedUsers = []
                    listBansCmdID = -1
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.teamTalkConnectionController(self, didReceiveBannedUsers: users)
                    }
                }
            case CLIENTEVENT_CMD_ERROR:
                if pendingChannelMessageCommandIDs.remove(message.nSource) != nil,
                   message.clienterrormsg.nErrorNo == CMDERR_NOT_AUTHORIZED.rawValue,
                   connectedRecord != nil {
                    appendTransmissionBlockedHistoryLocked()
                    publishInvalidation.insert(.history)
                }
            case CLIENTEVENT_INTERNAL_ERROR:
                if connectedRecord != nil {
                    let errorNo = message.clienterrormsg.nErrorNo
                    let errorMsg = clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.internal")
                    AudioLogger.log("INTERNAL_ERROR in session: code=%d msg=%@", errorNo, errorMsg)

                    if errorNo == INTERR_SNDOUTPUT_FAILURE.rawValue {
                        // Sound output device failed (e.g. unplugged). Reopen it.
                        AudioLogger.log("INTERNAL_ERROR: output device failure, reopening")
                        if outputAudioReady {
                            _ = TT_CloseSoundOutputDevice(instance)
                            outputAudioReady = false
                        }
                        do {
                            try ensureDirectOutputAudioReadyLocked(instance: instance)
                            if masterMuted {
                                _ = TT_SetSoundOutputMute(instance, 1)
                            }
                        } catch {
                            AudioLogger.log("INTERNAL_ERROR: failed to reopen output — %@", error.localizedDescription)
                        }
                    } else if errorNo == INTERR_TTMESSAGE_QUEUE_OVERFLOW.rawValue {
                        AudioLogger.log("INTERNAL_ERROR: message queue overflow — events may have been lost")
                    }

                    appendHistoryLocked(kind: .connectionLost, message: errorMsg)
                    publishInvalidation.insert(.history)
                }
            case CLIENTEVENT_CMD_CHANNEL_NEW,
                 CLIENTEVENT_CMD_CHANNEL_UPDATE,
                 CLIENTEVENT_CMD_CHANNEL_REMOVE,
                 CLIENTEVENT_CMD_USER_UPDATE,
                 CLIENTEVENT_CMD_USER_LOGGEDIN,
                 CLIENTEVENT_CMD_USER_LOGGEDOUT,
                 CLIENTEVENT_CMD_USER_JOINED,
                 CLIENTEVENT_CMD_USER_LEFT:
                if connectedRecord != nil {
                    let currentUserID = TT_GetMyUserID(instance)
                    switch message.nClientEvent {
                    case CLIENTEVENT_CMD_USER_LOGGEDIN:
                        if isSuppressingLoginHistoryLocked == false {
                            appendUserLoggedInHistoryLocked(message.user, currentUserID: currentUserID)
                            if message.user.nUserID != currentUserID {
                                SoundPlayer.shared.play(.loggedOn)
                            }
                        }
                        if message.user.nUserID != currentUserID {
                            applyDefaultSubscriptionPreferencesLocked(
                                instance: instance,
                                userID: message.user.nUserID,
                                preferences: preferencesStore.preferences
                            )
                            if recordingSeparateActive, let folder = recordingFolder {
                                folder.path.withCString { cPath in
                                    _ = TT_SetUserMediaStorageDirEx(instance, message.user.nUserID, cPath, nil, recordingFormat, 1000)
                                }
                            }
                        }
                    case CLIENTEVENT_CMD_USER_LOGGEDOUT:
                        appendUserLoggedOutHistoryLocked(message.user, currentUserID: currentUserID)
                        if message.user.nUserID != currentUserID {
                            SoundPlayer.shared.play(.loggedOff)
                        }
                    case CLIENTEVENT_CMD_USER_JOINED:
                        if isSuppressingLoginHistoryLocked == false {
                            appendUserJoinedChannelHistoryLocked(message.user, currentUserID: currentUserID, instance: instance)
                            if message.user.nUserID != currentUserID,
                               message.user.nChannelID == TT_GetMyChannelID(instance) {
                                SoundPlayer.shared.play(.newUser)
                            }
                        }
                        if message.user.nUserID == currentUserID,
                           !voiceTransmissionEnabled,
                           preferencesStore.preferences.lastVoiceTransmissionEnabled,
                           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                            do {
                                try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                                voiceTransmissionEnabled = true
                                SoundPlayer.shared.play(.voxMeEnable)
                                if let connectedRecord {
                                    publishSessionLocked(instance: instance, record: connectedRecord)
                                }
                            } catch {}
                        }
                        let joinedUsername = ttString(from: message.user.szUsername)
                        if let storedVolume = userVolumeStore.volume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_VOICE, storedVolume)
                        }
                        if let storedBalance = userVolumeStore.stereoBalance(forUsername: joinedUsername) {
                            _ = TT_SetUserStereo(instance, message.user.nUserID, STREAMTYPE_VOICE, storedBalance.left ? 1 : 0, storedBalance.right ? 1 : 0)
                        }
                        applyJitterControlLocked(instance: instance, userID: message.user.nUserID)
                    case CLIENTEVENT_CMD_USER_LEFT:
                        if isSuppressingJoinHistoryLocked == false {
                            appendUserLeftChannelHistoryLocked(message.user, currentUserID: currentUserID, instance: instance)
                        }
                        if message.user.nUserID != currentUserID {
                            let myChannel = TT_GetMyChannelID(instance)
                            if message.user.nChannelID == myChannel || message.user.nChannelID == 0 {
                                SoundPlayer.shared.play(.removeUser)
                            }
                        }
                    case CLIENTEVENT_CMD_USER_UPDATE:
                        appendSubscriptionHistoryIfNeededLocked(message.user)
                    default:
                        break
                    }
                    if voiceTransmissionEnabled,
                       isAnyMicrophoneEngineRunning,
                       message.user.nUserID == currentUserID {
                        refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
                    }
                    publishInvalidation = .all
                }
            default:
                continue
            }
        }
    }

    // MARK: - Teardown

    func resetLocked() {
        destroyLocked()
    }

    func destroyLocked() {
        stopPollingLocked()

        if let instance {
            if isAnyMicrophoneEngineRunning || inputAudioReady {
                stopAdvancedMicrophoneInputLocked(instance: instance, reason: "destroyLocked")
            }
            if recordingMuxedActive {
                _ = TT_StopRecordingMuxedAudioFile(instance)
            }
            if teamTalkVirtualInputReady {
                _ = TT_CloseSoundInputDevice(instance)
                teamTalkVirtualInputReady = false
            }
            if outputAudioReady {
                _ = TT_CloseSoundOutputDevice(instance)
            }
            TT_Disconnect(instance)
            TT_CloseTeamTalk(instance)
        }

        recordingMuxedActive = false
        recordingSeparateActive = false
        recordingFolder = nil

        instance = nil
        connectedRecord = nil
        channelChatHistory = []
        sessionHistory = []
        activeTransferProgress = [:]
        lastBuiltSessionSnapshot = nil
        pendingTextMessages.removeAll()
        pendingChannelMessageCommandIDs.removeAll()
        observedSubscriptionStates.removeAll()
        suppressLoginHistoryUntil = .distantPast
        suppressJoinHistoryUntil = .distantPast
        channelPasswords.removeAll()
        privateConversations.removeAll()
        selectedPrivateConversationUserID = nil
        visiblePrivateConversationUserID = nil
        isPrivateMessagesWindowVisible = false
        outputAudioReady = false
        inputAudioReady = false
        voiceTransmissionEnabled = false
        masterMuted = false
        hearMyselfEnabled = false
        teamTalkVirtualInputReady = false
        advancedMicrophoneTargetFormat = nil
        isAutoAwayActive = false
        autoAwayRestoreStatusMessage = ""
    }

    // MARK: - Error helpers

    func clientErrorMessage(from message: TTMessage) -> String? {
        guard message.ttType == __CLIENTERRORMSG else {
            return nil
        }

        let value = ttString(from: message.clienterrormsg.szErrorMsg)
        if !value.isEmpty { return value }

        // Fall back to SDK error description.
        let errorNo = message.clienterrormsg.nErrorNo
        guard errorNo != 0 else { return nil }
        var buf = [TTCHAR](repeating: 0, count: Int(TT_STRLEN))
        TT_GetErrorMessage(errorNo, &buf)
        let sdkMessage = String(cString: buf)
        return sdkMessage.isEmpty ? nil : sdkMessage
    }

    // MARK: - Command completion

    func waitForCommandCompletionLocked(
        instance: UnsafeMutableRawPointer,
        commandID: Int32
    ) throws {
        let deadline = Date().addingTimeInterval(10)

        while Date() < deadline {
            guard let message = nextMessageLocked(instance: instance, waitMSec: 250) else {
                continue
            }

            switch message.nClientEvent {
            case CLIENTEVENT_CMD_SUCCESS:
                pendingChannelMessageCommandIDs.remove(message.nSource)
                if message.nSource == commandID {
                    return
                }
            case CLIENTEVENT_CMD_ERROR:
                if pendingChannelMessageCommandIDs.remove(message.nSource) != nil,
                   message.clienterrormsg.nErrorNo == CMDERR_NOT_AUTHORIZED.rawValue,
                   let connectedRecord {
                    appendTransmissionBlockedHistoryLocked()
                    publishSessionLocked(instance: instance, record: connectedRecord)
                }
                if message.nSource == commandID {
                    let errorNumber = message.clienterrormsg.nErrorNo
                    if errorNumber == CMDERR_INCORRECT_CHANNEL_PASSWORD.rawValue {
                        throw TeamTalkConnectionError.incorrectChannelPassword(
                            clientErrorMessage(from: message) ?? L10n.text("connectedServer.channelPassword.error.incorrect")
                        )
                    }
                    throw TeamTalkConnectionError.loginFailed(
                        clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.internal")
                    )
                }
            case CLIENTEVENT_CON_LOST, CLIENTEVENT_CMD_MYSELF_LOGGEDOUT:
                appendConnectionLostHistoryLocked()
                destroyLocked()
                publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
                throw TeamTalkConnectionError.connectionFailed
            case CLIENTEVENT_CMD_MYSELF_KICKED:
                if let connectedRecord {
                    appendKickHistoryLocked(message, instance: instance)
                    publishSessionLocked(instance: instance, record: connectedRecord)
                }
            case CLIENTEVENT_CMD_FILE_NEW:
                if let connectedRecord {
                    if isSuppressingFileHistoryLocked == false {
                        appendFileHistoryLocked(message.remotefile, isAdded: true, instance: instance, record: connectedRecord)
                    }
                    publishSessionLocked(instance: instance, record: connectedRecord)
                }
            case CLIENTEVENT_CMD_FILE_REMOVE:
                if let connectedRecord {
                    if isSuppressingFileHistoryLocked == false {
                        appendFileHistoryLocked(message.remotefile, isAdded: false, instance: instance, record: connectedRecord)
                    }
                    publishSessionLocked(instance: instance, record: connectedRecord)
                }
            case CLIENTEVENT_CMD_CHANNEL_NEW,
                 CLIENTEVENT_CMD_CHANNEL_UPDATE,
                 CLIENTEVENT_CMD_CHANNEL_REMOVE,
                 CLIENTEVENT_CMD_USER_UPDATE,
                 CLIENTEVENT_CMD_USER_LOGGEDIN,
                 CLIENTEVENT_CMD_USER_LOGGEDOUT,
                 CLIENTEVENT_CMD_USER_JOINED,
                 CLIENTEVENT_CMD_USER_LEFT:
                if let connectedRecord {
                    let currentUserID = TT_GetMyUserID(instance)
                    switch message.nClientEvent {
                    case CLIENTEVENT_CMD_USER_LOGGEDIN:
                        if isSuppressingLoginHistoryLocked == false {
                            appendUserLoggedInHistoryLocked(message.user, currentUserID: currentUserID)
                        }
                        if message.user.nUserID != currentUserID {
                            applyDefaultSubscriptionPreferencesLocked(
                                instance: instance,
                                userID: message.user.nUserID,
                                preferences: preferencesStore.preferences
                            )
                            if recordingSeparateActive, let folder = recordingFolder {
                                folder.path.withCString { cPath in
                                    _ = TT_SetUserMediaStorageDirEx(instance, message.user.nUserID, cPath, nil, recordingFormat, 1000)
                                }
                            }
                        }
                    case CLIENTEVENT_CMD_USER_LOGGEDOUT:
                        appendUserLoggedOutHistoryLocked(message.user, currentUserID: currentUserID)
                    case CLIENTEVENT_CMD_USER_JOINED:
                        if isSuppressingLoginHistoryLocked == false {
                            appendUserJoinedChannelHistoryLocked(message.user, currentUserID: currentUserID, instance: instance)
                        }
                        if message.user.nUserID == currentUserID {
                            if !voiceTransmissionEnabled,
                               preferencesStore.preferences.lastVoiceTransmissionEnabled,
                               AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                                do {
                                    try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                                    voiceTransmissionEnabled = true
                                    SoundPlayer.shared.play(.voxMeEnable)
                                } catch {}
                            }
                            if recordingMuxedActive {
                                restartMuxedRecordingForChannelChange()
                            }
                        }
                        let joinedUsername = ttString(from: message.user.szUsername)
                        if let storedVolume = userVolumeStore.volume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_VOICE, storedVolume)
                        }
                        if let storedBalance = userVolumeStore.stereoBalance(forUsername: joinedUsername) {
                            _ = TT_SetUserStereo(instance, message.user.nUserID, STREAMTYPE_VOICE, storedBalance.left ? 1 : 0, storedBalance.right ? 1 : 0)
                        }
                        applyJitterControlLocked(instance: instance, userID: message.user.nUserID)
                    case CLIENTEVENT_CMD_USER_UPDATE:
                        appendSubscriptionHistoryIfNeededLocked(message.user)
                    case CLIENTEVENT_CMD_USER_LEFT:
                        if isSuppressingJoinHistoryLocked == false {
                            appendUserLeftChannelHistoryLocked(message.user, currentUserID: currentUserID, instance: instance)
                        }
                    default:
                        break
                    }
                    publishSessionLocked(instance: instance, record: connectedRecord)
                }
            case CLIENTEVENT_CMD_USER_TEXTMSG:
                if let connectedRecord {
                    if handleTextMessageEventLocked(message.textmessage, instance: instance, record: connectedRecord) {
                        publishSessionLocked(instance: instance, record: connectedRecord)
                    }
                }
            case CLIENTEVENT_INTERNAL_ERROR:
                throw TeamTalkConnectionError.internalError(
                    clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.internal")
                )
            default:
                continue
            }
        }

        throw TeamTalkConnectionError.connectionTimeout
    }
}
