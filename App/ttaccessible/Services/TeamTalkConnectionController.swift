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

enum IncomingTextMessageKind {
    case privateMessage
    case channelMessage
    case broadcastMessage
}

struct IncomingTextMessageEvent {
    let kind: IncomingTextMessageKind
    let senderName: String
    let content: String
}

// MARK: - Server properties model

struct ServerPropertiesData {
    var name: String
    var motdRaw: String
    var maxUsers: Int32
    var userTimeout: Int32
    var loginDelayMSec: Int32
    var maxLoginAttempts: Int32
    var maxLoginsPerIPAddress: Int32
    var autoSave: Bool
    var maxVoiceTxPerSecond: Int32
    var maxVideoCaptureTxPerSecond: Int32
    var maxMediaFileTxPerSecond: Int32
    var maxDesktopTxPerSecond: Int32
    var maxTotalTxPerSecond: Int32
}

// MARK: - Banned user model

struct BannedUserProperties {
    var ipAddress: String
    var channelPath: String
    var banTime: String
    var nickname: String
    var username: String
    var banTypes: UInt32
    var owner: String

    var displayBanType: String {
        var parts: [String] = []
        if (banTypes & UInt32(BANTYPE_IPADDR.rawValue)) != 0   { parts.append(L10n.text("bans.type.ip")) }
        if (banTypes & UInt32(BANTYPE_USERNAME.rawValue)) != 0 { parts.append(L10n.text("bans.type.username")) }
        if (banTypes & UInt32(BANTYPE_CHANNEL.rawValue)) != 0  { parts.append(L10n.text("bans.type.channel")) }
        return parts.joined(separator: ", ")
    }

    var displayName: String {
        nickname.isEmpty ? username : nickname
    }
}

// MARK: - User account model

enum UserAccountType {
    case defaultUser
    case admin
    case disabled
}

struct UserAccountProperties {
    var username: String
    var password: String
    var userType: UserAccountType
    var userRights: UInt32
    var initChannel: String
    var note: String
    var audioBpsLimit: Int32
    var commandsLimit: Int32
    var commandsIntervalMSec: Int32

    static let defaultUserRights: UInt32 = {
        let bits: [UInt32] = [
            UInt32(USERRIGHT_MULTI_LOGIN.rawValue),
            UInt32(USERRIGHT_VIEW_ALL_USERS.rawValue),
            UInt32(USERRIGHT_CREATE_TEMPORARY_CHANNEL.rawValue),
            UInt32(USERRIGHT_UPLOAD_FILES.rawValue),
            UInt32(USERRIGHT_DOWNLOAD_FILES.rawValue),
            UInt32(USERRIGHT_TRANSMIT_VOICE.rawValue),
            UInt32(USERRIGHT_TEXTMESSAGE_USER.rawValue),
            UInt32(USERRIGHT_TEXTMESSAGE_CHANNEL.rawValue)
        ]
        return bits.reduce(0, |)
    }()

    init() {
        username = ""
        password = ""
        userType = .defaultUser
        userRights = UserAccountProperties.defaultUserRights
        initChannel = ""
        note = ""
        audioBpsLimit = 0
        commandsLimit = 0
        commandsIntervalMSec = 0
    }
}

enum PrivateMessagesPresentationReason {
    case userInitiated
    case incomingMessage
}

enum TeamTalkConnectionError: LocalizedError {
    case sdkUnavailable
    case connectionStartFailed
    case loginStartFailed
    case connectionFailed
    case connectionTimeout
    case loginFailed(String)
    case incorrectChannelPassword(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return L10n.text("teamtalk.connection.error.sdkUnavailable")
        case .connectionStartFailed:
            return L10n.text("teamtalk.connection.error.connectionStartFailed")
        case .loginStartFailed:
            return L10n.text("teamtalk.connection.error.loginStartFailed")
        case .connectionFailed:
            return L10n.text("teamtalk.connection.error.connectionFailed")
        case .connectionTimeout:
            return L10n.text("teamtalk.connection.error.timeout")
        case .loginFailed(let message), .incorrectChannelPassword(let message), .internalError(let message):
            return message
        }
    }
}

struct TeamTalkConnectOptions {
    var nicknameOverride: String?
    var statusMessage: String?
    var genderOverride: TeamTalkGender?
    var initialChannelPath: String?
    var initialChannelPassword: String
    var preferJoinLastChannelFromServer: Bool

    init(
        nicknameOverride: String? = nil,
        statusMessage: String? = nil,
        genderOverride: TeamTalkGender? = nil,
        initialChannelPath: String? = nil,
        initialChannelPassword: String = "",
        preferJoinLastChannelFromServer: Bool = false
    ) {
        self.nicknameOverride = nicknameOverride
        self.statusMessage = statusMessage
        self.genderOverride = genderOverride
        self.initialChannelPath = initialChannelPath
        self.initialChannelPassword = initialChannelPassword
        self.preferJoinLastChannelFromServer = preferJoinLastChannelFromServer
    }
}

final class TeamTalkConnectionController {
    private struct SessionPublishInvalidation: OptionSet {
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

    private let queueKey = DispatchSpecificKey<Void>()
    private let queue = DispatchQueue(label: "com.math65.ttaccessible.teamtalk")
    private let clientName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TTAccessible"
    private let preferencesStore: AppPreferencesStore
    let userVolumeStore = UserVolumeStore()
    private let lastChannelStore = LastChannelStore()
    private let audioDiagnosticsLogger = AudioDiagnosticsLogger.shared
    private let performanceLogger = AppPerformanceLogger.shared

    @MainActor weak var delegate: TeamTalkConnectionControllerDelegate?
    @MainActor private(set) var sessionSnapshot: ConnectedServerSession?
    @MainActor private(set) var isConnected = false

