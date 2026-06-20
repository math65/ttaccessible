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
                AudioLogger.log("connect: begin")
                self.resetLocked()
                AudioLogger.log("connect: creating instance")
                let instance = try self.createInstanceLocked()
                AudioLogger.log("connect: instance created — connecting + logging in")
                try self.withSuppressedLoginHistoryLocked {
                    try self.connectAndLoginLocked(
                        instance: instance,
                        record: record,
                        password: password,
                        options: options
                    )
                }
                AudioLogger.log("connect: logged in — auto-joining channel")
                self.instance = instance
                self.connectedRecord = record
                self.autoJoinAfterLoginLocked(instance: instance, options: options)
                AudioLogger.log("connect: joined — applying post-login options")
                try self.applyPostLoginOptionsLocked(instance: instance, options: options)
                self.applyDefaultSubscriptionPreferencesLocked(instance: instance, preferences: self.preferencesStore.preferences)
                AudioLogger.log("connect: readying output audio")
                try self.ensureOutputAudioReadyLocked(instance: instance)
                AudioLogger.log("connect: output ready — connect complete")
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
            // No prewarm needed here — destroyLocked kept the warm instance in
            // `reusableInstance`, so the next connect reuses it directly.
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
        // Reuse a warm instance kept from a previous connection — it's already past
        // the SDK's ~8 s device enumeration, so this connect is ~1 s instead of cold.
        if let reusable = reusableInstance {
            reusableInstance = nil
            AudioLogger.log("connect: reusing warm instance")
            return reusable
        }
        // Reuse a background-prewarmed instance if one is ready or in flight — this
        // is what keeps the ~12 s TT_InitTeamTalkPoll device-enumeration off the
        // connect path. If a prewarm is in flight, wait for it (the probe queue
        // signals the semaphore directly, so blocking `queue` here can't deadlock).
        if prewarmInFlight {
            AudioLogger.log("connect: waiting for prewarmed instance")
            prewarmReady.wait()
            prewarmInFlight = false
            prewarmBoxLock.lock()
            let prewarmed = prewarmBoxedInstance
            prewarmBoxedInstance = nil
            prewarmBoxLock.unlock()
            if let prewarmed {
                AudioLogger.log("connect: using prewarmed instance")
                return prewarmed
            }
        }
        guard let instance = TT_InitTeamTalkPoll() else {
            throw TeamTalkConnectionError.sdkUnavailable
        }
        return instance
    }

    /// Create the next TeamTalk instance ahead of time on the probe queue so the
    /// SDK's ~12 s device-enumeration init never lands on the connect path. Safe to
    /// call repeatedly; no-ops while connected, already prewarmed, or in flight.
    func prewarmConnection() {
        queue.async { [weak self] in
            guard let self,
                  self.instance == nil,
                  self.reusableInstance == nil,
                  self.prewarmInFlight == false else { return }
            // Already have a boxed instance from a previous prewarm? Then we're ready.
            self.prewarmBoxLock.lock()
            let alreadyBoxed = self.prewarmBoxedInstance != nil
            self.prewarmBoxLock.unlock()
            if alreadyBoxed { return }

            self.prewarmInFlight = true
            AudioLogger.log("prewarm: creating instance in background")
            self.soundDeviceProbeQueue.async { [weak self] in
                let inst = TT_InitTeamTalkPoll()
                guard let self else {
                    if let inst { TT_CloseTeamTalk(inst) }
                    return
                }
                self.prewarmBoxLock.lock()
                self.prewarmBoxedInstance = inst
                self.prewarmBoxLock.unlock()
                self.prewarmReady.signal()
                AudioLogger.log("prewarm: instance ready")
            }
        }
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

        // Poll at 10 ms (was 100 ms). The SDK delivers muxed playback audio blocks
        // (~one per codec tx-interval, e.g. 20 ms) only through this message queue;
        // a 100 ms poll drained ~5 blocks at once then starved the output render
        // engine for the rest of the cycle, causing underrun crackle. A 10 ms poll
        // delivers blocks smoothly as they're produced so a small jitter buffer
        // suffices (no added latency). Drains are cheap no-ops when the queue is empty.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(4))
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
            // Reconcile per-user audio events when channel membership changed, then
            // top up the output mixer's ring for this tick.
            if outputAudioReady, perUserAudioNeedsRefresh {
                // Audio mixing now runs on the engine's own timer (engineQueue); the
                // message loop only reconciles which per-user events are enabled.
                refreshPerUserAudioEventsLocked(instance: instance)
            }
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
            let autoAwayPollInterval = isAutoAwayActive ? 0.5 : 5.0
            if connectedRecord != nil,
               now - lastAutoAwayCheckTime >= autoAwayPollInterval {
                lastAutoAwayCheckTime = now
                if updateAutoAwayIfNeededLocked(instance: instance) {
                    publishInvalidation = .all
                }
            }
            // Coalesce the expensive full-session publish. The message poll is fast
            // (20 ms) so per-user audio blocks arrive smoothly, but rebuilding the
            // whole channel/user tree every tick during the connect flood made
            // connecting slow. Accumulate invalidations and rebuild at most ~every
            // 80 ms (the old ~100 ms cadence) — pending changes still flush within a
            // few ticks since the timer fires regardless of message traffic. The
            // lightweight transfer-progress publish stays immediate.
            let heavyBits: SessionPublishInvalidation = [.rootTree, .chat, .history, .privateConversations, .channelFiles, .audio, .identity, .permissions]
            pendingPublishInvalidation.formUnion(publishInvalidation)
            if pendingPublishInvalidation.contains(.activeTransfers),
               pendingPublishInvalidation.intersection(heavyBits).isEmpty {
                publishActiveTransfersLocked(currentChannelID: TT_GetMyChannelID(instance))
                pendingPublishInvalidation = []
            } else if !pendingPublishInvalidation.isEmpty, let connectedRecord,
                      now - lastSnapshotPublishAt >= 0.08 {
                publishSessionLocked(instance: instance, record: connectedRecord, invalidation: pendingPublishInvalidation)
                pendingPublishInvalidation = []
                lastSnapshotPublishAt = now
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
                // Per-user remote audio → our mixer (playback); muxed → AEC reference.
                handleAudioBlockLocked(instance: instance, source: message.nSource)
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
                publishInvalidation.formUnion(handleFileTransferEventLocked(message.filetransfer))
                if connectedRecord != nil {
                    publishInvalidation.insert(.activeTransfers)
                }
            case CLIENTEVENT_USER_STATECHANGE:
                if connectedRecord != nil {
                    publishAudioRuntimeUpdateLocked(instance: instance)
                }
            case CLIENTEVENT_USER_MEDIAFILE_VIDEO:
                if connectedRecord != nil {
                    handleUserMediaFileVideoEventLocked(userID: message.nSource)
                }
            case CLIENTEVENT_USER_RECORD_MEDIAFILE:
                if connectedRecord != nil {
                    let status = message.mediafileinfo.nStatus
                    if status == MFS_ERROR || status == MFS_ABORTED {
                        recordingMuxedActive = false
                        publishInvalidation = .all
                    }
                }
            case CLIENTEVENT_STREAM_MEDIAFILE:
                if connectedRecord != nil {
                    let info = message.mediafileinfo
                    let status = info.nStatus
                    switch status {
                    case MFS_STARTED:
                        if info.uDurationMSec > 0 {
                            mediaStreamingDurationMSec = info.uDurationMSec
                        }
                        if let fileName = mediaStreamingFileName, !mediaStreamingStartedHistoryLogged {
                            appendMediaStreamingStartedHistoryLocked(fileName: fileName)
                            mediaStreamingStartedHistoryLogged = true
                            publishInvalidation.insert(.history)
                        }
                        updateMediaStreamingProgressLocked(elapsedMSec: info.uElapsedMSec, durationMSec: info.uDurationMSec)
                    case MFS_PAUSED:
                        if !mediaStreamingRestartInFlight {
                            mediaStreamingUserPauseIntent = false
                            mediaStreamingPaused = true
                            updateMediaStreamingProgressLocked(elapsedMSec: info.uElapsedMSec, durationMSec: info.uDurationMSec)
                        }
                    case MFS_PLAYING:
                        if !mediaStreamingRestartInFlight, !mediaStreamingUserPauseIntent {
                            mediaStreamingPaused = false
                            updateMediaStreamingProgressLocked(elapsedMSec: info.uElapsedMSec, durationMSec: info.uDurationMSec)
                        }
                    case MFS_FINISHED, MFS_ABORTED, MFS_CLOSED:
                        if shouldIgnoreMediaStreamingFinalizeLocked(info: info) {
                            break
                        }
                        finalizeMediaStreamingLocked(instance: instance, reason: .finished)
                    case MFS_ERROR:
                        finalizeMediaStreamingLocked(instance: instance, reason: .error)
                    default:
                        break
                    }
                }
            case CLIENTEVENT_CMD_USERACCOUNT:
                pendingUserAccounts.append(makeUserAccountProperties(from: message.useraccount))
            case CLIENTEVENT_CMD_BANNEDUSER:
                pendingBannedUsers.append(makeBannedUserProperties(from: message.banneduser))
            case CLIENTEVENT_CMD_SUCCESS:
                pendingChannelMessageCommandIDs.remove(message.nSource)
                publishInvalidation.formUnion(handleFileTransferCommandSuccessLocked(commandID: message.nSource))
                if message.nSource == listUserAccountsCmdID {
                    let accounts = pendingUserAccounts
                    cachedUserAccounts = accounts
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
                publishInvalidation.formUnion(handleFileTransferCommandErrorLocked(message))
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
                            teardownOutputRenderLocked(instance: instance)
                            _ = TT_CloseSoundOutputDevice(instance)
                            outputAudioReady = false
                        }
                        do {
                            // Reopens the virtual output + muxed event; the render
                            // engine restarts on the next muxed block (mute/gain
                            // are reapplied from prefs inside the ensure path).
                            try ensureDirectOutputAudioReadyLocked(instance: instance)
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
                    // Channel membership may have changed → reconcile per-user audio.
                    perUserAudioNeedsRefresh = true
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
                            } catch {
                                AudioLogger.log(
                                    "auto-restore mic on join failed: %@",
                                    error.localizedDescription
                                )
                            }
                        }
                        let joinedUsername = ttString(from: message.user.szUsername)
                        if let storedVolume = userVolumeStore.volume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_VOICE, storedVolume)
                        }
                        if let storedMediaFileVolume = userVolumeStore.mediaFileVolume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_MEDIAFILE_AUDIO, storedMediaFileVolume)
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
            cleanupVideoLocked()
            if mediaStreamingActive {
                _ = TT_StopStreamingMediaFileToChannel(instance)
            }
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
                teardownOutputRenderLocked(instance: instance)
                _ = TT_CloseSoundOutputDevice(instance)
            }
            TT_Disconnect(instance)
            // Keep the instance alive and WARM for reuse instead of closing it.
            // TT_CloseTeamTalk would force the next connect to recreate the instance
            // and re-run the SDK's ~8 s device enumeration; reuse keeps reconnects
            // ~1 s. (Also avoids the documented TT_CloseTeamTalk-at-exit crash.)
            reusableInstance = instance
        }

        mediaStreamingSecurityScopedURL?.stopAccessingSecurityScopedResource()
        mediaStreamingSecurityScopedURL = nil
        mediaStreamingActive = false
        mediaStreamingPath = nil
        mediaStreamingStartedHistoryLogged = false
        mediaStreamingSeekedWhilePaused = false
        mediaStreamingFileName = nil
        mediaStreamingRestartInFlight = false
        mediaStreamingUserPauseIntent = false
        mediaStreamingPaused = false
        mediaStreamingDurationMSec = 0
        mediaStreamingElapsedMSec = 0
        mediaStreamingElapsedSampleAt = nil
        mediaStreamingBroadcastGainLevel = INT32(SOUND_GAIN_DEFAULT.rawValue)
        mediaStreamingHasVideo = false
        mediaStreamingActiveVideoCodec = VideoCodec()
        mediaStreamingFinalizeSuppressedUntil = nil
        mediaStreamingResumeAnchorMSec = nil
        mediaStreamingResumeAnchorUntil = nil
        activeVideoDisplayUserID = 0
        usersWithPendingMediaVideoFrame.removeAll()
        publishMediaStreamingProgressLocked()
        recordingMuxedActive = false
        recordingSeparateActive = false
        recordingFolder = nil

        instance = nil
        connectedRecord = nil
        channelChatHistory = []
        sessionHistory = []
        activeTransferProgress = [:]
        pendingFileTransferCommands.removeAll()
        fileTransferCommandIDsByTransferID.removeAll()
        securityScopedFileTransferURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedFileTransferURLs.removeAll()
        lastBuiltSessionSnapshot = nil
        pendingTextMessages.removeAll()
        pendingChannelMessageCommandIDs.removeAll()
        observedSubscriptionStates.removeAll()
        suppressLoginHistoryUntil = .distantPast
        suppressJoinHistoryUntil = .distantPast
        channelPasswords.removeAll()
        pendingUserAccounts.removeAll()
        cachedUserAccounts.removeAll()
        listUserAccountsCmdID = -1
        privateConversations.removeAll()
        selectedPrivateConversationUserID = nil
        visiblePrivateConversationUserID = nil
        isPrivateMessagesWindowVisible = false
        outputRenderEngine.stop()
        perUserAudioEnabled.removeAll()
        perUserAudioNeedsRefresh = false
        pendingPublishInvalidation = []
        lastSnapshotPublishAt = 0
        outputAudioReady = false
        inputAudioReady = false
        voiceTransmissionEnabled = false
        masterMuted = false
        hearMyselfEnabled = false
        previewMonitorEnabled = false
        teamTalkVirtualInputReady = false
        advancedMicrophoneTargetFormat = nil
        isAutoAwayActive = false
        autoAwayActivationTime = nil
        autoAwayRestoreStatusMessage = ""
        autoAwayPeakIdleSeconds = nil
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
                let fileInvalidation = handleFileTransferCommandSuccessLocked(commandID: message.nSource)
                if !fileInvalidation.isEmpty, let connectedRecord {
                    publishSessionLocked(instance: instance, record: connectedRecord, invalidation: fileInvalidation)
                }
                if message.nSource == commandID {
                    return
                }
            case CLIENTEVENT_CMD_ERROR:
                let fileInvalidation = handleFileTransferCommandErrorLocked(message)
                if !fileInvalidation.isEmpty, let connectedRecord {
                    publishSessionLocked(instance: instance, record: connectedRecord, invalidation: fileInvalidation)
                }
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
                    // Channel membership may have changed → reconcile per-user audio.
                    perUserAudioNeedsRefresh = true
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
                                } catch {
                                    AudioLogger.log(
                                        "auto-restore mic on channel join failed: %@",
                                        error.localizedDescription
                                    )
                                }
                            }
                            if recordingMuxedActive {
                                restartMuxedRecordingForChannelChange()
                            }
                        }
                        let joinedUsername = ttString(from: message.user.szUsername)
                        if let storedVolume = userVolumeStore.volume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_VOICE, storedVolume)
                        }
                        if let storedMediaFileVolume = userVolumeStore.mediaFileVolume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_MEDIAFILE_AUDIO, storedMediaFileVolume)
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
            case CLIENTEVENT_FILETRANSFER:
                let fileInvalidation = handleFileTransferEventLocked(message.filetransfer)
                if !fileInvalidation.isEmpty, let connectedRecord {
                    if fileInvalidation.contains(.activeTransfers),
                       fileInvalidation.intersection([.rootTree, .chat, .history, .privateConversations, .channelFiles, .audio, .identity, .permissions]).isEmpty {
                        publishActiveTransfersLocked(currentChannelID: TT_GetMyChannelID(instance))
                    } else {
                        publishSessionLocked(instance: instance, record: connectedRecord, invalidation: fileInvalidation)
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
