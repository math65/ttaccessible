//
//  TeamTalkConnectionController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
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
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateMediaStreamingProgress progress: MediaStreamingProgress)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateVideoDisplay state: VideoDisplayState)
}

final class TeamTalkConnectionController {
    enum FileTransferCommandKind {
        case upload
        case download
        case delete
    }

    struct PendingFileTransferCommand {
        let kind: FileTransferCommandKind
        let localPath: String?
        let completion: (Result<Void, Error>) -> Void
    }

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


    var audioDeviceChangeMonitor: AudioDeviceChangeMonitor?

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
    var pushToTalkPressed = false
    var pushToTalkShortcutResolver: (() -> Bool)?
    var lastAudioWarningMessage: String?
    var masterMuted = false
    var hearMyselfEnabled = false
    var recordingMuxedActive = false
    var recordingSeparateActive = false
    var recordingFolder: URL?
    var recordingFormat: AudioFileFormat = AFF_WAVE_FORMAT
    var mediaStreamingActive = false
    var mediaStreamingPath: String?
    var mediaStreamingStartedHistoryLogged = false
    var mediaStreamingFileName: String?
    var mediaStreamingSecurityScopedURL: URL?
    var mediaStreamingRestartInFlight = false
    /// True after the user requests pause until the SDK reports `MFS_PAUSED` (blocks spurious `MFS_PLAYING`).
    var mediaStreamingUserPauseIntent = false
    var mediaStreamingPaused = false
    /// Set when the user seeks while paused; resume must re-send that offset because the SDK may not apply seeks until playback.
    var mediaStreamingSeekedWhilePaused = false
    /// Ignore regressive SDK elapsed reports briefly after resume-via-restart.
    var mediaStreamingResumeAnchorMSec: UInt32?
    var mediaStreamingResumeAnchorUntil: Date?
    var mediaStreamingDurationMSec: UInt32 = 0
    var mediaStreamingElapsedMSec: UInt32 = 0
    var mediaStreamingElapsedSampleAt: Date?
    var mediaStreamingBroadcastGainLevel: INT32 = 1000
    var mediaStreamingHasVideo = false
    var mediaStreamingActiveVideoCodec = VideoCodec()
    var mediaStreamingFinalizeSuppressedUntil: Date?
    var activeVideoDisplayUserID: Int32 = 0
    var lastPublishedVideoFrame: VideoFramePayload?
    var lastPublishedVideoFrameUserID: Int32 = 0
    var usersWithPendingMediaVideoFrame = Set<Int32>()
    var teamTalkVirtualInputReady = false
    var advancedMicrophoneTargetFormat: AdvancedMicrophoneAudioTargetFormat?
    var reconnectTimer: DispatchSourceTimer?
    var reconnectRecord: SavedServerRecord?
    var reconnectPassword: String?
    var reconnectOptions = TeamTalkConnectOptions()
    var lastChannelID: Int32 = 0
    var isRestartingSoundSystem = false
    var suppressDeviceChangeUntil = Date.distantPast
    var audioHardwareChangeWorkItem: DispatchWorkItem?
    var lastAudioRoutingSnapshot: AudioRoutingSnapshot?
    var lastAutoAwayCheckTime: CFAbsoluteTime = 0
    var isAutoAwayActive = false
    var autoAwayActivationTime: Date?
    var autoAwayRestoreStatusMessage = ""
    /// Highest HID idle time observed since auto-away activated (input resets pull this down).
    var autoAwayPeakIdleSeconds: Double?
    var pendingUserAccounts: [UserAccountProperties] = []
    var cachedUserAccounts: [UserAccountProperties] = []
    var listUserAccountsCmdID: Int32 = -1
    var pendingBannedUsers: [BannedUserProperties] = []
    var listBansCmdID: Int32 = -1
    var pendingFileTransferCommands: [Int32: PendingFileTransferCommand] = [:]
    var fileTransferCommandIDsByTransferID: [Int32: Int32] = [:]
    var securityScopedFileTransferURLs: [Int32: URL] = [:]
    var lastBuiltSessionSnapshot: ConnectedServerSession?
    var cachedSoundDevices: [SoundDevice] = []
    var cachedAudioDeviceCatalog: AudioDeviceCatalog?
    lazy var advancedMicrophoneEngine = AdvancedMicrophoneAudioEngine { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }
    /// Speaker tap for AEC reference (macOS 14.2+). Typed as Any to avoid availability annotation on stored property.
    var speakerTapCaptureStorage: Any?

    let passwordStore: ServerPasswordStore

    init(preferencesStore: AppPreferencesStore, passwordStore: ServerPasswordStore) {
        self.preferencesStore = preferencesStore
        self.passwordStore = passwordStore
        queue.setSpecific(key: queueKey, value: ())
    }