    private var instance: UnsafeMutableRawPointer?
    private var pollTimer: DispatchSourceTimer?
    private var connectedRecord: SavedServerRecord?
    private var channelChatHistory: [ChannelChatMessage] = []
    private var sessionHistory: [SessionHistoryEntry] = []
    private var activeTransferProgress: [Int32: FileTransferProgress] = [:]
    private var pendingTextMessages: [UInt64: [TextMessage]] = [:]
    private var pendingChannelMessageCommandIDs = Set<Int32>()
    private var observedSubscriptionStates: [Int32: [UserSubscriptionOption: Bool]] = [:]
    private var suppressLoginHistoryDepth = 0
    private var suppressJoinHistoryDepth = 0
    private var suppressLoginHistoryUntil = Date.distantPast
    private var suppressJoinHistoryUntil = Date.distantPast
    private var channelPasswords: [Int32: String] = [:]
    private var privateConversations: [Int32: PrivateConversation] = [:]
    private var selectedPrivateConversationUserID: Int32?
    private var visiblePrivateConversationUserID: Int32?
    private var isPrivateMessagesWindowVisible = false
    private var outputAudioReady = false
    private var inputAudioReady = false
    private var voiceTransmissionEnabled = false
    private var teamTalkVirtualInputReady = false
    private var advancedMicrophoneTargetFormat: AdvancedMicrophoneAudioTargetFormat?
    private var insertedAudioChunkCount = 0
    private var failedAudioChunkInsertCount = 0
    private var lastLoggedAudioInputQueueBucket: UInt32?
    private var reconnectTimer: DispatchSourceTimer?
    private var reconnectRecord: SavedServerRecord?
    private var reconnectPassword: String?
    private var reconnectOptions = TeamTalkConnectOptions()
    private var lastChannelID: Int32 = 0
    private var isAutoAwayActive = false
    private var autoAwayRestoreStatusMessage = ""
    private var pendingUserAccounts: [UserAccountProperties] = []
    private var listUserAccountsCmdID: Int32 = -1
    private var pendingBannedUsers: [BannedUserProperties] = []
    private var listBansCmdID: Int32 = -1
    private var lastBuiltSessionSnapshot: ConnectedServerSession?
    private var cachedSoundDevices: [SoundDevice] = []
    private var cachedAudioDeviceCatalog: AudioDeviceCatalog?
    private lazy var advancedMicrophoneEngine = AdvancedMicrophoneAudioEngine(diagnosticsScope: "audio-teamtalk-capture") { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }

    private lazy var appleVoiceChatEngine = AppleVoiceChatAudioEngine(diagnosticsScope: "audio-apple-voicechat") { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        queue.setSpecific(key: queueKey, value: ())
    }

    private func logAudio(_ message: String) {
        audioDiagnosticsLogger.log("audio", message)
    }

    private var isAnyMicrophoneEngineRunning: Bool {
        advancedMicrophoneEngine.isRunning || appleVoiceChatEngine.isRunning
    }

    private func describe(_ preset: InputChannelPreset) -> String {
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

    private func describeLimiter(_ preferences: AdvancedInputAudioPreferences) -> String {
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

    private func describeDynamicProcessor(_ preferences: AdvancedInputAudioPreferences) -> String {
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

    func applyDefaultSubscriptionPreferences() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, let record = self.connectedRecord else {
                return
            }
            self.applyDefaultSubscriptionPreferencesLocked(instance: instance, preferences: self.preferencesStore.preferences)
            self.publishSessionLocked(instance: instance, record: record)
        }
    }

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

    func changeNickname(to nickname: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.identity.error.emptyNickname"))))
                }
                return
            }

