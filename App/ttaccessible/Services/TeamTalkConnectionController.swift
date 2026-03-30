//
//  TeamTalkConnectionController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AVFoundation
import CoreAudio
import Foundation
import IOKit

@MainActor
protocol TeamTalkConnectionControllerDelegate: AnyObject {
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateSession session: ConnectedServerSession)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateAudioRuntime update: ConnectedServerAudioRuntimeUpdate)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateActiveTransfers transfers: [FileTransferProgress], currentChannelID: Int32)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didDisconnectWithMessage message: String?)
    func teamTalkConnectionControllerDidStartReconnecting(_ controller: TeamTalkConnectionController)
    func teamTalkConnectionController(
        _ controller: TeamTalkConnectionController,
        didRequestPrivateMessagesWindowFor userID: Int32?,
        reason: PrivateMessagesPresentationReason
    )
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didFinishFileTransfer fileName: String, isDownload: Bool, success: Bool)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveServerStatistics stats: ServerStatistics)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveUserAccounts accounts: [UserAccountProperties])
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveBannedUsers users: [BannedUserProperties])
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveIncomingTextMessage event: IncomingTextMessageEvent)
}

final class TeamTalkConnectionController {
    struct SessionPublishInvalidation: OptionSet {
        let rawValue: Int

        static let rootTree = SessionPublishInvalidation(rawValue: 1 << 0)
        static let chat = SessionPublishInvalidation(rawValue: 1 << 1)
        static let history = SessionPublishInvalidation(rawValue: 1 << 2)
        static let privateConversations = SessionPublishInvalidation(rawValue: 1 << 3)
        static let channelFiles = SessionPublishInvalidation(rawValue: 1 << 4)
        static let activeTransfers = SessionPublishInvalidation(rawValue: 1 << 5)
        static let audio = SessionPublishInvalidation(rawValue: 1 << 6)
        static let identity = SessionPublishInvalidation(rawValue: 1 << 7)
        static let permissions = SessionPublishInvalidation(rawValue: 1 << 8)

        static let all: SessionPublishInvalidation = [
            .rootTree,
            .chat,
            .history,
            .privateConversations,
            .channelFiles,
            .activeTransfers,
            .audio,
            .identity,
            .permissions
        ]
    }

    let queueKey = DispatchSpecificKey<Void>()
    let queue = DispatchQueue(label: "com.math65.ttaccessible.teamtalk")
    let clientName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TTAccessible"
    let preferencesStore: AppPreferencesStore
    let userVolumeStore = UserVolumeStore()
    let lastChannelStore = LastChannelStore()
    let audioDiagnosticsLogger = AudioDiagnosticsLogger.shared
    let performanceLogger = AppPerformanceLogger.shared

    @MainActor weak var delegate: TeamTalkConnectionControllerDelegate?
    @MainActor var sessionSnapshot: ConnectedServerSession?
    @MainActor var isConnected = false

    var instance: UnsafeMutableRawPointer?
    var pollTimer: DispatchSourceTimer?
    var connectedRecord: SavedServerRecord?
    var channelChatHistory: [ChannelChatMessage] = []
    var sessionHistory: [SessionHistoryEntry] = []
    var activeTransferProgress: [Int32: FileTransferProgress] = [:]
    var pendingTextMessages: [UInt64: [TextMessage]] = [:]
    var pendingChannelMessageCommandIDs = Set<Int32>()
    var observedSubscriptionStates: [Int32: [UserSubscriptionOption: Bool]] = [:]
    var suppressLoginHistoryDepth = 0
    var suppressJoinHistoryDepth = 0
    var suppressLoginHistoryUntil = Date.distantPast
    var suppressJoinHistoryUntil = Date.distantPast
    var channelPasswords: [Int32: String] = [:]
    var privateConversations: [Int32: PrivateConversation] = [:]
    var selectedPrivateConversationUserID: Int32?
    var visiblePrivateConversationUserID: Int32?
    var isPrivateMessagesWindowVisible = false
    var outputAudioReady = false
    var inputAudioReady = false
    var voiceTransmissionEnabled = false
    var teamTalkVirtualInputReady = false
    var advancedMicrophoneTargetFormat: AdvancedMicrophoneAudioTargetFormat?
    var insertedAudioChunkCount = 0
    var failedAudioChunkInsertCount = 0
    var lastLoggedAudioInputQueueBucket: UInt32?
    var reconnectTimer: DispatchSourceTimer?
    var reconnectRecord: SavedServerRecord?
    var reconnectPassword: String?
    var reconnectOptions = TeamTalkConnectOptions()
    var lastChannelID: Int32 = 0
    var isAutoAwayActive = false
    var autoAwayRestoreStatusMessage = ""
    var pendingUserAccounts: [UserAccountProperties] = []
    var listUserAccountsCmdID: Int32 = -1
    var pendingBannedUsers: [BannedUserProperties] = []
    var listBansCmdID: Int32 = -1
    var lastBuiltSessionSnapshot: ConnectedServerSession?
    var cachedSoundDevices: [SoundDevice] = []
    var cachedAudioDeviceCatalog: AudioDeviceCatalog?
    lazy var advancedMicrophoneEngine = AdvancedMicrophoneAudioEngine(diagnosticsScope: "audio-teamtalk-capture") { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }

    lazy var appleVoiceChatEngine = AppleVoiceChatAudioEngine(diagnosticsScope: "audio-apple-voicechat") { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        queue.setSpecific(key: queueKey, value: ())
    }

    func logAudio(_ message: String) {
        audioDiagnosticsLogger.log("audio", message)
    }