    // MARK: - Channel passwords

    /// THE accessor for "what password do we have for this channel": the
    /// in-session map first, then the keychain. Every join path — manual,
    /// auto-join, reconnect — resolves through here, so the two stores can't
    /// drift apart.
    ///
    /// Keyed by the SDK's own channel path rather than the display path built
    /// from `pathComponents`: that one is rooted at the SERVER's display name,
    /// which changes when `TT_GetServerProperties` arrives mid-session and again
    /// whenever an admin renames the server — orphaning every saved password.
    func knownChannelPasswordLocked(instance: UnsafeMutableRawPointer, channelID: Int32) -> String {
        guard channelID > 0 else { return "" }
        if let remembered = channelPasswords[channelID], !remembered.isEmpty {
            return remembered
        }
        guard let serverID = connectedRecord?.id else { return "" }
        let path = channelPathLocked(instance: instance, channelID: channelID)
        guard !path.isEmpty else { return "" }
        let saved = (try? passwordStore.channelPassword(for: serverID, channelPath: path)) ?? nil
        if let saved {
            channelPasswords[channelID] = saved
        }
        return saved ?? ""
    }

    /// Record a password that the server accepted, in both stores. Skips the
    /// keychain write when the persisted value is already identical — comparing
    /// against the PERSISTED value, not the in-memory one, which the join path
    /// has already updated by this point.
    func rememberChannelPasswordLocked(instance: UnsafeMutableRawPointer, channelID: Int32, password: String) {
        guard channelID > 0 else { return }
        channelPasswords[channelID] = password
        guard !password.isEmpty, let serverID = connectedRecord?.id else { return }
        let path = channelPathLocked(instance: instance, channelID: channelID)
        guard !path.isEmpty else { return }
        let persisted = (try? passwordStore.channelPassword(for: serverID, channelPath: path)) ?? nil
        guard persisted != password else { return }
        try? passwordStore.setChannelPassword(password, for: serverID, channelPath: path)
    }

    /// Forget a channel password everywhere. Called when the server rejects it:
    /// without this a rotated password is re-submitted on every future join and
    /// pre-filled into the prompt, and cancelling never clears it.
    func forgetChannelPasswordLocked(instance: UnsafeMutableRawPointer, channelID: Int32) {
        guard channelID > 0 else { return }
        channelPasswords.removeValue(forKey: channelID)
        guard let serverID = connectedRecord?.id else { return }
        let path = channelPathLocked(instance: instance, channelID: channelID)
        guard !path.isEmpty else { return }
        try? passwordStore.setChannelPassword(nil, for: serverID, channelPath: path)
    }

    /// Full SDK path of a channel, or "" if unavailable.
    func channelPathLocked(instance: UnsafeMutableRawPointer, channelID: Int32) -> String {
        guard channelID > 0 else { return "" }
        var pathBuffer = [TTCHAR](repeating: 0, count: Int(TT_STRLEN))
        guard TT_GetChannelPath(instance, channelID, &pathBuffer) != 0 else { return "" }
        return String(cString: pathBuffer)
    }

    // Queue-safe wrappers for the UI layer.

    func knownChannelPassword(forChannelID channelID: Int32) -> String {
        queue.sync {
            guard let instance else { return "" }
            return knownChannelPasswordLocked(instance: instance, channelID: channelID)
        }
    }

    func rememberChannelPassword(_ password: String, forChannelID channelID: Int32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            self.rememberChannelPasswordLocked(instance: instance, channelID: channelID, password: password)
        }
    }

    func forgetChannelPassword(forChannelID channelID: Int32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            self.forgetChannelPasswordLocked(instance: instance, channelID: channelID)
        }
    }

    func passwordForChannel(_ channelID: Int32) -> String {
        guard channelID > 0 else {
            return ""
        }

        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return channelPasswords[channelID] ?? ""
        }

        return queue.sync {
            channelPasswords[channelID] ?? ""
        }
    }

    var isAnyMicrophoneEngineRunning: Bool {
        advancedMicrophoneEngine.isRunning
    }

    // MARK: - Audio (see TeamTalkConnectionController+Audio.swift)

    // MARK: - applyDefaultSubscriptionPreferences (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Private messaging (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Identity (see TeamTalkConnectionController+Identity.swift)

    // MARK: - Channel management (see TeamTalkConnectionController+ChannelManagement.swift)

    // MARK: - Administration (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Channel & broadcast messaging (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Connection lifecycle (see TeamTalkConnectionController+Connection.swift)

    // MARK: - Auto-away (see TeamTalkConnectionController+Identity.swift)

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