            let commandID = trimmed.withCString { TT_DoChangeNickname(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
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

    func changeStatus(
        mode: TeamTalkStatusMode,
        message: String,
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

            let currentUser = self.currentUserLocked(instance: instance)
            self.clearAutoAwayStateLocked()
            let mergedMode = mode.merged(with: currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue)
            let commandID = message.withCString { messagePointer in
                TT_DoChangeStatus(instance, mergedMode, messagePointer)
            }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                if mode == .question {
                    SoundPlayer.shared.play(.questionMode)
                }
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

    func changeGender(
        _ gender: TeamTalkGender,
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

            let currentUser = self.currentUserLocked(instance: instance)
            let currentBitmask = currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue
            let currentMode = TeamTalkStatusMode(bitmask: currentBitmask)
            let mergedMode = currentMode.merged(with: gender.merged(with: currentBitmask))
            let currentStatusMessage = currentUser.map { self.ttString(from: $0.szStatusMsg) } ?? ""

            let commandID = currentStatusMessage.withCString { messagePointer in
                TT_DoChangeStatus(instance, mergedMode, messagePointer)
            }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
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

    func joinChannel(
        id channelID: Int32,
        password: String = "",
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

            let commandID = password.withCString { passwordPointer in
                TT_DoJoinChannelByID(instance, channelID, passwordPointer)
            }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.withSuppressedJoinHistoryLocked {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                }
                self.channelPasswords[channelID] = password
                self.appendJoinedChannelHistoryLocked(channelID: channelID, instance: instance)
                self.saveLastChannelLocked(channelID: channelID, instance: instance)
                if self.voiceTransmissionEnabled, self.isAnyMicrophoneEngineRunning {
                    self.refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
                }
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

    struct ChannelProperties {
        var name: String
        var topic: String
        var password: String
        var maxUsers: Int32
        var isPermanent: Bool
        var isSoloTransmit: Bool
        var isNoVoiceActivation: Bool
        var isNoRecording: Bool
    }

    struct ChannelInfo {
        let id: Int32
        let parentID: Int32
        let name: String
        let topic: String
        let password: String
        let maxUsers: Int32
        let isPermanent: Bool
        let isSoloTransmit: Bool
        let isNoVoiceActivation: Bool
        let isNoRecording: Bool
    }

    func channelInfo(forChannelID channelID: Int32) -> ChannelInfo? {
        var channel = Channel()
        guard let instance, TT_GetChannel(instance, channelID, &channel) != 0 else {
            return nil
        }
        let chanType = channel.uChannelType
        return ChannelInfo(
            id: channel.nChannelID,
            parentID: channel.nParentID,
            name: ttString(from: channel.szName),
            topic: ttString(from: channel.szTopic),
            password: ttString(from: channel.szPassword),
            maxUsers: channel.nMaxUsers,
            isPermanent: (chanType & UInt32(CHANNEL_PERMANENT.rawValue)) != 0,
            isSoloTransmit: (chanType & UInt32(CHANNEL_SOLO_TRANSMIT.rawValue)) != 0,
            isNoVoiceActivation: (chanType & UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue)) != 0,
            isNoRecording: (chanType & UInt32(CHANNEL_NO_RECORDING.rawValue)) != 0
        )
    }

    func createChannel(
        parentID: Int32,
        properties: ChannelProperties,
        joinAfterCreate: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var chan = Channel()
            chan.nParentID = parentID
            self.copyTTString(properties.name, into: &chan.szName)
            self.copyTTString(properties.topic, into: &chan.szTopic)
            self.copyTTString(properties.password, into: &chan.szPassword)
            chan.nMaxUsers = properties.maxUsers

            var chanType: UInt32 = UInt32(CHANNEL_DEFAULT.rawValue)
            if properties.isPermanent { chanType |= UInt32(CHANNEL_PERMANENT.rawValue) }
            if properties.isSoloTransmit { chanType |= UInt32(CHANNEL_SOLO_TRANSMIT.rawValue) }
            if properties.isNoVoiceActivation { chanType |= UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue) }
            if properties.isNoRecording { chanType |= UInt32(CHANNEL_NO_RECORDING.rawValue) }
            chan.uChannelType = chanType

            // Copy audio codec from parent channel
            var parentChan = Channel()
            if TT_GetChannel(instance, parentID, &parentChan) != 0 {
                chan.audiocodec = parentChan.audiocodec
            }

            if joinAfterCreate {
                let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoJoinChannel(instance, $0) }
                guard commandID > 0 else {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                    return
                }
                do {
                    try self.withSuppressedJoinHistoryLocked {
                        try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                    }
                    self.channelPasswords[TT_GetMyChannelID(instance)] = properties.password
                    self.publishSessionLocked(instance: instance, record: record)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } else {
                let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoMakeChannel(instance, $0) }
                guard commandID > 0 else {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                    return
                }
                do {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                    self.publishSessionLocked(instance: instance, record: record)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    func updateChannel(
        channelID: Int32,
        properties: ChannelProperties,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var chan = Channel()
            guard TT_GetChannel(instance, channelID, &chan) != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            self.copyTTString(properties.name, into: &chan.szName)
            self.copyTTString(properties.topic, into: &chan.szTopic)
            self.copyTTString(properties.password, into: &chan.szPassword)
            chan.nMaxUsers = properties.maxUsers

            var chanType: UInt32 = chan.uChannelType
            // Clear the flags we manage
            let managedFlags: UInt32 = UInt32(CHANNEL_PERMANENT.rawValue)
                | UInt32(CHANNEL_SOLO_TRANSMIT.rawValue)
                | UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue)
                | UInt32(CHANNEL_NO_RECORDING.rawValue)
            chanType &= ~managedFlags
            if properties.isPermanent { chanType |= UInt32(CHANNEL_PERMANENT.rawValue) }
            if properties.isSoloTransmit { chanType |= UInt32(CHANNEL_SOLO_TRANSMIT.rawValue) }
            if properties.isNoVoiceActivation { chanType |= UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue) }
            if properties.isNoRecording { chanType |= UInt32(CHANNEL_NO_RECORDING.rawValue) }
            chan.uChannelType = chanType

            let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoUpdateChannel(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func deleteChannel(
        channelID: Int32,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            let commandID = TT_DoRemoveChannel(instance, channelID)
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Transferts de fichiers

    func sendFile(toChannelID channelID: Int32, localPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let result = localPath.withCString { TT_DoSendFile(instance, channelID, $0) }
            DispatchQueue.main.async {
                if result > 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("files.error.uploadFailed"))))
                }
            }
        }
    }

    func receiveFile(fromChannelID channelID: Int32, fileID: Int32, toLocalPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let result = toLocalPath.withCString { TT_DoRecvFile(instance, channelID, fileID, $0) }
            DispatchQueue.main.async {
                if result > 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("files.error.downloadFailed"))))
                }
            }
        }
    }

    func cancelFileTransfer(transferID: Int32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            TT_CancelFileTransfer(instance, transferID)
        }
    }

    func deleteChannelFile(channelID: Int32, fileID: Int32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let result = TT_DoDeleteFile(instance, channelID, fileID)
            DispatchQueue.main.async {
                if result > 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("files.error.deleteFailed"))))
                }
            }
        }
    }

    // MARK: - User account management

    func listUserAccounts() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            let cmdID = TT_DoListUserAccounts(instance, 0, 100000)
            if cmdID > 0 {
                self.pendingUserAccounts = []
                self.listUserAccountsCmdID = cmdID
            }
        }
    }

    func createUserAccount(_ account: UserAccountProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            var sdkAccount = self.makeSDKAccount(from: account)
            let cmdID = TT_DoNewUserAccount(instance, &sdkAccount)
            if cmdID > 0 {
                do {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: cmdID)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError("createUserAccount failed"))) }
            }
        }
    }

    func updateUserAccount(originalUsername: String, updated account: UserAccountProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            do {
                // SDK has no update: delete then recreate
                let deleteCmdID = originalUsername.withCString { TT_DoDeleteUserAccount(instance, $0) }
                if deleteCmdID > 0 {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: deleteCmdID)
                }
                var sdkAccount = self.makeSDKAccount(from: account)
                let createCmdID = TT_DoNewUserAccount(instance, &sdkAccount)
                if createCmdID > 0 {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: createCmdID)
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError("updateUserAccount create failed"))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func deleteUserAccount(username: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let cmdID = username.withCString { TT_DoDeleteUserAccount(instance, $0) }
            if cmdID > 0 {
                do {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: cmdID)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError("deleteUserAccount failed"))) }
            }
        }
    }

    private func makeSDKAccount(from properties: UserAccountProperties) -> UserAccount {
        var account = UserAccount()
        copyTTString(properties.username, into: &account.szUsername)
        copyTTString(properties.password, into: &account.szPassword)
        switch properties.userType {
        case .admin:
            account.uUserType = UInt32(USERTYPE_ADMIN.rawValue)
        case .defaultUser:
            account.uUserType = UInt32(USERTYPE_DEFAULT.rawValue)
        case .disabled:
            account.uUserType = UInt32(USERTYPE_NONE.rawValue)
        }
        account.uUserRights = properties.userRights
        copyTTString(properties.initChannel, into: &account.szInitChannel)
        copyTTString(properties.note, into: &account.szNote)
        account.nAudioCodecBpsLimit = properties.audioBpsLimit
        account.abusePrevent.nCommandsLimit = properties.commandsLimit
        account.abusePrevent.nCommandsIntervalMSec = properties.commandsIntervalMSec
        return account
    }

    private func makeUserAccountProperties(from account: UserAccount) -> UserAccountProperties {
        var props = UserAccountProperties()
        props.username = ttString(from: account.szUsername)
        props.password = ""  // SDK does not return plaintext passwords
        if (account.uUserType & UInt32(USERTYPE_ADMIN.rawValue)) != 0 {
            props.userType = .admin
        } else if account.uUserType == UInt32(USERTYPE_DEFAULT.rawValue) {
            props.userType = .defaultUser
        } else {
            props.userType = .disabled
        }
        props.userRights = account.uUserRights
        props.initChannel = ttString(from: account.szInitChannel)
        props.note = ttString(from: account.szNote)
        props.audioBpsLimit = account.nAudioCodecBpsLimit
        props.commandsLimit = account.abusePrevent.nCommandsLimit
        props.commandsIntervalMSec = account.abusePrevent.nCommandsIntervalMSec
        return props
    }

    // MARK: - Ban management

    func listBans() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            let cmdID = TT_DoListBans(instance, 0, 0, 100000)
            if cmdID > 0 {
                self.pendingBannedUsers = []
                self.listBansCmdID = cmdID
            }
        }
    }

    func kickAndBanUser(userID: Int32, banTypes: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let banCmdID = TT_DoBanUserEx(instance, userID, banTypes)
            let kickCmdID = TT_DoKickUser(instance, userID, 0)
            DispatchQueue.main.async {
                completion(banCmdID > 0 && kickCmdID > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError("kickAndBanUser failed")))
            }
        }
    }

    func addBan(_ ban: BannedUserProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            var sdkBan = BannedUser()
            self.copyTTString(ban.ipAddress, into: &sdkBan.szIPAddress)
            self.copyTTString(ban.username, into: &sdkBan.szUsername)
            self.copyTTString(ban.channelPath, into: &sdkBan.szChannelPath)
            sdkBan.uBanTypes = ban.banTypes
            let cmdID = TT_DoBan(instance, &sdkBan)
            DispatchQueue.main.async {
                completion(cmdID > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError("addBan failed")))
            }
        }
    }

    func removeBan(_ ban: BannedUserProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            var sdkBan = BannedUser()
            self.copyTTString(ban.ipAddress, into: &sdkBan.szIPAddress)
            self.copyTTString(ban.username, into: &sdkBan.szUsername)
            self.copyTTString(ban.channelPath, into: &sdkBan.szChannelPath)
            sdkBan.uBanTypes = ban.banTypes
            let cmdID = TT_DoUnBanUserEx(instance, &sdkBan)
            DispatchQueue.main.async {
                completion(cmdID > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError("removeBan failed")))
            }
        }
    }

    private func makeBannedUserProperties(from ban: BannedUser) -> BannedUserProperties {
        BannedUserProperties(
            ipAddress:   ttString(from: ban.szIPAddress),
            channelPath: ttString(from: ban.szChannelPath),
            banTime:     ttString(from: ban.szBanTime),
            nickname:    ttString(from: ban.szNickname),
            username:    ttString(from: ban.szUsername),
            banTypes:    ban.uBanTypes,
            owner:       ttString(from: ban.szOwner)
        )
    }

    private func handleFileTransferEventLocked(_ transfer: FileTransfer) {
        switch transfer.nStatus {
        case FILETRANSFER_ACTIVE:
            activeTransferProgress[transfer.nTransferID] = FileTransferProgress(
                transferID: transfer.nTransferID,
                fileName: ttString(from: transfer.szRemoteFileName),
                transferred: transfer.nTransferred,
                total: transfer.nFileSize,
                isDownload: transfer.bInbound != 0
            )
        case FILETRANSFER_FINISHED:
            activeTransferProgress.removeValue(forKey: transfer.nTransferID)
            SoundPlayer.shared.play(.fileTxComplete)
            let fileName = ttString(from: transfer.szRemoteFileName)
            let isDownload = transfer.bInbound != 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.teamTalkConnectionController(self, didFinishFileTransfer: fileName, isDownload: isDownload, success: true)
            }
        case FILETRANSFER_ERROR:
            activeTransferProgress.removeValue(forKey: transfer.nTransferID)
            let fileName = ttString(from: transfer.szRemoteFileName)
            let isDownload = transfer.bInbound != 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.teamTalkConnectionController(self, didFinishFileTransfer: fileName, isDownload: isDownload, success: false)
            }
        default:
            break
        }
    }

    func kickUser(userID: Int32, channelID: Int32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let result = TT_DoKickUser(instance, userID, channelID)
            DispatchQueue.main.async {
                completion(result > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.action.kickFailed"))))
            }
        }
    }

    func muteUser(userID: Int32, mute: Bool) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_SetUserMute(instance, userID, STREAMTYPE_VOICE, mute ? 1 : 0)
        }
    }

    func moveUser(userID: Int32, toChannelID: Int32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let result = TT_DoMoveUser(instance, userID, toChannelID)
            DispatchQueue.main.async {
                completion(result > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.action.moveFailed"))))
            }
        }
    }

    func queryServerStats() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_DoQueryServerStats(instance)
        }
    }

    func getServerProperties() -> ServerPropertiesData? {
        var result: ServerPropertiesData?
        queue.sync { [weak self] in
            guard let self, let instance = self.instance else { return }
            var sp = ServerProperties()
            guard TT_GetServerProperties(instance, &sp) != 0 else { return }
            result = ServerPropertiesData(
                name: self.ttString(from: sp.szServerName),
                motdRaw: self.ttString(from: sp.szMOTDRaw),
                maxUsers: sp.nMaxUsers,
                userTimeout: sp.nUserTimeout,
                loginDelayMSec: sp.nLoginDelayMSec,
                maxLoginAttempts: sp.nMaxLoginAttempts,
                maxLoginsPerIPAddress: sp.nMaxLoginsPerIPAddress,
                autoSave: sp.bAutoSave != 0,
                maxVoiceTxPerSecond: sp.nMaxVoiceTxPerSecond,
                maxVideoCaptureTxPerSecond: sp.nMaxVideoCaptureTxPerSecond,
                maxMediaFileTxPerSecond: sp.nMaxMediaFileTxPerSecond,
                maxDesktopTxPerSecond: sp.nMaxDesktopTxPerSecond,
                maxTotalTxPerSecond: sp.nMaxTotalTxPerSecond
            )
        }
        return result
    }

    func updateServerProperties(_ props: ServerPropertiesData, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var sp = ServerProperties()
            guard TT_GetServerProperties(instance, &sp) != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            self.copyTTString(props.name, into: &sp.szServerName)
            self.copyTTString(props.motdRaw, into: &sp.szMOTDRaw)
            sp.nMaxUsers = props.maxUsers
            sp.nUserTimeout = props.userTimeout
            sp.nLoginDelayMSec = props.loginDelayMSec
            sp.nMaxLoginAttempts = props.maxLoginAttempts
            sp.nMaxLoginsPerIPAddress = props.maxLoginsPerIPAddress
            sp.bAutoSave = props.autoSave ? 1 : 0
            sp.nMaxVoiceTxPerSecond = props.maxVoiceTxPerSecond
            sp.nMaxVideoCaptureTxPerSecond = props.maxVideoCaptureTxPerSecond
            sp.nMaxMediaFileTxPerSecond = props.maxMediaFileTxPerSecond
            sp.nMaxDesktopTxPerSecond = props.maxDesktopTxPerSecond
            sp.nMaxTotalTxPerSecond = props.maxTotalTxPerSecond

            let commandID = withUnsafeMutablePointer(to: &sp) { TT_DoUpdateServer(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func setUserVoiceVolume(userID: Int32, username: String, volume: Int32) {
        userVolumeStore.setVolume(volume, forUsername: username)
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_SetUserVolume(instance, userID, STREAMTYPE_VOICE, volume)
        }
    }

    func leaveCurrentChannel(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let commandID = TT_DoLeaveChannel(instance)
            let previousChannelID = TT_GetMyChannelID(instance)
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.withSuppressedJoinHistoryLocked {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                }
                if previousChannelID > 0 {
                    self.appendLeftChannelHistoryLocked(channelID: previousChannelID, instance: instance)
                }
                if self.voiceTransmissionEnabled, self.isAnyMicrophoneEngineRunning {
                    self.refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
                }
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

    func setSubscription(
        _ option: UserSubscriptionOption,
        forUserIDs userIDs: [Int32],
        enabled: Bool,
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

            let uniqueUserIDs = Array(Set(userIDs)).sorted()
            guard uniqueUserIDs.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("subscriptions.error.noSelectedUser"))))
                }
                return
            }

            for userID in uniqueUserIDs {
                let commandID = self.setSubscriptionLocked(instance: instance, userID: userID, option: option, enabled: enabled)
                guard commandID > 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(TeamTalkConnectionError.internalError(L10n.text("subscriptions.error.updateFailed"))))
                    }
                    return
                }
                let userName = self.displayName(forUserID: userID, instance: instance)
                self.updateObservedSubscriptionStateLocked(option, enabled: enabled, userID: userID)
                self.appendSubscriptionHistoryLocked(
                    option,
                    userName: userName,
                    enabled: enabled,
                    userID: userID
                )
            }

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

    private func createInstanceLocked() throws -> UnsafeMutableRawPointer {
        guard let instance = TT_InitTeamTalkPoll() else {
            throw TeamTalkConnectionError.sdkUnavailable
        }
        return instance
    }


    private func withSuppressedLoginHistoryLocked<T>(_ body: () throws -> T) rethrows -> T {
        suppressLoginHistoryDepth += 1
        defer {
            suppressLoginHistoryDepth = max(0, suppressLoginHistoryDepth - 1)
            suppressLoginHistoryUntil = max(suppressLoginHistoryUntil, Date().addingTimeInterval(1.5))
        }
        return try body()
    }

    private func withSuppressedJoinHistoryLocked<T>(_ body: () throws -> T) rethrows -> T {
        suppressJoinHistoryDepth += 1
        defer {
            suppressJoinHistoryDepth = max(0, suppressJoinHistoryDepth - 1)
            suppressJoinHistoryUntil = max(suppressJoinHistoryUntil, Date().addingTimeInterval(1.5))
        }
        return try body()
    }

    private var isSuppressingLoginHistoryLocked: Bool {
        suppressLoginHistoryDepth > 0 || Date() < suppressLoginHistoryUntil
    }

    private var isSuppressingJoinHistoryLocked: Bool {
        suppressJoinHistoryDepth > 0 || Date() < suppressJoinHistoryUntil
    }

    private var isSuppressingFileHistoryLocked: Bool {
        isSuppressingLoginHistoryLocked || isSuppressingJoinHistoryLocked
    }

    // MARK: - Reconnexion automatique

    private func startReconnectTimerLocked() {
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

    private func attemptReconnectLocked() {
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

    private func cancelReconnectLocked() {
        reconnectTimer?.setEventHandler {}
        reconnectTimer?.cancel()
        reconnectTimer = nil
        reconnectRecord = nil
        reconnectPassword = nil
        reconnectOptions = TeamTalkConnectOptions()
        lastChannelID = 0
    }

    private func publishReconnecting() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.teamTalkConnectionControllerDidStartReconnecting(self)
        }
    }

    private func autoJoinAfterLoginLocked(instance: UnsafeMutableRawPointer) {
        autoJoinAfterLoginLocked(instance: instance, options: TeamTalkConnectOptions())
    }

    private func autoJoinAfterLoginLocked(instance: UnsafeMutableRawPointer, options: TeamTalkConnectOptions) {
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

    private func connectAndLoginLocked(
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

    private func applyPostLoginOptionsLocked(
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

    private func nextMessageLocked(
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

    private func startPollingLocked() {
        stopPollingLocked()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.drainMessagesLocked()
        }
        pollTimer = timer
        timer.resume()
    }

    private func stopPollingLocked() {
        pollTimer?.setEventHandler {}
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func drainMessagesLocked() {
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

    private func resetLocked() {
        destroyLocked()
    }

    private func destroyLocked() {
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

    private func clearAutoAwayStateLocked() {
        isAutoAwayActive = false
        autoAwayRestoreStatusMessage = ""
    }

    private func currentIdleSecondsLocked() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else {
            return 0
        }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as NSDictionary?,
              let idleTime = dictionary["HIDIdleTime"] as? NSNumber else {
            return 0
        }

        return Double(idleTime.uint64Value) / 1_000_000_000
    }

    private func updateAutoAwayIfNeededLocked(instance: UnsafeMutableRawPointer) -> Bool {
        guard (TT_GetFlags(instance) & UInt32(CLIENT_AUTHORIZED.rawValue)) != 0 else {
            if isAutoAwayActive {
                clearAutoAwayStateLocked()
            }
            return false
        }

        let timeoutMinutes = preferencesStore.preferences.autoAwayTimeoutMinutes
        guard timeoutMinutes > 0 else {
            if isAutoAwayActive {
                return deactivateAutoAwayLocked(instance: instance)
            }
            return false
        }

        guard let currentUser = currentUserLocked(instance: instance) else {
            if isAutoAwayActive {
                clearAutoAwayStateLocked()
            }
            return false
        }

        let currentMode = TeamTalkStatusMode(bitmask: currentUser.nStatusMode)
        if isAutoAwayActive, currentMode != .away {
            clearAutoAwayStateLocked()
            return false
        }

        let idleSeconds = currentIdleSecondsLocked()
        let threshold = Double(timeoutMinutes * 60)

        if isAutoAwayActive {
            guard idleSeconds < threshold else {
                return false
            }
            return deactivateAutoAwayLocked(instance: instance)
        }

        guard currentMode == .available, idleSeconds >= threshold else {
            return false
        }

        let currentStatusMessage = ttString(from: currentUser.szStatusMsg)
        autoAwayRestoreStatusMessage = currentStatusMessage
        let awayStatusMessage = preferencesStore.preferences.autoAwayStatusMessage.isEmpty
            ? currentStatusMessage
            : preferencesStore.preferences.autoAwayStatusMessage
        let awayBitmask = TeamTalkStatusMode.away.merged(with: currentUser.nStatusMode)
        let commandID = awayStatusMessage.withCString { TT_DoChangeStatus(instance, awayBitmask, $0) }
        guard commandID > 0 else {
            clearAutoAwayStateLocked()
            return false
        }

        do {
            try waitForCommandCompletionLocked(instance: instance, commandID: commandID)
            isAutoAwayActive = true
            appendAutoAwayActivatedHistoryLocked()
            return true
        } catch {
            clearAutoAwayStateLocked()
            return false
        }
    }

    private func deactivateAutoAwayLocked(instance: UnsafeMutableRawPointer) -> Bool {
        guard isAutoAwayActive, let currentUser = currentUserLocked(instance: instance) else {
            clearAutoAwayStateLocked()
            return false
        }

        let restoredMessage = autoAwayRestoreStatusMessage
        let restoredBitmask = TeamTalkStatusMode.available.merged(with: currentUser.nStatusMode)
        let commandID = restoredMessage.withCString { TT_DoChangeStatus(instance, restoredBitmask, $0) }
        guard commandID > 0 else {
            clearAutoAwayStateLocked()
            return false
        }

        do {
            try waitForCommandCompletionLocked(instance: instance, commandID: commandID)
            clearAutoAwayStateLocked()
            appendAutoAwayDeactivatedHistoryLocked()
            return true
        } catch {
            return false
        }
    }

    private func clientErrorMessage(from message: TTMessage) -> String? {
        guard message.ttType == __CLIENTERRORMSG else {
            return nil
        }

        let value = ttString(from: message.clienterrormsg.szErrorMsg)
        return value.isEmpty ? nil : value
    }

    private func waitForCommandCompletionLocked(
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

    private func publishActiveTransfersLocked(currentChannelID: Int32) {
        let transfers = Array(activeTransferProgress.values)
        performanceLogger.increment("teamtalk.publishActiveTransfers")
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didUpdateActiveTransfers: transfers, currentChannelID: currentChannelID)
        }
    }

    private func publishAudioRuntimeUpdateLocked(instance: UnsafeMutableRawPointer) {
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
        performanceLogger.increment("teamtalk.publishAudioRuntime")
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didUpdateAudioRuntime: update)
        }
    }

    private func publishSessionLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        invalidation: SessionPublishInvalidation = .all
    ) {
        performanceLogger.increment("teamtalk.publishSession")
        let startedAt = performanceLogger.beginInterval("teamtalk.makeSessionSnapshot")
        let snapshot = makeSessionSnapshotLocked(instance: instance, record: record, invalidation: invalidation)
        performanceLogger.endInterval("teamtalk.makeSessionSnapshot", startedAt)
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

    private func publishDisconnected(message: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.sessionSnapshot = nil
            self.isConnected = false
            self.delegate?.teamTalkConnectionController(self, didDisconnectWithMessage: message)
        }
    }

    private func makeSessionSnapshotLocked(
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
            outputGainDB: preferences.outputGainDB
        )
    }

    private func appendHistoryLocked(
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

    private func appendConnectedHistoryLocked(record: SavedServerRecord) {
        appendHistoryLocked(
            kind: .connected,
            message: L10n.format("history.connected", record.name)
        )
    }

    private func appendDisconnectedHistoryLocked() {
        appendHistoryLocked(
            kind: .disconnected,
            message: L10n.text("history.disconnected")
        )
    }

    private func appendConnectionLostHistoryLocked() {
        appendHistoryLocked(
            kind: .connectionLost,
            message: L10n.text("history.connectionLost")
        )
    }

    private func appendAutoAwayActivatedHistoryLocked() {
        appendHistoryLocked(
            kind: .autoAwayActivated,
            message: L10n.text("history.autoAwayActivated")
        )
    }

    private func appendAutoAwayDeactivatedHistoryLocked() {
        appendHistoryLocked(
            kind: .autoAwayDeactivated,
            message: L10n.text("history.autoAwayDeactivated")
        )
    }

    private func saveLastChannelLocked(channelID: Int32, instance: UnsafeMutableRawPointer) {
        guard channelID > 0, let record = connectedRecord else { return }
        var pathBuffer = [TTCHAR](repeating: 0, count: Int(TT_STRLEN))
        guard TT_GetChannelPath(instance, channelID, &pathBuffer) != 0 else { return }
        let path = String(cString: pathBuffer)
        guard !path.isEmpty else { return }
        let serverKey = LastChannelStore.serverKey(host: record.host, tcpPort: record.tcpPort, username: record.username)
        lastChannelStore.setChannelPath(path, forServerKey: serverKey)
    }

    private func appendJoinedChannelHistoryLocked(channelID: Int32, instance: UnsafeMutableRawPointer) {
        appendHistoryLocked(
            kind: .joinedChannel,
            message: L10n.format("history.joinedChannel", historyChannelNameLocked(channelID: channelID, instance: instance)),
            channelID: channelID
        )
    }

    private func appendLeftChannelHistoryLocked(channelID: Int32, instance: UnsafeMutableRawPointer) {
        appendHistoryLocked(
            kind: .leftChannel,
            message: L10n.format("history.leftChannel", historyChannelNameLocked(channelID: channelID, instance: instance)),
            channelID: channelID
        )
    }

    private func appendUserLoggedInHistoryLocked(_ user: User, currentUserID: Int32) {
        guard user.nUserID != currentUserID else {
            return
        }
        appendHistoryLocked(
            kind: .userLoggedIn,
            message: L10n.format("history.userLoggedIn", displayName(for: user)),
            userID: user.nUserID
        )
    }

    private func appendUserLoggedOutHistoryLocked(_ user: User, currentUserID: Int32) {
        guard user.nUserID != currentUserID else {
            return
        }
        appendHistoryLocked(
            kind: .userLoggedOut,
            message: L10n.format("history.userLoggedOut", displayName(for: user)),
            userID: user.nUserID
        )
    }

    private func appendUserJoinedChannelHistoryLocked(
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

    private func appendUserLeftChannelHistoryLocked(
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

    private func appendKickHistoryLocked(_ message: TTMessage, instance: UnsafeMutableRawPointer) {
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

    private func appendFileHistoryLocked(
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

    private func appendTransmissionBlockedHistoryLocked() {
        appendHistoryLocked(
            kind: .transmissionBlocked,
            message: L10n.text("history.transmissionBlocked")
        )
    }

    private func appendBroadcastSentHistoryLocked(senderName: String, content: String, userID: Int32?) {
        appendHistoryLocked(
            kind: .broadcastSent,
            message: L10n.format("history.broadcastSent", senderName, content),
            userID: userID
        )
    }

    private func appendBroadcastReceivedHistoryLocked(
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

    private func appendSubscriptionHistoryLocked(
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

    private func appendSubscriptionHistoryIfNeededLocked(_ user: User) {
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

    private func historyChannelNameLocked(channelID: Int32, instance: UnsafeMutableRawPointer) -> String {
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

    private func historyActorNameLocked(
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

    private func userIDForUsernameLocked(_ username: String, instance: UnsafeMutableRawPointer) -> Int32? {
        guard username.isEmpty == false else {
            return nil
        }

        var user = User()
        guard username.withCString({ TT_GetUserByUsername(instance, $0, &user) != 0 }) else {
            return nil
        }
        return user.nUserID
    }

    @discardableResult
    private func handleTextMessageEventLocked(
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

    private func mergeTextMessageLocked(_ textMessage: TextMessage) -> String? {
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

    private func textMessageMergeKey(for textMessage: TextMessage) -> UInt64 {
        let type = UInt64(UInt32(textMessage.nMsgType.rawValue))
        let fromUserID = UInt64(UInt32(bitPattern: textMessage.nFromUserID))
        let toUserID = UInt64(UInt32(bitPattern: textMessage.nToUserID))
        return (type << 32) | (fromUserID << 16) | toUserID
    }

    private func makeOutgoingChannelTextMessage(channelID: Int32, fromUserID: Int32) -> TextMessage {
        var message = TextMessage()
        message.nMsgType = MSGTYPE_CHANNEL
        message.nFromUserID = fromUserID
        message.nChannelID = channelID
        message.nToUserID = 0
        message.bMore = 0
        return message
    }

    private func makeOutgoingBroadcastTextMessage(fromUserID: Int32) -> TextMessage {
        var message = TextMessage()
        message.nMsgType = MSGTYPE_BROADCAST
        message.nFromUserID = fromUserID
        message.nToUserID = 0
        message.nChannelID = 0
        message.bMore = 0
        return message
    }

    private func makeOutgoingPrivateTextMessage(toUserID: Int32, fromUserID: Int32) -> TextMessage {
        var message = TextMessage()
        message.nMsgType = MSGTYPE_USER
        message.nFromUserID = fromUserID
        message.nToUserID = toUserID
        message.nChannelID = 0
        message.bMore = 0
        return message
    }

    private func buildTextMessages(from baseMessage: TextMessage, content: String) -> [TextMessage] {
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

    private func copyTTString<T>(_ string: String, into target: inout T) {
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

    private func displayName(forUserID userID: Int32, instance: UnsafeMutableRawPointer) -> String {
        var user = User()
        if TT_GetUser(instance, userID, &user) != 0 {
            return displayName(for: user)
        }

        return L10n.format("connectedServer.chat.sender.unknown", String(userID))
    }

    private func currentUserLocked(instance: UnsafeMutableRawPointer) -> User? {
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

    private func ensurePrivateConversationLocked(peerUserID: Int32, peerDisplayName: String) {
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

    private func isUserOnlineLocked(userID: Int32, instance: UnsafeMutableRawPointer) -> Bool {
        var user = User()
        return TT_GetUser(instance, userID, &user) != 0
    }

    private func privatePeerDisplayName(
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

    private func applyDefaultSubscriptionPreferencesLocked(
        instance: UnsafeMutableRawPointer,
        preferences: AppPreferences
    ) {
        let myUserID = TT_GetMyUserID(instance)
        for user in fetchServerUsersLocked(instance: instance) where user.nUserID != myUserID {
            applyDefaultSubscriptionPreferencesLocked(instance: instance, userID: user.nUserID, preferences: preferences)
        }
    }

    private func applyDefaultSubscriptionPreferencesLocked(
        instance: UnsafeMutableRawPointer,
        userID: Int32,
        preferences: AppPreferences
    ) {
        for option in UserSubscriptionOption.allCases {
            let enabled = preferences.isSubscriptionEnabledByDefault(option)
            let commandID = setSubscriptionLocked(instance: instance, userID: userID, option: option, enabled: enabled)
            if commandID > 0 {
                updateObservedSubscriptionStateLocked(option, enabled: enabled, userID: userID)
            }
        }
    }

    @discardableResult
    private func setSubscriptionLocked(
        instance: UnsafeMutableRawPointer,
        userID: Int32,
        option: UserSubscriptionOption,
        enabled: Bool
    ) -> Int32 {
        if enabled {
            return TT_DoSubscribe(instance, userID, Subscriptions(option.subscriptionMask))
        }
        return TT_DoUnsubscribe(instance, userID, Subscriptions(option.subscriptionMask))
    }

    private func updateObservedSubscriptionStateLocked(
        _ option: UserSubscriptionOption,
        enabled: Bool,
        userID: Int32
    ) {
        var states = observedSubscriptionStates[userID] ?? [:]
        states[option] = enabled
        observedSubscriptionStates[userID] = states
    }

    private func publishPrivateMessagesWindowRequest(userID: Int32?, reason: PrivateMessagesPresentationReason) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didRequestPrivateMessagesWindowFor: userID, reason: reason)
        }
    }

    private func publishIncomingTextMessage(_ event: IncomingTextMessageEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.teamTalkConnectionController(self, didReceiveIncomingTextMessage: event)
        }
    }

    private func makeStatusText(
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

    private func ensureOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard outputAudioReady == false else {
            return
        }

        try ensureDirectOutputAudioReadyLocked(instance: instance)
    }

    private func ensureAdvancedMicrophoneInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
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

    private func reinitializeAudioDevicesLocked(
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

    private func makeAudioStatusText() -> String {
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

    private enum AudioDirection {
        case input
        case output
    }

    private func loadSoundDevicesLocked(forceRefresh: Bool) -> [SoundDevice] {
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

    private func availableAudioDevicesLocked(forceRefresh: Bool) -> AudioDeviceCatalog {
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

    private func makeAudioDeviceOption(from device: SoundDevice) -> AudioDeviceOption {
        let persistentID = ttString(from: device.szDeviceID).isEmpty
            ? "legacy:\(device.nDeviceID)"
            : ttString(from: device.szDeviceID)
        return AudioDeviceOption(
            id: persistentID,
            persistentID: persistentID,
            displayName: ttString(from: device.szDeviceName)
        )
    }

    private func ensureDirectOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
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

    private func stopAdvancedMicrophoneInputLocked(instance: UnsafeMutableRawPointer, reason: String) {
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

    private func ensureTeamTalkVirtualInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
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

    private func effectiveMicrophoneProcessingPreferencesLocked(
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

    private func currentAdvancedInputAudioPreferencesLocked(
        preferences: AppPreferences
    ) -> AdvancedInputAudioPreferences {
        let deviceID = InputAudioDeviceResolver.currentInputDeviceID(for: preferences.preferredInputDevice)
        return preferencesStore.advancedInputAudio(for: deviceID)
    }

    private func handleUserAudioBlockEventLocked(
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

    private func insertAdvancedMicrophoneAudioChunkLocked(_ chunk: AdvancedMicrophoneAudioChunk) {
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

    private func chunkLevelStats(_ data: Data) -> (peak: Float, rms: Float) {
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

    private func formatDecibels(_ value: Float) -> String {
        guard value > 0 else {
            return "-inf dBFS"
        }
        return String(format: "%.1f dBFS", 20 * log10(Double(value)))
    }

    private func refreshAdvancedMicrophoneTargetIfNeededLocked(instance: UnsafeMutableRawPointer) {
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

    private func currentAdvancedMicrophoneTargetFormatLocked(instance: UnsafeMutableRawPointer) throws -> AdvancedMicrophoneAudioTargetFormat {
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

    private func sampleRate(forSpeexBandmode bandmode: Int32) -> Double {
        switch bandmode {
        case 1:
            return 16_000
        case 2:
            return 32_000
        default:
            return 8_000
        }
    }

    private func selectedOutputDeviceIDLocked() throws -> INT32 {
        try selectedDeviceIDLocked(
            preference: preferencesStore.preferences.preferredOutputDevice,
            availableDevices: availableAudioDevicesLocked(forceRefresh: false).outputDevices,
            direction: .output
        )
    }

    private func selectedOutputDeviceUIDLocked() throws -> String {
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

    private func systemDefaultOutputDeviceUID() throws -> String {
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

    private func selectedInputDeviceIDLocked() throws -> INT32 {
        try selectedDeviceIDLocked(
            preference: preferencesStore.preferences.preferredInputDevice,
            availableDevices: availableAudioDevicesLocked(forceRefresh: false).inputDevices,
            direction: .input
        )
    }

    private func applyOutputGainLocked(instance: UnsafeMutableRawPointer, gainDB: Double) {
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

    private func selectedDeviceIDLocked(
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

    private func fetchServerChannelsLocked(instance: UnsafeMutableRawPointer) -> [Channel] {
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

    private func fetchServerUsersLocked(instance: UnsafeMutableRawPointer) -> [User] {
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

    private func displayName(for user: User) -> String {
        let nickname = ttString(from: user.szNickname)
        if nickname.isEmpty == false {
            return nickname
        }
        return ttString(from: user.szUsername)
    }

    private func effectiveNickname(for record: SavedServerRecord, override nicknameOverride: String? = nil) -> String {
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

    private func clientVersion(for user: User) -> String {
        "\(user.uVersion >> 16).\((user.uVersion >> 8) & 0xFF).\(user.uVersion & 0xFF)"
    }

    private func ttString<T>(from value: T) -> String {
        var copy = value
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                String(cString: charPointer)
            }
        }
    }
}