    var isAnyMicrophoneEngineRunning: Bool {
        advancedMicrophoneEngine.isRunning || appleVoiceChatEngine.isRunning
    }

    func describe(_ preset: InputChannelPreset) -> String {
        switch preset {
        case .auto:
            return "auto"
        case .mono(let channel):
            return "mono:\(channel)"
        case .stereoPair(let first, let second):
            return "stereo:\(first)/\(second)"
        case .monoMix(let first, let second):
            return "monoMix:\(first)+\(second)"
        }
    }

    func describeLimiter(_ preferences: AdvancedInputAudioPreferences) -> String {
        guard preferences.limiterEnabled else {
            return "off"
        }

        switch preferences.limiterMode {
        case .preset:
            return "preset:\(preferences.limiterPreset.rawValue)"
        case .manual:
            return "manual:\(preferences.effectiveLimiterThresholdDB)dB/\(Int(preferences.effectiveLimiterReleaseMilliseconds.rounded()))ms"
        }
    }

    func describeDynamicProcessor(_ preferences: AdvancedInputAudioPreferences) -> String {
        guard preferences.dynamicProcessorEnabled else {
            return "off"
        }
        switch preferences.dynamicProcessorMode {
        case .gate:
            return "gate:\(Int(preferences.gate.thresholdDB.rounded()))dB/\(Int(preferences.gate.attackMilliseconds.rounded()))ms/\(Int(preferences.gate.holdMilliseconds.rounded()))ms/\(Int(preferences.gate.releaseMilliseconds.rounded()))ms"
        case .expander:
            return "expander:\(Int(preferences.expander.thresholdDB.rounded()))dB/\(preferences.expander.ratio):1/\(Int(preferences.expander.attackMilliseconds.rounded()))ms/\(Int(preferences.expander.releaseMilliseconds.rounded()))ms"
        }
    }

