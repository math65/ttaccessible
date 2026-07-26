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
                // A reconnect armed for a PREVIOUS server must not survive a
                // deliberate connect elsewhere: its timer would otherwise fire
                // mid-session and either tear down this live instance (on
                // failure) or overwrite this session with the old server's.
                self.cancelReconnectLocked()
                self.justKickedAt = nil
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
                self.userVolumeStore.setServerScope(Self.serverVolumeScope(for: record))
                self.userVolumeStore.setMemoryMode(self.preferencesStore.preferences.userVolumeMemoryMode)
                // Must precede the auto-join: it resolves the stored channel
                // paths into IDs, and the auto-join looks a password up by ID.
                self.refreshSavedChannelPasswordIDsLocked(instance: instance)
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
            return reusable
        }
        // Reuse a background-prewarmed instance if one is ready or in flight — this
        // is what keeps the ~12 s TT_InitTeamTalkPoll device-enumeration off the
        // connect path. If a prewarm is in flight, wait for it (the probe queue
        // signals the semaphore directly, so blocking `queue` here can't deadlock).
        if prewarmInFlight {
            prewarmReady.wait()
            prewarmInFlight = false
            prewarmBoxLock.lock()
            let prewarmed = prewarmBoxedInstance
            prewarmBoxedInstance = nil
            prewarmBoxLock.unlock()
            if let prewarmed {
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

    /// Delay before each successive attempt. A server restart is usually back
    /// within seconds, so the first retries are quick; a longer outage spaces
    /// them out instead of hammering the host. Running off the end gives up and
    /// tells the user the connection is lost.
    static let reconnectBackoffSeconds: [Int] = [5, 10, 30, 60, 60, 60, 60, 60]

    /// Handle a server-initiated connection drop from any message loop, honoring
    /// the `autoReconnect` preference. A drop can surface as `CON_LOST` (ping
    /// timeout / TCP drop) or, when a server shuts down or restarts, as a
    /// server-forced `MYSELF_LOGGEDOUT` — the app never calls `TT_DoLogout`, so a
    /// logout event is always the server dropping us, never a deliberate local
    /// logout. (An admin kick/ban arrives as `MYSELF_KICKED`, which marks the
    /// logout that follows it as expected.) Centralizes what used to be three
    /// divergent paths, two of which booted the user unconditionally regardless
    /// of the preference.
    ///
    /// Returns whether a reconnect was armed — callers on the command path use
    /// it to decide whether the failure still deserves an error dialog.
    @discardableResult
    func handleServerDropLocked(instance: UnsafeMutableRawPointer, reason: String) -> Bool {
        // A server-side kick or ban lands as MYSELF_KICKED and *then* a
        // MYSELF_LOGGEDOUT. Treating that logout as a drop would silently
        // rejoin a kicked user seconds later, and make a banned one retry
        // forever. The reference client draws the same line: it arms its
        // reconnect timer on CON_LOST only, never on LOGGEDOUT.
        let wasKicked = justKickedAt.map { Date().timeIntervalSince($0) < 5 } ?? false
        let willReconnect = preferencesStore.preferences.autoReconnect && !wasKicked
        AudioLogger.log("Connection drop (%@): autoReconnect=%d kicked=%d",
                        reason, willReconnect ? 1 : 0, wasKicked ? 1 : 0)
        SoundPlayer.shared.play(.serverLost)
        appendConnectionLostHistoryLocked()

        // Capture everything the reconnect needs BEFORE destroyLocked() wipes it.
        // On the LOGGEDOUT path the SDK has already cleared its own channel
        // state, so TT_GetMyChannelID returns 0 — fall back to what the last
        // session publish recorded while the channel was still valid.
        let record = connectedRecord
        let password = reconnectPassword
        let liveChannelID = TT_GetMyChannelID(instance)
        let lastChan = liveChannelID > 0 ? liveChannelID : lastKnownChannelID
        let lastChanPath = liveChannelID > 0
            ? channelPathLocked(instance: instance, channelID: liveChannelID)
            : lastKnownChannelPath
        let lastChanPassword = channelPasswords[lastChan] ?? ""
        destroyLocked()

        guard willReconnect, let record, let password else {
            publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
            return false
        }

        // Remember where we were by PATH (survives an ID-reassigning restart);
        // keep the ID + password as a fallback for a same-process blip.
        lastChannelID = lastChan
        lastChannelPath = lastChanPath
        lastChannelPassword = lastChanPassword
        reconnectRecord = record
        self.reconnectPassword = password
        self.reconnectOptions = TeamTalkConnectOptions(
            initialChannelPath: record.initialChannelPath,
            initialChannelPassword: record.initialChannelPassword
        )
        reconnectAttempt = 0
        scheduleNextReconnectAttemptLocked()
        publishReconnecting()
        return true
    }

    /// Arm a ONE-SHOT timer for the next attempt. One-shot rather than
    /// repeating because `connectAndLoginLocked` can block this serial queue
    /// for ~10 s against a black-holed host: a repeating timer would fire
    /// back-to-back attempts with no gap between them, and could keep
    /// `disconnectSynchronously()` (a `queue.sync` from the main thread)
    /// waiting that long.
    func scheduleNextReconnectAttemptLocked() {
        stopReconnectTimerLocked()

        guard reconnectAttempt < Self.reconnectBackoffSeconds.count else {
            AudioLogger.log("Reconnect: giving up after %d attempts", reconnectAttempt)
            cancelReconnectLocked()
            publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
            return
        }

        let delay = Self.reconnectBackoffSeconds[reconnectAttempt]
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(delay))
        timer.setEventHandler { [weak self] in
            self?.attemptReconnectLocked()
        }
        reconnectTimer = timer
        timer.resume()
        AudioLogger.log("Reconnect: next attempt in %ds", delay)
    }

    /// Tear down the retry timer WITHOUT touching the stored credentials and
    /// rejoin target. Splitting this out of `cancelReconnectLocked` is what lets
    /// the attempt path re-arm itself, and lets the success path defer clearing
    /// state until after it has used it.
    func stopReconnectTimerLocked() {
        reconnectTimer?.setEventHandler {}
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    func attemptReconnectLocked() {
        stopReconnectTimerLocked()
        guard let record = reconnectRecord, let password = reconnectPassword else {
            AudioLogger.log("Reconnect: no stored credentials, giving up")
            cancelReconnectLocked()
            publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
            return
        }

        reconnectAttempt += 1
        let options = reconnectOptions
        let shouldRejoinLastChannel = preferencesStore.preferences.rejoinLastChannelOnReconnect

        AudioLogger.log("Reconnect attempt %d to %@…", reconnectAttempt, record.host)
        var newInstance: UnsafeMutableRawPointer?
        do {
            let instance = try createInstanceLocked()
            newInstance = instance
            try withSuppressedLoginHistoryLocked {
                try connectAndLoginLocked(
                    instance: instance,
                    record: record,
                    password: password,
                    options: options
                )
            }

            // Success — restore state. The reconnect state is deliberately NOT
            // cleared yet: the rejoin below reads it, and clearing early also
            // meant a throw from ensureOutputAudioReadyLocked (output device
            // gone during the outage) left the UI stuck on "reconnecting…"
            // forever, with the timer and credentials already gone.
            applyDefaultSubscriptionPreferencesLocked(instance: instance, preferences: preferencesStore.preferences)
            try ensureOutputAudioReadyLocked(instance: instance)
            self.instance = instance
            self.connectedRecord = record
            self.userVolumeStore.setServerScope(Self.serverVolumeScope(for: record))
            self.userVolumeStore.setMemoryMode(self.preferencesStore.preferences.userVolumeMemoryMode)
            // Before the rejoin below: it resolves stored channel paths to IDs,
            // and the rejoin looks a channel password up by ID.
            refreshSavedChannelPasswordIDsLocked(instance: instance)

            // Rejoin the channel we were in, by path (survives a restart that
            // reassigns IDs); fall back to the server's normal auto-join.
            if !(shouldRejoinLastChannel && rejoinLastChannelLocked(
                instance: instance,
                path: lastChannelPath,
                password: lastChannelPassword,
                channelID: lastChannelID
            )) {
                autoJoinAfterLoginLocked(instance: instance, options: options)
            }

            cancelReconnectLocked()
            // Re-arm for a FUTURE drop. cancelReconnectLocked clears the stored
            // credentials and connect() is otherwise their only setter, so
            // without this the whole feature works exactly once per session:
            // the second drop finds no password and boots the user.
            reconnectPassword = password
            reconnectOptions = options
            publishSessionLocked(instance: instance, record: record)
            startPollingLocked()
            AudioLogger.log("Reconnect succeeded")
        } catch {
            // destroyLocked() only tears down self.instance, which is still nil
            // on this path — close the instance this attempt created, or every
            // retry orphans a full SDK instance with its threads and socket.
            if let newInstance, newInstance != self.instance {
                TT_Disconnect(newInstance)
                TT_CloseTeamTalk(newInstance)
            }
            destroyLocked()
            scheduleNextReconnectAttemptLocked()
        }
    }

    func cancelReconnectLocked() {
        stopReconnectTimerLocked()
        reconnectAttempt = 0
        reconnectRecord = nil
        reconnectPassword = nil
        reconnectOptions = TeamTalkConnectOptions()
        lastChannelID = 0
        lastChannelPath = ""
        lastChannelPassword = ""
    }

    /// Rejoin the channel we were in before the drop. Resolves the remembered
    /// PATH to the (possibly reassigned) channel ID on the reconnected server;
    /// falls back to the numeric ID for a same-process blip where it's unchanged.
    /// Returns whether a join was issued.
    func rejoinLastChannelLocked(
        instance: UnsafeMutableRawPointer,
        path: String,
        password: String,
        channelID lastID: Int32
    ) -> Bool {
        if !path.isEmpty {
            let channelID = path.withCString { TT_GetChannelIDFromPath(instance, $0) }
            if channelID > 0 {
                channelPasswords[channelID] = password
                _ = password.withCString { TT_DoJoinChannelByID(instance, channelID, $0) }
                AudioLogger.log("Reconnect: rejoining channel by path %@", path)
                return true
            }
            AudioLogger.log("Reconnect: path %@ not found on server, falling back", path)
        }
        // Numeric fallback, for a same-process blip where IDs are unchanged.
        // Only safe when the ID still names the SAME channel: after a restart
        // that reassigns IDs, joining a stale ID drops the user into an
        // unrelated channel — the very thing the path lookup exists to avoid.
        // If it doesn't match, say so and let the caller fall back to the
        // server's normal auto-join.
        var channel = Channel()
        if lastID > 0, TT_GetChannel(instance, lastID, &channel) != 0 {
            let currentPath = channelPathLocked(instance: instance, channelID: lastID)
            if path.isEmpty || currentPath == path {
                let pwd = channelPasswords[lastID] ?? password
                channelPasswords[lastID] = pwd
                _ = pwd.withCString { TT_DoJoinChannelByID(instance, lastID, $0) }
                AudioLogger.log("Reconnect: rejoining channel by ID %d", lastID)
                return true
            }
            AudioLogger.log("Reconnect: channel %d is now %@, not %@ — not rejoining by ID",
                            lastID, currentPath, path)
        }
        return false
    }

    /// Full path of a channel, or "" if unavailable. Stable across a server
    /// restart (unlike the numeric channel ID).
    func channelPathLocked(instance: UnsafeMutableRawPointer, channelID: Int32) -> String {
        guard channelID > 0 else { return "" }
        var pathBuffer = [TTCHAR](repeating: 0, count: Int(TT_STRLEN))
        guard TT_GetChannelPath(instance, channelID, &pathBuffer) != 0 else { return "" }
        return String(cString: pathBuffer)
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
                // Explicit option wins; otherwise use whatever we already know
                // for this channel (in-session or persisted).
                let password = options.initialChannelPassword.isEmpty
                    ? knownChannelPasswordLocked(instance: instance, channelID: channelID)
                    : options.initialChannelPassword
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
                        // On a cold launch the in-session map is empty, so this
                        // is exactly where the persisted password has to be
                        // consulted — otherwise "join last channel" lands the
                        // user in root despite a saved secret.
                        let pwd = knownChannelPasswordLocked(instance: instance, channelID: channelID)
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
                let configured = connectedRecord?.initialChannelPassword ?? ""
                let password = configured.isEmpty
                    ? knownChannelPasswordLocked(instance: instance, channelID: channelID)
                    : configured
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
                let (loginUsername, loginPassword) = try resolveLoginCredentialsLocked(
                    instance: instance,
                    record: record,
                    password: password
                )
                loginCommandID = nickname.withCString { nicknamePointer in
                    loginUsername.withCString { usernamePointer in
                        loginPassword.withCString { passwordPointer in
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
                    if message.clienterrormsg.nErrorNo == CMDERR_LOGINSERVICE_UNAVAILABLE.rawValue {
                        throw TeamTalkConnectionError.webLoginFailed(L10n.text("teamtalk.connection.error.webLoginServiceUnavailable"))
                    }
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

    /// Resolves the username/password pair to pass to `TT_DoLoginEx`. For a
    /// normal account this is the record's username and the stored password. For
    /// a bearware web login it performs the bearware token handshake using the
    /// server's `szAccessToken` and returns the bearware-confirmed username with
    /// an empty password. Runs synchronously on the TeamTalk queue.
    private func resolveLoginCredentialsLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        password: String
    ) throws -> (username: String, password: String) {
        guard record.useWebLogin else {
            return (record.username, password)
        }

        guard let credential = bearWareCredentialStore.load(), credential.token.isEmpty == false else {
            throw TeamTalkConnectionError.webLoginNotConfigured
        }

        var serverProperties = ServerProperties()
        guard TT_GetServerProperties(instance, &serverProperties) != 0 else {
            throw TeamTalkConnectionError.webLoginFailed(L10n.text("teamtalk.connection.error.webLoginFailed"))
        }
        let accessToken = ttString(from: serverProperties.szAccessToken)

        // No access token from the server (e.g. a race where szAccessToken is read
        // empty on CON_SUCCESS): skip the bearware round-trip entirely and fall back
        // to the record username with an empty password.
        guard accessToken.isEmpty == false else {
            return (record.username, "")
        }

        // Best-effort, like the Qt client (mainwindow.cpp slotBearWareAuthReply:
        // "connect even if auth failed. Otherwise user will not see progress"). A
        // non-conforming bearware.dk response must never abort the connection: we
        // fall back to the record username + empty password and let TT_DoLoginEx
        // surface a real CMDERR if the server actually rejects the login.
        let confirmedUsername = (try? bearWareWebLoginClient.clientAuth(
            username: credential.username,
            token: credential.token,
            accessToken: accessToken
        )) ?? ""
        let loginUsername = confirmedUsername.isEmpty ? record.username : confirmedUsername
        return (loginUsername, "")
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
                handleServerDropLocked(instance: instance, reason: "CON_LOST")
                return
            case CLIENTEVENT_CMD_MYSELF_LOGGEDOUT:
                handleServerDropLocked(instance: instance, reason: "MYSELF_LOGGEDOUT")
                return
            case CLIENTEVENT_AUDIOINPUT:
                break
            case CLIENTEVENT_USER_AUDIOBLOCK:
                // Per-user remote audio → our mixer (playback); muxed → AEC reference.
                handleAudioBlockLocked(instance: instance, source: message.nSource)
            case CLIENTEVENT_CMD_MYSELF_KICKED:
                // A kick from the SERVER is followed by MYSELF_LOGGEDOUT; mark
                // it so the drop handler knows that logout was expected and
                // doesn't reconnect us straight back in (or, for a ban, retry
                // forever). Only a server kick, identified by nSource == 0 the
                // same way `appendKickHistoryLocked` does: marking a CHANNEL
                // kick too would suppress a genuine reconnect if the connection
                // happened to drop within the mark's lifetime.
                if message.nSource == 0 {
                    justKickedAt = Date()
                }
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
                        // Device streams are endless — keep duration 0 (inert seek UI).
                        if info.uDurationMSec > 0, deviceStreamSource == nil {
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
                            // Reopens the virtual output + muxed event and starts the
                            // render engine directly (mute/gain reapplied from prefs
                            // inside the ensure path).
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
                        if message.user.nUserID == currentUserID {
                            armMicrophoneEngineOnJoinLocked(instance: instance)
                        }
                        if message.user.nUserID == currentUserID {
                            restartMediaStreamForChannelChangeLocked(instance: instance)
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
                        // Continuous mixer pan lives in our own render engine (not the SDK),
                        // so push it here too — otherwise the strip shows the saved pan while
                        // the user plays centered until the slider is touched. Voice and media
                        // pan independently (mirroring split volume). muted:false is the engine
                        // default; an active SOLO is re-applied right after via the coordinator's
                        // reapplySolo() on the next session update.
                        if let storedVoicePan = userVolumeStore.voicePan(forUsername: joinedUsername) {
                            outputRenderEngine.setUserSettings(
                                OutputUserMixSettings(volume: 1, pan: storedVoicePan, muted: false),
                                for: message.user.nUserID)
                        }
                        if let storedMediaPan = userVolumeStore.mediaPan(forUsername: joinedUsername) {
                            outputRenderEngine.setUserSettings(
                                OutputUserMixSettings(volume: 1, pan: storedMediaPan, muted: false),
                                for: outputMediaSourceKey(message.user.nUserID))
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
        // Channel IDs only mean anything for a live connection.
        clearSavedChannelPasswordIDs()

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

        deviceStreamSource?.stop()
        deviceStreamSource = nil
        deviceStreamMonitorEnabled = false
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
        userVolumeStore.setServerScope(nil)
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
        // Reset the device-preference dedup state too: the sound devices are closed
        // above, so on the next connect (which may reuse this warm instance)
        // applyAudioPreferences must re-initialize them. Leaving these set would let
        // the `applied == new` dedup guard silently skip re-applying the device.
        appliedInputPreference = nil
        appliedOutputPreference = nil
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
        // Belongs to the session being torn down. Without this it survives into
        // the NEXT one, and a drop there — before any channel has been joined,
        // so `TT_GetMyChannelID` gives 0 and the fallback kicks in — rejoins a
        // channel from the previous session, possibly on a different server.
        // Read by `handleServerDropLocked` BEFORE it calls us, so clearing here
        // costs the drop path nothing.
        lastKnownChannelID = 0
        lastKnownChannelPath = ""
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
                // A drop mid-command used to boot unconditionally; now it honors
                // autoReconnect like the idle loop, then unwinds the command.
                // When a reconnect IS armed the UI has already been told we're
                // reconnecting, so unwind with an error the presentation layer
                // stays quiet about — otherwise a modal alert and a VoiceOver
                // announcement land on top of the reconnecting state.
                if handleServerDropLocked(instance: instance, reason: "CON_LOST/LOGGEDOUT (command)") {
                    throw TeamTalkConnectionError.connectionLostReconnecting
                }
                throw TeamTalkConnectionError.connectionFailed
            case CLIENTEVENT_CMD_MYSELF_KICKED:
                // See the idle loop's handler: marks the MYSELF_LOGGEDOUT that
                // follows a SERVER kick (nSource == 0) as expected, so it isn't
                // reconnected. A channel kick is left unmarked on purpose.
                if message.nSource == 0 {
                    justKickedAt = Date()
                }
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
                            armMicrophoneEngineOnJoinLocked(instance: instance)
                            restartMediaStreamForChannelChangeLocked(instance: instance)
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
                        // Continuous mixer pan lives in our own render engine (not the SDK),
                        // so push it here too — otherwise the strip shows the saved pan while
                        // the user plays centered until the slider is touched. Voice and media
                        // pan independently (mirroring split volume). muted:false is the engine
                        // default; an active SOLO is re-applied right after via the coordinator's
                        // reapplySolo() on the next session update.
                        if let storedVoicePan = userVolumeStore.voicePan(forUsername: joinedUsername) {
                            outputRenderEngine.setUserSettings(
                                OutputUserMixSettings(volume: 1, pan: storedVoicePan, muted: false),
                                for: message.user.nUserID)
                        }
                        if let storedMediaPan = userVolumeStore.mediaPan(forUsername: joinedUsername) {
                            outputRenderEngine.setUserSettings(
                                OutputUserMixSettings(volume: 1, pan: storedMediaPan, muted: false),
                                for: outputMediaSourceKey(message.user.nUserID))
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
