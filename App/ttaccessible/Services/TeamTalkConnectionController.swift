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
    /// Dedicated queue for the SDK's TT_GetSoundDevices / TT_InitTeamTalkPoll probes,
    /// kept OFF the main `queue` so they never block connecting or starve the realtime
    /// audio mixer pump. QoS is `.userInitiated` (not `.utility`): the connect path runs
    /// at user-initiated priority and waits on the prewarm done here, so a lower QoS
    /// caused a priority inversion (Thread Performance Checker) that slowed connecting.
    let soundDeviceProbeQueue = DispatchQueue(label: "com.math65.ttaccessible.sounddevices", qos: .userInitiated)
    /// Connection-instance prewarm. `TT_InitTeamTalkPoll` triggers the SDK sound
    /// system init, which enumerates every CoreAudio device (~12 s on a large rig).
    /// The app creates a fresh instance per connect, so that 12 s landed on EVERY
    /// connect. We instead create the next instance ahead of time on the probe
    /// queue (at launch and after disconnect) so connect reuses a ready one.
    var prewarmInFlight = false                              // `queue`-only
    let prewarmReady = DispatchSemaphore(value: 0)
    let prewarmBoxLock = NSLock()
    var prewarmBoxedInstance: UnsafeMutableRawPointer?       // probe queue → `queue`, lock + semaphore guarded
    /// A disconnected-but-still-alive TeamTalk instance kept WARM for reuse. The
    /// SDK re-runs its ~8 s device enumeration every time a fresh instance is
    /// created, so closing the instance on disconnect made every reconnect cold
    /// (~8 s). Keeping it (TT_Disconnect, not TT_CloseTeamTalk) makes reconnects
    /// reuse the warm instance and connect in ~1 s. `queue`-only.
    var reusableInstance: UnsafeMutableRawPointer?
    let clientName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "tt-Accessible"
    let preferencesStore: AppPreferencesStore
    let userVolumeStore = UserVolumeStore()
    let lastChannelStore = LastChannelStore()
    let bearWareCredentialStore = BearWareCredentialStore()
    let bearWareWebLoginClient = BearWareWebLoginClient()


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
    // The input/output device preferences currently open in the SDK, so a
    // preference change can reinitialize only the device that actually changed
    // (avoids needlessly closing the output — and its intermittent SDK deadlock —
    // when only the input changed, and vice versa).
    var appliedInputPreference: AudioDevicePreference?
    var appliedOutputPreference: AudioDevicePreference?
    /// The microphone processing preferences (preset + AEC/noise-suppression mode)
    /// currently live in the running capture engine. Used to detect a processing-only
    /// change (same device) so we can rebuild the engine without a device switch.
    var appliedAdvancedInputAudio: AdvancedInputAudioPreferences?
    var voiceTransmissionEnabled = false
    var pushToTalkPressed = false
    /// Queue-side caches of the hotkey-relevant preferences: the per-chunk
    /// transmit gate must not read the @Published preferences struct across
    /// threads. Seeded at init, updated via applyMicrophoneHotkeySettings.
    var cachedMicrophoneMode: AppPreferences.MicrophoneMode = .alwaysOn
    var cachedPushToTalkKeyConfigured = false
    /// "Both" mode only: the always-on gate toggled by ⌘⇧A. The mic engine stays
    /// hot (voiceTransmissionEnabled) the whole time so PTT is instant; this
    /// lightweight flag decides whether captured audio is transmitted when PTT
    /// is not held. Releasing PTT closes it (see setPushToTalkPressed).
    var bothGateOpen = false
    var lastAudioWarningMessage: String?
    var masterMuted = false
    var hearMyselfEnabled = false
    // When connected, the Audio-preferences mic preview can't open a second capture
    // on the input device (the live mic engine owns it), so instead it monitors the
    // live mic through the output engine — same path as hearMyself, gated separately.
    var previewMonitorEnabled = false
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
    /// Coalescing for the media panel's high-frequency controls: gain updates
    /// and seeks are expensive SDK calls, and key-repeat floods otherwise queue
    /// a backlog that keeps adjusting after the user releases the key.
    let mediaStreamingGainRequest = CoalescedRequest<Int>()
    let mediaStreamingSeekRequest = CoalescedRequest<UInt32>()
    /// Live capture + loopback server when the active media stream sources an
    /// audio device (nil for file/URL streams).
    var deviceStreamSource: AudioDeviceStreamSource?
    /// Whether the local user hears their own device stream back (chosen per
    /// stream in the start dialog; file/URL streams always self-monitor).
    var deviceStreamMonitorEnabled = false
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
    /// Lowercased-username → nickname of currently-online users, built once per
    /// account listing so `makeUserAccountProperties` resolves each account's online
    /// nickname from a map instead of a per-account `TT_GetUserByUsername` call.
    var onlineNicknamesByUsername: [String: String] = [:]
    var pendingBannedUsers: [BannedUserProperties] = []
    var listBansCmdID: Int32 = -1
    var pendingFileTransferCommands: [Int32: PendingFileTransferCommand] = [:]
    var fileTransferCommandIDsByTransferID: [Int32: Int32] = [:]
    var securityScopedFileTransferURLs: [Int32: URL] = [:]
    var lastBuiltSessionSnapshot: ConnectedServerSession?
    var cachedAudioDeviceCatalog: AudioDeviceCatalog?
    lazy var advancedMicrophoneEngine = AdvancedMicrophoneAudioEngine { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }
    /// Speaker tap for AEC reference (macOS 14.2+). Typed as Any to avoid availability annotation on stored property.
    var speakerTapCaptureStorage: Any?
    /// Custom CoreAudio output engine. The SDK renders to the virtual output
    /// device (TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL); we pull the muxed playback PCM
    /// and render it ourselves, so switching the output device never calls the
    /// SDK's deadlock-prone TT_CloseSoundOutputDevice. See OutputAudioRenderEngine.
    let outputRenderEngine = OutputAudioRenderEngine()
    /// Dedicated drainer for per-user audio blocks, decoupled from the message
    /// loop so a slow tick (heavy publish in a crowded channel) can never starve
    /// the mix sources. See AudioBlockPump.
    let audioBlockPump = AudioBlockPump()
    /// Remote user IDs we currently have per-user audio block events enabled for
    /// (reconciled with channel membership; the local user is never included).
    var perUserAudioEnabled: Set<Int32> = []
    /// Whether we currently subscribe to our OWN media-file stream so the local
    /// user hears the media they broadcast (TT_LOCAL_USERID + media block events).
    var localMediaAudioEnabled = false
    /// Set when channel membership changes; the message loop reconciles per-user
    /// audio events on its next tick.
    var perUserAudioNeedsRefresh = false
    /// Coalesced session-publish state: the message poll is fast (for smooth
    /// per-user audio), but the expensive full-tree `publishSessionLocked` is
    /// throttled to ~old cadence so it doesn't rebuild every tick during the
    /// connect flood (which slowed connecting).
    var pendingPublishInvalidation: SessionPublishInvalidation = []
    var lastSnapshotPublishAt: CFAbsoluteTime = 0

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        queue.setSpecific(key: queueKey, value: ())
        userVolumeStore.setMemoryMode(preferencesStore.preferences.userVolumeMemoryMode)
        // Seed the queue-side hotkey caches before any queue work runs; the
        // preferences sink keeps them current afterward.
        cachedMicrophoneMode = preferencesStore.preferences.microphoneMode
        cachedPushToTalkKeyConfigured = preferencesStore.preferences.pushToTalkKey?.isValid ?? false
    }

    /// Push the per-user volume memory mode (off / session / persistent) to the store.
    /// Thread-safe; call it live when the preference changes so the mode takes effect
    /// without needing a reconnect.
    func updateUserVolumeMemoryMode(_ mode: AppPreferences.UserVolumeMemoryMode) {
        userVolumeStore.setMemoryMode(mode)
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

        return "tt-Accessible"
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