    @MainActor
    func availableAudioDevices() -> AudioDeviceCatalog {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return availableAudioDevicesLocked(forceRefresh: false)
        }
        return queue.sync {
            availableAudioDevicesLocked(forceRefresh: false)
        }
    }

    @MainActor
    func refreshAvailableAudioDevices() -> AudioDeviceCatalog {
        queue.sync {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = nil
            return availableAudioDevicesLocked(forceRefresh: true)
        }
    }

    func applyAudioPreferences(
        _ preferences: AppPreferences,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                return
            }

            guard let instance = self.instance, let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                return
            }

            do {
                let advanced = self.currentAdvancedInputAudioPreferencesLocked(preferences: preferences)
                self.logAudio(
                    "Audio re-apply requested. input=\(preferences.preferredInputDevice.displayName ?? "system") output=\(preferences.preferredOutputDevice.displayName ?? "system") advanced=\(advanced.isEnabled) preset=\(self.describe(advanced.preset)) dynamic=\(self.describeDynamicProcessor(advanced)) limiter=\(self.describeLimiter(advanced))"
                )
                try self.reinitializeAudioDevicesLocked(instance: instance, preferences: preferences)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.logAudio("Audio re-apply failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func reloadPreferredAudioDevicesIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        applyAudioPreferences(preferencesStore.preferences, completion: completion)
    }

    // MARK: - applyDefaultSubscriptionPreferences (see TeamTalkConnectionController+Administration.swift)

    func applyInputGainDB(_ value: Double) {
        let clamped = AppPreferences.clampGainDB(value)
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.advancedMicrophoneEngine.updateInputGainDB(clamped)
            self.appleVoiceChatEngine.updateInputGainDB(clamped)
            self.logAudio("Input gain applied. value=\(Self.formatGainDB(clamped))")
        }
    }

    func applyOutputGainDB(_ value: Double) {
        let clamped = AppPreferences.clampGainDB(value)
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let instance = self.instance, self.connectedRecord != nil else {
                return
            }

            self.applyOutputGainLocked(instance: instance, gainDB: clamped)
            self.appleVoiceChatEngine.updateOutputGainDB(clamped)
            self.logAudio("Output gain applied. value=\(Self.formatGainDB(clamped))")
        }
    }

    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func activateVoiceTransmission(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            guard TT_GetMyChannelID(instance) > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel"))))
                }
                return
            }

            do {
                self.logAudio("Microphone activation requested. channel=\(TT_GetMyChannelID(instance)) engineRunning=\(self.isAnyMicrophoneEngineRunning) inputReady=\(self.inputAudioReady) virtualReady=\(self.teamTalkVirtualInputReady)")
                try self.ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                self.voiceTransmissionEnabled = true
                SoundPlayer.shared.play(.voxMeEnable)
                self.logAudio("Microphone enabled. engineRunning=\(self.isAnyMicrophoneEngineRunning) virtualReady=\(self.teamTalkVirtualInputReady)")
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.logAudio("Microphone activation failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func deactivateVoiceTransmission(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            if self.isAnyMicrophoneEngineRunning || self.inputAudioReady {
                self.stopAdvancedMicrophoneInputLocked(instance: instance, reason: "deactivateVoiceTransmission")
            }
            self.voiceTransmissionEnabled = false
            self.inputAudioReady = false
            self.advancedMicrophoneTargetFormat = nil
            SoundPlayer.shared.play(.voxMeDisable)
            self.logAudio("Microphone disabled.")
            self.publishSessionLocked(instance: instance, record: record)

            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    // MARK: - Private messaging (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Identity (see TeamTalkConnectionController+Identity.swift)

    // MARK: - Channel management (see TeamTalkConnectionController+ChannelManagement.swift)

    // MARK: - Administration (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Channel & broadcast messaging (see TeamTalkConnectionController+Messaging.swift)

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

    func createInstanceLocked() throws -> UnsafeMutableRawPointer {
        guard let instance = TT_InitTeamTalkPoll() else {
            throw TeamTalkConnectionError.sdkUnavailable
        }
        return instance
    }


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
        logAudio("Automatic reconnection scheduled in 5 seconds.")
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

        logAudio("Attempting reconnection to \(record.host):\(record.tcpPort)")

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

            // Succès — restaurer l'état
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
            logAudio("Reconnection succeeded.")
        } catch {
            logAudio("Reconnection failed: \(error.localizedDescription)")
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

        // Priorité 1 : szInitChannel du compte utilisateur côté serveur
        var account = UserAccount()
        if TT_GetMyUserAccount(instance, &account) != 0 {
            let initChannel = ttString(from: account.szInitChannel)
            if initChannel.isEmpty == false {
                return
            }
        }

        // Priorité 2 : canal initial configuré sur le serveur enregistré
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

        // Priorité 3 : rejoindre le canal racine si la préférence est activée
        guard preferencesStore.preferences.autoJoinRootChannel else { return }
        let rootChannelID = TT_GetRootChannelID(instance)
        guard rootChannelID > 0 else { return }
        _ = TT_DoJoinChannelByID(instance, rootChannelID, "")
    }

    func connectAndLoginLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        password: String,
        options: TeamTalkConnectOptions
    ) throws {
        logAudio("Connecting to server \(record.host):\(record.tcpPort)/\(record.udpPort) secure=\(record.encrypted)")
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
                logAudio("Transport connection established. Starting TeamTalk login.")
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
                logAudio("TeamTalk login succeeded.")
                return

            case CLIENTEVENT_CMD_ERROR:
                if loginCommandID == -1 || message.nSource == loginCommandID {
                    logAudio("TeamTalk error during login: \(clientErrorMessage(from: message) ?? "unknown")")
                    throw TeamTalkConnectionError.loginFailed(clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.loginFailed"))
                }

            case CLIENTEVENT_CON_CRYPT_ERROR:
                logAudio("Encryption error during connection.")
                throw TeamTalkConnectionError.connectionFailed

            case CLIENTEVENT_CON_FAILED:
                logAudio("Transport connection failed.")
                throw TeamTalkConnectionError.connectionFailed

            case CLIENTEVENT_INTERNAL_ERROR:
                logAudio("Internal TeamTalk error during connection: \(clientErrorMessage(from: message) ?? "unknown")")
                throw TeamTalkConnectionError.internalError(clientErrorMessage(from: message) ?? L10n.text("teamtalk.connection.error.internal"))

            default:
                continue
            }
        }

        throw TeamTalkConnectionError.connectionTimeout
    }

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

    func drainMessagesLocked() {
        guard let instance else {
            return
        }

        let drainStartedAt = performanceLogger.beginInterval("teamtalk.drainMessages")
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
            if connectedRecord != nil,
               updateAutoAwayIfNeededLocked(instance: instance) {
                publishInvalidation = .all
            }
            if publishInvalidation.contains(.activeTransfers),
               publishInvalidation.intersection([.rootTree, .chat, .history, .privateConversations, .channelFiles, .audio, .identity, .permissions]).isEmpty {
                publishActiveTransfersLocked(currentChannelID: TT_GetMyChannelID(instance))
            } else if !publishInvalidation.isEmpty, let connectedRecord {
                publishSessionLocked(instance: instance, record: connectedRecord, invalidation: publishInvalidation)
            }
            performanceLogger.endInterval("teamtalk.drainMessages", drainStartedAt)
        }

        while true {
            var message = TTMessage()
            guard TT_GetMessage(instance, &message, &waitMSec) != 0 else {
                return
            }

            switch message.nClientEvent {
            case CLIENTEVENT_CON_LOST:
                logAudio("Connection lost.")
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
                logAudio("Forced logout.")
                appendConnectionLostHistoryLocked()
                destroyLocked()
                publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
                return
            case CLIENTEVENT_AUDIOINPUT:
                let queueMSec = message.audioinputprogress.uQueueMSec
                let bucket = queueMSec / 50
                if lastLoggedAudioInputQueueBucket != bucket || queueMSec == 0 {
                    lastLoggedAudioInputQueueBucket = bucket
                    logAudio("TeamTalk audio queue state: queueMSec=\(queueMSec) elapsedMSec=\(message.audioinputprogress.uElapsedMSec)")
                }
            case CLIENTEVENT_USER_AUDIOBLOCK:
                handleUserAudioBlockEventLocked(message, instance: instance)
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
                           preferencesStore.preferences.microphoneEnabledByDefault,
                           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                            do {
                                try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                                voiceTransmissionEnabled = true
                            } catch {}
                        }
                        let joinedUsername = ttString(from: message.user.szUsername)
                        if let storedVolume = userVolumeStore.volume(forUsername: joinedUsername) {
                            _ = TT_SetUserVolume(instance, message.user.nUserID, STREAMTYPE_VOICE, storedVolume)
                        }
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

    func resetLocked() {
        destroyLocked()
    }

    func destroyLocked() {
        logAudio("Tearing down TeamTalk session. voiceEnabled=\(voiceTransmissionEnabled) engineRunning=\(isAnyMicrophoneEngineRunning) inputReady=\(inputAudioReady) outputReady=\(outputAudioReady)")
        stopPollingLocked()

        if let instance {
            if isAnyMicrophoneEngineRunning || inputAudioReady {
                stopAdvancedMicrophoneInputLocked(instance: instance, reason: "destroyLocked")
            }
            if teamTalkVirtualInputReady {
                _ = TT_CloseSoundInputDevice(instance)
                teamTalkVirtualInputReady = false
                logAudio("TeamTalk virtual input closed.")
            }
            if outputAudioReady {
                _ = TT_CloseSoundOutputDevice(instance)
            }
            TT_Disconnect(instance)
            TT_CloseTeamTalk(instance)
        }

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
        teamTalkVirtualInputReady = false
        advancedMicrophoneTargetFormat = nil
        insertedAudioChunkCount = 0
        failedAudioChunkInsertCount = 0
        lastLoggedAudioInputQueueBucket = nil
        isAutoAwayActive = false
        autoAwayRestoreStatusMessage = ""
    }

    // MARK: - Auto-away (see TeamTalkConnectionController+Identity.swift)

    func clientErrorMessage(from message: TTMessage) -> String? {
        guard message.ttType == __CLIENTERRORMSG else {
            return nil
        }

        let value = ttString(from: message.clienterrormsg.szErrorMsg)
        return value.isEmpty ? nil : value
    }

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
                        }
                    case CLIENTEVENT_CMD_USER_LOGGEDOUT:
                        appendUserLoggedOutHistoryLocked(message.user, currentUserID: currentUserID)
                    case CLIENTEVENT_CMD_USER_JOINED:
                        if isSuppressingLoginHistoryLocked == false {
                            appendUserJoinedChannelHistoryLocked(message.user, currentUserID: currentUserID, instance: instance)
                        }
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
                    handleTextMessageEventLocked(message.textmessage, instance: instance, record: connectedRecord)
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

    // MARK: - Session snapshot and publishing (see TeamTalkConnectionController+SessionSnapshot.swift)

    // MARK: - Session history (see TeamTalkConnectionController+SessionHistory.swift)

    // MARK: - Text message handling (see TeamTalkConnectionController+Messaging.swift)

    func copyTTString<T>(_ string: String, into target: inout T) {
        var copy = target
        withUnsafeMutablePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                memset(charPointer, 0, MemoryLayout<T>.size)
                _ = string.withCString { source in
                    strlcpy(charPointer, source, MemoryLayout<T>.size)
                }
            }
        }
        target = copy
    }

    func displayName(forUserID userID: Int32, instance: UnsafeMutableRawPointer) -> String {
        var user = User()
        if TT_GetUser(instance, userID, &user) != 0 {
            return displayName(for: user)
        }

        return L10n.format("connectedServer.chat.sender.unknown", String(userID))
    }

    func currentUserLocked(instance: UnsafeMutableRawPointer) -> User? {
        let currentUserID = TT_GetMyUserID(instance)
        guard currentUserID > 0 else {
            return nil
        }

        var user = User()
        guard TT_GetUser(instance, currentUserID, &user) != 0 else {
            return nil
        }
        return user
    }

    // MARK: - Private conversation helpers (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Subscription helpers (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Message publishing helpers (see TeamTalkConnectionController+Messaging.swift)

    func ensureOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard outputAudioReady == false else {
            return
        }

        try ensureDirectOutputAudioReadyLocked(instance: instance)
    }

    func ensureAdvancedMicrophoneInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard inputAudioReady == false else {
            return
        }

        guard let deviceInfo = InputAudioDeviceResolver.resolveCurrentInputDevice(for: preferencesStore.preferences.preferredInputDevice) else {
            throw TeamTalkConnectionError.internalError(L10n.text("preferences.audio.advanced.error.deviceUnavailable"))
        }

        let effectivePreferences = effectiveMicrophoneProcessingPreferencesLocked(for: deviceInfo)
        let targetFormat = try currentAdvancedMicrophoneTargetFormatLocked(instance: instance)

        do {
            let configuration = AdvancedMicrophoneAudioConfiguration(
                device: deviceInfo,
                preset: effectivePreferences.preset,
                inputGainDB: preferencesStore.preferences.inputGainDB,
                echoCancellationEnabled: effectivePreferences.echoCancellationEnabled,
                dynamicProcessorEnabled: effectivePreferences.dynamicProcessorEnabled,
                dynamicProcessorMode: effectivePreferences.dynamicProcessorMode,
                gateThresholdDB: effectivePreferences.gate.thresholdDB,
                gateAttackMilliseconds: effectivePreferences.gate.attackMilliseconds,
                gateHoldMilliseconds: effectivePreferences.gate.holdMilliseconds,
                gateReleaseMilliseconds: effectivePreferences.gate.releaseMilliseconds,
                expanderThresholdDB: effectivePreferences.expander.thresholdDB,
                expanderRatio: effectivePreferences.expander.ratio,
                expanderAttackMilliseconds: effectivePreferences.expander.attackMilliseconds,
                expanderReleaseMilliseconds: effectivePreferences.expander.releaseMilliseconds,
                limiterEnabled: effectivePreferences.limiterEnabled,
                limiterMode: effectivePreferences.limiterMode,
                limiterPreset: effectivePreferences.limiterPreset,
                limiterThresholdDB: effectivePreferences.effectiveLimiterThresholdDB,
                limiterReleaseMilliseconds: effectivePreferences.effectiveLimiterReleaseMilliseconds,
                targetFormat: targetFormat
            )
            logAudio(
                "Starting Apple capture. device=\(deviceInfo.name) channels=\(deviceInfo.inputChannels) sampleRate=\(deviceInfo.nominalSampleRate) aec=\(effectivePreferences.echoCancellationEnabled) preset=\(describe(effectivePreferences.preset)) dynamic=\(describeDynamicProcessor(effectivePreferences)) limiter=\(describeLimiter(effectivePreferences)) targetRate=\(targetFormat.sampleRate) targetChannels=\(targetFormat.channels) txInterval=\(targetFormat.txIntervalMSec)"
            )
            try ensureTeamTalkVirtualInputReadyLocked(instance: instance)
            if effectivePreferences.echoCancellationEnabled {
                let outputUID = try selectedOutputDeviceUIDLocked()
                let voiceChatConfig = AppleVoiceChatAudioConfiguration(
                    microphone: configuration,
                    outputDeviceUID: outputUID,
                    outputGainDB: preferencesStore.preferences.outputGainDB
                )
                if outputAudioReady {
                    _ = TT_CloseSoundOutputDevice(instance)
                    outputAudioReady = false
                    logAudio("TeamTalk output closed for AEC handover.")
                }
                let result = try appleVoiceChatEngine.start(configuration: voiceChatConfig)
                var audioFmt = AudioFormat()
                audioFmt.nAudioFmt = AFF_WAVE_FORMAT
                audioFmt.nSampleRate = result.playbackFormat.sampleRate
                audioFmt.nChannels = result.playbackFormat.channels
                withUnsafePointer(to: audioFmt) { fmtPtr in
                    _ = TT_EnableAudioBlockEventEx(instance, TT_MUXED_USERID, STREAMTYPE_VOICE.rawValue, fmtPtr, 1)
                }
                logAudio(
                    "AppleVoiceChat engine started. streamID=\(result.streamID) playbackRate=\(result.playbackFormat.sampleRate) playbackChannels=\(result.playbackFormat.channels)"
                )
            } else {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
                _ = try advancedMicrophoneEngine.start(configuration: configuration)
                logAudio("Microphone capture started.")
            }
            advancedMicrophoneTargetFormat = targetFormat
            inputAudioReady = true
            insertedAudioChunkCount = 0
            failedAudioChunkInsertCount = 0
            lastLoggedAudioInputQueueBucket = nil
        } catch {
            if teamTalkVirtualInputReady {
                _ = TT_CloseSoundInputDevice(instance)
                teamTalkVirtualInputReady = false
                logAudio("TeamTalk virtual input closed after Apple capture start failure.")
            }
            inputAudioReady = false
            advancedMicrophoneTargetFormat = nil
            do {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
            } catch {
                logAudio("Failed to restore TeamTalk output after microphone error: \(error.localizedDescription)")
            }
            logAudio("Microphone start failed: \(error.localizedDescription)")
            throw error
        }
    }

    func reinitializeAudioDevicesLocked(
        instance: UnsafeMutableRawPointer,
        preferences: AppPreferences
    ) throws {
        logAudio("Audio reinitialization. wasVoice=\(voiceTransmissionEnabled) wasInput=\(inputAudioReady) wasOutput=\(outputAudioReady)")
        let wasVoiceTransmissionEnabled = voiceTransmissionEnabled
        let wasInputAudioReady = inputAudioReady
        if wasVoiceTransmissionEnabled || wasInputAudioReady || isAnyMicrophoneEngineRunning {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "reinitializeAudioDevicesLocked")
        }
        voiceTransmissionEnabled = false
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil

        if outputAudioReady {
            _ = TT_CloseSoundOutputDevice(instance)
            outputAudioReady = false
        }

        try ensureDirectOutputAudioReadyLocked(instance: instance)

        if wasVoiceTransmissionEnabled || wasInputAudioReady {
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
        }

        if wasVoiceTransmissionEnabled {
            voiceTransmissionEnabled = true
        }
    }

    func makeAudioStatusText() -> String {
        if voiceTransmissionEnabled {
            return L10n.text("connectedServer.audio.status.microphoneActive")
        }
        if inputAudioReady {
            return L10n.text("connectedServer.audio.status.inputReady")
        }
        if outputAudioReady {
            return L10n.text("connectedServer.audio.status.outputReady")
        }
        return L10n.text("connectedServer.audio.status.unavailable")
    }

    enum AudioDirection {
        case input
        case output
    }

    func loadSoundDevicesLocked(forceRefresh: Bool) -> [SoundDevice] {
        if forceRefresh == false, cachedSoundDevices.isEmpty == false {
            return cachedSoundDevices
        }

        var count: INT32 = 0
        guard TT_GetSoundDevices(nil, &count) != 0, count > 0 else {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = .empty
            return []
        }

        var devices = Array(repeating: SoundDevice(), count: Int(count))
        guard TT_GetSoundDevices(&devices, &count) != 0 else {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = .empty
            return []
        }

        cachedSoundDevices = Array(devices.prefix(Int(count)))
        return cachedSoundDevices
    }

    func availableAudioDevicesLocked(forceRefresh: Bool) -> AudioDeviceCatalog {
        if forceRefresh == false, let cachedAudioDeviceCatalog {
            return cachedAudioDeviceCatalog
        }

        let activeDevices = loadSoundDevicesLocked(forceRefresh: forceRefresh)
        let inputDevices = activeDevices
            .filter { $0.nMaxInputChannels > 0 && $0.nDeviceID != TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL }
            .map(makeAudioDeviceOption(from:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let outputDevices = activeDevices
            .filter { $0.nMaxOutputChannels > 0 && $0.nDeviceID != TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL }
            .map(makeAudioDeviceOption(from:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let catalog = AudioDeviceCatalog(inputDevices: inputDevices, outputDevices: outputDevices)
        cachedAudioDeviceCatalog = catalog
        return catalog
    }

    func makeAudioDeviceOption(from device: SoundDevice) -> AudioDeviceOption {
        let persistentID = ttString(from: device.szDeviceID).isEmpty
            ? "legacy:\(device.nDeviceID)"
            : ttString(from: device.szDeviceID)
        return AudioDeviceOption(
            id: persistentID,
            persistentID: persistentID,
            displayName: ttString(from: device.szDeviceName)
        )
    }

    func ensureDirectOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard outputAudioReady == false else {
            return
        }

        let outputDeviceID = try selectedOutputDeviceIDLocked()
        guard TT_InitSoundOutputDevice(instance, outputDeviceID) != 0 else {
            logAudio("TeamTalk output init failed. deviceID=\(outputDeviceID)")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        outputAudioReady = true
        applyOutputGainLocked(instance: instance, gainDB: preferencesStore.preferences.outputGainDB)
        logAudio("TeamTalk direct output initialized. deviceID=\(outputDeviceID)")
    }

    func stopAdvancedMicrophoneInputLocked(instance: UnsafeMutableRawPointer, reason: String) {
        logAudio("Stopping Apple capture. reason=\(reason) virtualReady=\(teamTalkVirtualInputReady) inserted=\(insertedAudioChunkCount) failed=\(failedAudioChunkInsertCount)")
        if appleVoiceChatEngine.isRunning {
            logAudio("Microphone teardown: disabling muxed audio block events...")
            _ = TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, STREAMTYPE_VOICE.rawValue, 0)
            logAudio("Microphone teardown: stopping AppleVoiceChat engine...")
            appleVoiceChatEngine.stop()
            logAudio("Microphone teardown: AppleVoiceChat engine stopped.")
        } else {
            logAudio("Microphone teardown: stopping Apple engine...")
            advancedMicrophoneEngine.stop()
            logAudio("Microphone teardown: Apple engine stopped.")
        }
        let didEndRawInput = TT_InsertAudioBlock(instance, nil) != 0
        logAudio("Microphone teardown: TT_InsertAudioBlock(nil)=\(didEndRawInput)")
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil
        logAudio("Microphone teardown: local state reset.")
        if outputAudioReady == false {
            do {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
                logAudio("TeamTalk direct output restored after AEC stop.")
            } catch {
                logAudio("Failed to restore TeamTalk output after AEC stop: \(error.localizedDescription)")
            }
        }
    }

    func ensureTeamTalkVirtualInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard teamTalkVirtualInputReady == false else {
            return
        }

        guard TT_InitSoundInputDevice(instance, TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) != 0 else {
            logAudio("TeamTalk virtual input init failed.")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.inputStartFailed"))
        }

        teamTalkVirtualInputReady = true
        logAudio("TeamTalk virtual input initialized.")
    }

    func effectiveMicrophoneProcessingPreferencesLocked(
        for deviceInfo: InputAudioDeviceInfo
    ) -> AdvancedInputAudioPreferences {
        var effectivePreferences = preferencesStore.advancedInputAudio(for: deviceInfo.uid)
        if effectivePreferences.isEnabled == false {
            effectivePreferences.preset = .auto
            effectivePreferences.dynamicProcessorEnabled = false
            effectivePreferences.limiterEnabled = false
        }

        return InputAudioDeviceResolver.normalizedPreferences(
            effectivePreferences,
            for: deviceInfo
        ).preferences
    }

    func currentAdvancedInputAudioPreferencesLocked(
        preferences: AppPreferences
    ) -> AdvancedInputAudioPreferences {
        let deviceID = InputAudioDeviceResolver.currentInputDeviceID(for: preferences.preferredInputDevice)
        return preferencesStore.advancedInputAudio(for: deviceID)
    }

    func handleUserAudioBlockEventLocked(
        _ message: TTMessage,
        instance: UnsafeMutableRawPointer
    ) {
        guard appleVoiceChatEngine.isRunning else {
            return
        }
        let userID = message.nSource
        guard let block = TT_AcquireUserAudioBlock(instance, STREAMTYPE_VOICE.rawValue, userID) else {
            return
        }
        defer { _ = TT_ReleaseUserAudioBlock(instance, block) }
        let sampleCount = block.pointee.nSamples
        let sampleRate = block.pointee.nSampleRate
        let channels = block.pointee.nChannels
        let streamID = block.pointee.nStreamID
        guard sampleCount > 0, channels > 0, let rawAudio = block.pointee.lpRawAudio else {
            return
        }
        let byteCount = Int(sampleCount) * Int(channels) * 2
        let data = Data(bytes: rawAudio, count: byteCount)
        let chunk = TeamTalkPlaybackAudioChunk(
            sourceID: streamID,
            streamTypes: STREAMTYPE_VOICE.rawValue,
            sampleRate: sampleRate,
            channels: channels,
            sampleCount: sampleCount,
            data: data
        )
        appleVoiceChatEngine.enqueuePlaybackChunk(chunk)
    }

    func insertAdvancedMicrophoneAudioChunkLocked(_ chunk: AdvancedMicrophoneAudioChunk) {
        guard voiceTransmissionEnabled,
              let instance,
              TT_GetMyChannelID(instance) > 0 else {
            logAudio(
                "Chunk skipped before injection. voice=\(voiceTransmissionEnabled) inChannel=\(instance.map { TT_GetMyChannelID($0) > 0 } ?? false) stream=\(chunk.streamID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount)"
            )
            return
        }

        let stats = chunkLevelStats(chunk.data)
        chunk.data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var audioBlock = AudioBlock()
            audioBlock.nStreamID = chunk.streamID
            audioBlock.nSampleRate = chunk.sampleRate
            audioBlock.nChannels = chunk.channels
            audioBlock.lpRawAudio = UnsafeMutableRawPointer(mutating: baseAddress)
            audioBlock.nSamples = chunk.sampleCount
            audioBlock.uSampleIndex = 0
            if TT_InsertAudioBlock(instance, &audioBlock) != 0 {
                insertedAudioChunkCount += 1
                if insertedAudioChunkCount <= 12 || insertedAudioChunkCount % 50 == 0 {
                    logAudio(
                        "Audio block injected. count=\(insertedAudioChunkCount) stream=\(chunk.streamID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount) peak=\(formatDecibels(stats.peak)) rms=\(formatDecibels(stats.rms)) bytes=\(chunk.data.count)"
                    )
                }
            } else {
                failedAudioChunkInsertCount += 1
                logAudio(
                    "TT_InsertAudioBlock failed. failed=\(failedAudioChunkInsertCount) stream=\(chunk.streamID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount) peak=\(formatDecibels(stats.peak)) rms=\(formatDecibels(stats.rms)) bytes=\(chunk.data.count)"
                )
            }
        }
    }

    func chunkLevelStats(_ data: Data) -> (peak: Float, rms: Float) {
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard let baseAddress = samples.baseAddress, samples.count > 0 else {
                return (0, 0)
            }

            var peak: Float = 0
            var sumSquares: Double = 0
            let scale = Float(Int16.max)
            for index in 0..<samples.count {
                let normalized = Float(baseAddress[index]) / scale
                let magnitude = abs(normalized)
                peak = max(peak, magnitude)
                sumSquares += Double(normalized * normalized)
            }
            let rms = Float((sumSquares / Double(samples.count)).squareRoot())
            return (peak, rms)
        }
    }

    func formatDecibels(_ value: Float) -> String {
        guard value > 0 else {
            return "-inf dBFS"
        }
        return String(format: "%.1f dBFS", 20 * log10(Double(value)))
    }

    func refreshAdvancedMicrophoneTargetIfNeededLocked(instance: UnsafeMutableRawPointer) {
        guard isAnyMicrophoneEngineRunning else {
            return
        }

        guard let currentTargetFormat = try? currentAdvancedMicrophoneTargetFormatLocked(instance: instance) else {
            return
        }

        guard currentTargetFormat != advancedMicrophoneTargetFormat else {
            return
        }

        logAudio("Microphone target format changed. old=\(String(describing: advancedMicrophoneTargetFormat)) new=\(currentTargetFormat)")
        do {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "refreshAdvancedMicrophoneTargetIfNeededLocked")
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
        } catch {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "refreshAdvancedMicrophoneTargetIfNeededLocked rollback")
            voiceTransmissionEnabled = false
            logAudio("Microphone target format refresh failed: \(error.localizedDescription)")
        }
    }

    func currentAdvancedMicrophoneTargetFormatLocked(instance: UnsafeMutableRawPointer) throws -> AdvancedMicrophoneAudioTargetFormat {
        let channelID = TT_GetMyChannelID(instance)
        guard channelID > 0 else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel"))
        }

        var channel = Channel()
        guard TT_GetChannel(instance, channelID, &channel) != 0 else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel"))
        }

        let audioCodec = channel.audiocodec
        switch audioCodec.nCodec {
        case OPUS_CODEC:
            let channels = max(1, min(2, Int(audioCodec.opus.nChannels)))
            let txInterval = audioCodec.opus.nTxIntervalMSec > 0 ? audioCodec.opus.nTxIntervalMSec : 20
            return AdvancedMicrophoneAudioTargetFormat(
                sampleRate: Double(audioCodec.opus.nSampleRate),
                channels: channels,
                txIntervalMSec: txInterval
            )

        case SPEEX_CODEC:
            return AdvancedMicrophoneAudioTargetFormat(
                sampleRate: sampleRate(forSpeexBandmode: audioCodec.speex.nBandmode),
                channels: audioCodec.speex.bStereoPlayback != 0 ? 2 : 1,
                txIntervalMSec: audioCodec.speex.nTxIntervalMSec > 0 ? audioCodec.speex.nTxIntervalMSec : 20
            )

        case SPEEX_VBR_CODEC:
            return AdvancedMicrophoneAudioTargetFormat(
                sampleRate: sampleRate(forSpeexBandmode: audioCodec.speex_vbr.nBandmode),
                channels: audioCodec.speex_vbr.bStereoPlayback != 0 ? 2 : 1,
                txIntervalMSec: audioCodec.speex_vbr.nTxIntervalMSec > 0 ? audioCodec.speex_vbr.nTxIntervalMSec : 20
            )

        default:
            return AdvancedMicrophoneAudioTargetFormat(sampleRate: 48_000, channels: 1, txIntervalMSec: 20)
        }
    }

    func sampleRate(forSpeexBandmode bandmode: Int32) -> Double {
        switch bandmode {
        case 1:
            return 16_000
        case 2:
            return 32_000
        default:
            return 8_000
        }
    }

    func selectedOutputDeviceIDLocked() throws -> INT32 {
        try selectedDeviceIDLocked(
            preference: preferencesStore.preferences.preferredOutputDevice,
            availableDevices: availableAudioDevicesLocked(forceRefresh: false).outputDevices,
            direction: .output
        )
    }

    func selectedOutputDeviceUIDLocked() throws -> String {
        let preference = preferencesStore.preferences.preferredOutputDevice
        // If the user picked a specific device, its persistentID is already the CoreAudio UID
        // (for non-legacy devices, makeAudioDeviceOption sets persistentID = szDeviceID = CoreAudio UID).
        if let prefID = preference.persistentID,
           prefID.isEmpty == false,
           !prefID.hasPrefix("legacy:") {
            let availableDevices = availableAudioDevicesLocked(forceRefresh: false).outputDevices
            if availableDevices.contains(where: { $0.persistentID == prefID }) {
                return prefID
            }
        }
        // Fall back to the system default output device via CoreAudio directly.
        return try systemDefaultOutputDeviceUID()
    }

    func systemDefaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioDeviceUnknown else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { ptr in
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, ptr)
        }
        guard status == noErr, let uid = cfUID else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        return uid as String
    }

    func selectedInputDeviceIDLocked() throws -> INT32 {
        try selectedDeviceIDLocked(
            preference: preferencesStore.preferences.preferredInputDevice,
            availableDevices: availableAudioDevicesLocked(forceRefresh: false).inputDevices,
            direction: .input
        )
    }

    func applyOutputGainLocked(instance: UnsafeMutableRawPointer, gainDB: Double) {
        let volume = Self.teamTalkVolume(for: gainDB)
        guard TT_SetSoundOutputVolume(instance, volume) != 0 else {
            logAudio("Output gain application failed. value=\(Self.formatGainDB(gainDB)) volume=\(volume)")
            return
        }
    }

    private nonisolated static func teamTalkVolume(for gainDB: Double) -> INT32 {
        let defaultVolume = Double(SOUND_VOLUME_DEFAULT.rawValue)
        let minVolume = Double(SOUND_VOLUME_MIN.rawValue)
        let maxVolume = Double(SOUND_VOLUME_MAX.rawValue)
        let linear = pow(10.0, gainDB / 20.0)
        let scaled = defaultVolume * linear
        let clamped = min(max(scaled.rounded(), minVolume), maxVolume)
        return INT32(clamped)
    }

    private nonisolated static func formatGainDB(_ value: Double) -> String {
        let rounded = AppPreferences.clampGainDB(value)
        if rounded > 0 {
            return String(format: "+%.0f dB", rounded)
        }
        return String(format: "%.0f dB", rounded)
    }

    func selectedDeviceIDLocked(
        preference: AudioDevicePreference,
        availableDevices: [AudioDeviceOption],
        direction: AudioDirection
    ) throws -> INT32 {
        var defaultInputDeviceID: INT32 = 0
        var defaultOutputDeviceID: INT32 = 0
        guard TT_GetDefaultSoundDevices(&defaultInputDeviceID, &defaultOutputDeviceID) != 0 else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.defaultDevicesUnavailable"))
        }

        guard let persistentID = preference.persistentID, persistentID.isEmpty == false else {
            return direction == .input ? defaultInputDeviceID : defaultOutputDeviceID
        }

        guard availableDevices.contains(where: { $0.persistentID == persistentID }) else {
            return direction == .input ? defaultInputDeviceID : defaultOutputDeviceID
        }

        for device in loadSoundDevicesLocked(forceRefresh: false) {
            let candidatePersistentID = ttString(from: device.szDeviceID).isEmpty
                ? "legacy:\(device.nDeviceID)"
                : ttString(from: device.szDeviceID)
            guard candidatePersistentID == persistentID else {
                continue
            }
            if direction == .input, device.nMaxInputChannels > 0 {
                return device.nDeviceID
            }
            if direction == .output, device.nMaxOutputChannels > 0 {
                return device.nDeviceID
            }
        }

        return direction == .input ? defaultInputDeviceID : defaultOutputDeviceID
    }

    func fetchServerChannelsLocked(instance: UnsafeMutableRawPointer) -> [Channel] {
        var count: INT32 = 0
        guard TT_GetServerChannels(instance, nil, &count) != 0, count > 0 else {
            return []
        }

        var channels = Array(repeating: Channel(), count: Int(count))
        var actualCount = count
        let didFetch = channels.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }

            return TT_GetServerChannels(instance, baseAddress, &actualCount) != 0
        }

        guard didFetch else {
            return []
        }

        return Array(channels.prefix(Int(actualCount)))
    }

    func fetchServerUsersLocked(instance: UnsafeMutableRawPointer) -> [User] {
        var count: INT32 = 0
        guard TT_GetServerUsers(instance, nil, &count) != 0, count > 0 else {
            return []
        }

        var users = Array(repeating: User(), count: Int(count))
        var actualCount = count
        let didFetch = users.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }

            return TT_GetServerUsers(instance, baseAddress, &actualCount) != 0
        }

        guard didFetch else {
            return []
        }

        return Array(users.prefix(Int(actualCount)))
    }

    func displayName(for user: User) -> String {
        let nickname = ttString(from: user.szNickname)
        if nickname.isEmpty == false {
            return nickname
        }
        return ttString(from: user.szUsername)
    }

    func effectiveNickname(for record: SavedServerRecord, override nicknameOverride: String? = nil) -> String {
        let overriddenNickname = nicknameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if overriddenNickname.isEmpty == false {
            return overriddenNickname
        }

        let recordNickname = record.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if recordNickname.isEmpty == false {
            return recordNickname
        }

        let preferredNickname = preferencesStore.preferences.defaultNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferredNickname.isEmpty == false {
            return preferredNickname
        }

        return "TTAccessible"
    }

    func clientVersion(for user: User) -> String {
        "\(user.uVersion >> 16).\((user.uVersion >> 8) & 0xFF).\(user.uVersion & 0xFF)"
    }

    func ttString<T>(from value: T) -> String {
        var copy = value
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                String(cString: charPointer)
            }
        }
    }
}
