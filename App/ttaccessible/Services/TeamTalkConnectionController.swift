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
    /// Queue-side cache of how people are named (nickname, username, or both):
    /// `displayName(for:)` runs per user per snapshot and from the message loop,
    /// so it must not read the @Published preferences struct. Seeded at init,
    /// updated via updateUserNameDisplayStyle.
    var cachedUserNameDisplayStyle: AppPreferences.UserNameDisplayStyle = .nicknameAndUsername
    /// "Both" mode only: the always-on gate toggled by ⌘⇧A. The mic engine stays
    /// hot (voiceTransmissionEnabled) the whole time so PTT is instant; this
    /// lightweight flag decides whether captured audio is transmitted when PTT
    /// is not held. Releasing PTT closes it (see setPushToTalkPressed).
    var bothGateOpen = false
    /// Set when the mic was open and a channel that carries no voice forced it
    /// shut, so leaving that channel gives the user back the mic they had. Without
    /// it "both" mode loses the gate for good: a normal channel change keeps the
    /// gate because the engine is already running and `armBothModeEngineIfNeeded`
    /// returns early, but once the engine has been torn down that same call rearms
    /// it gate-closed. Being moved into a silent channel and back would otherwise
    /// leave the user mute with no sign — the failure this whole path exists to end.
    var reopenVoiceWhenChannelAllowsIt = false
    /// Consecutive capture restarts that failed to get a single block accepted.
    /// The guard restarts on a run of refused voice, but a restart only helps when
    /// the fault is local and rebuildable; against anything else it used to retry
    /// every 30 s forever, announcing itself each time and repairing nothing —
    /// observed in the field. Past `maxVoiceCaptureRecoveryAttempts` it gives up
    /// loudly instead. Reset by the first accepted block.
    var voiceCaptureRecoveryAttempts = 0
    /// Run of consecutive voice blocks the SDK refused, and how much voice that
    /// adds up to. A refusal is normally transient, but the capture can settle
    /// into a state where every block is refused and nothing recovers on its
    /// own — see `noteVoiceInsertOutcomeLocked`, which throttles the log and
    /// restarts the capture on a sustained run.
    var refusedVoiceInsertCount = 0
    var refusedVoiceSeconds: Double = 0
    var lastRefusedVoiceLogAt: CFAbsoluteTime = 0
    var lastVoiceCaptureRecoveryAt: CFAbsoluteTime = 0
    /// One line per refused block was 47 lines a second in the field.
    static let refusedVoiceLogInterval: CFAbsoluteTime = 5
    /// A second of refused voice is well past any transient queue pressure.
    static let refusedVoiceRecoveryThreshold: Double = 1
    /// Spaces the restarts out; `maxVoiceCaptureRecoveryAttempts` is what actually
    /// ends them — on its own this only slowed the loop down to one every 30 s.
    static let voiceCaptureRecoveryBackoff: CFAbsoluteTime = 30
    /// Two restarts are enough to tell a rebuildable fault from one a restart will
    /// never fix. Beyond that the mic is turned off and said to be off, which the
    /// user can act on — unlike an announcement every 30 s that changes nothing.
    static let maxVoiceCaptureRecoveryAttempts = 2
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
    /// What the active stream sources — the three kinds behave differently
    /// enough that the UI cannot tell them apart from the duration alone.
    var mediaStreamingSourceKind: MediaStreamingSourceKind = .file
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
    /// Path + password of the channel we were in when the connection dropped.
    /// The PATH is what we rejoin by on reconnect: a full server restart
    /// reassigns numeric channel IDs, so `lastChannelID` can point at the wrong
    /// channel (or nothing), but the path is stable.
    var lastChannelPath: String = ""
    var lastChannelPassword: String = ""
    /// Index into `reconnectBackoffSeconds`; also the give-up counter.
    var reconnectAttempt = 0
    /// When we were last kicked. A server kick emits MYSELF_KICKED and then
    /// MYSELF_LOGGEDOUT, and that logout must not be treated as a dropped
    /// connection worth reconnecting.
    var justKickedAt: Date?
    /// Channel we were last confirmed to be in, refreshed on every session
    /// publish. The SDK clears its own channel state BEFORE posting
    /// MYSELF_LOGGEDOUT, so asking it at drop time returns nothing on that path.
    var lastKnownChannelID: Int32 = 0
    var lastKnownChannelPath: String = ""
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
    /// Voice↔stream sync (always on while a live-capture media stream runs):
    /// measures the media path's sender-side latency from our own stream's
    /// local playback blocks and delays outgoing voice to match, so a user
    /// singing over their streamed instrument arrives in time at receivers.
    /// See VoiceSyncDelayLine.swift.
    let voiceSyncEstimator = MediaSyncEstimator()
    lazy var voiceSyncDelayLine = VoiceSyncDelayLine(queue: queue)
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

    let passwordStore: ServerPasswordStore

    /// Channel IDs with a password persisted in the keychain, mirrored in memory so the
    /// UI can answer "is there a saved password here?" on the main thread without
    /// keychain I/O or a hop onto this controller's serial queue — menu validation runs
    /// every time a menu opens and must stay cheap. Guarded by its own lock rather than
    /// the queue for exactly that reason.
    private let savedChannelPasswordLock = NSLock()
    private var savedChannelPasswordIDs: Set<Int32> = []

    func hasSavedChannelPassword(forChannelID channelID: Int32) -> Bool {
        savedChannelPasswordLock.lock()
        defer { savedChannelPasswordLock.unlock() }
        return savedChannelPasswordIDs.contains(channelID)
    }

    private func markSavedChannelPassword(_ channelID: Int32, saved: Bool) {
        savedChannelPasswordLock.lock()
        if saved { savedChannelPasswordIDs.insert(channelID) } else { savedChannelPasswordIDs.remove(channelID) }
        savedChannelPasswordLock.unlock()
    }

    private func replaceSavedChannelPasswordIDs(_ ids: Set<Int32>) {
        savedChannelPasswordLock.lock()
        savedChannelPasswordIDs = ids
        savedChannelPasswordLock.unlock()
    }

    /// Resolve the server's persisted channel paths to live channel IDs. Called once
    /// after login (the channel tree exists by then), not on every session publish —
    /// keychain reads are far too expensive for that.
    func refreshSavedChannelPasswordIDsLocked(instance: UnsafeMutableRawPointer) {
        guard let serverID = connectedRecord?.id,
              let map = try? passwordStore.allChannelPasswords(for: serverID), map.isEmpty == false else {
            replaceSavedChannelPasswordIDs([])
            return
        }
        var ids: Set<Int32> = []
        for path in map.keys {
            let channelID = path.withCString { TT_GetChannelIDFromPath(instance, $0) }
            if channelID > 0 { ids.insert(channelID) }
        }
        replaceSavedChannelPasswordIDs(ids)
    }

    func clearSavedChannelPasswordIDs() {
        replaceSavedChannelPasswordIDs([])
    }

    init(preferencesStore: AppPreferencesStore, passwordStore: ServerPasswordStore) {
        self.preferencesStore = preferencesStore
        self.passwordStore = passwordStore
        queue.setSpecific(key: queueKey, value: ())
        userVolumeStore.setMemoryMode(preferencesStore.preferences.userVolumeMemoryMode)
        // Seed the queue-side hotkey caches before any queue work runs; the
        // preferences sink keeps them current afterward.
        cachedMicrophoneMode = preferencesStore.preferences.microphoneMode
        cachedPushToTalkKeyConfigured = preferencesStore.preferences.pushToTalkKey?.isValid ?? false
        cachedUserNameDisplayStyle = preferencesStore.preferences.userNameDisplayStyle
        audioBlockPump.mediaSyncEstimator = voiceSyncEstimator
        voiceSyncDelayLine.insertHandler = { [weak self] chunk in
            // Runs on the controller queue (the delay line's timer lives there).
            self?.performVoiceInsertLocked(chunk) ?? true
        }
    }

    /// Push the per-user volume memory mode (off / session / persistent) to the store.
    /// Thread-safe; call it live when the preference changes so the mode takes effect
    /// without needing a reconnect.
    func updateUserVolumeMemoryMode(_ mode: AppPreferences.UserVolumeMemoryMode) {
        userVolumeStore.setMemoryMode(mode)
    }

    /// Push the "show people as" preference to the queue-side cache and, when a
    /// session is up, rebuild the tree so every row, mixer strip and window title
    /// is renamed on the spot — no reconnect. Chat lines and history entries
    /// already written keep the name they were written with.
    func updateUserNameDisplayStyle(_ style: AppPreferences.UserNameDisplayStyle) {
        queue.async { [weak self] in
            guard let self, self.cachedUserNameDisplayStyle != style else { return }
            self.cachedUserNameDisplayStyle = style
            guard let instance = self.instance, let connectedRecord = self.connectedRecord else { return }
            self.publishSessionLocked(instance: instance, record: connectedRecord, invalidation: [.rootTree])
        }
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
        markSavedChannelPassword(channelID, saved: true)
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
        markSavedChannelPassword(channelID, saved: false)
        guard let serverID = connectedRecord?.id else { return }
        let path = channelPathLocked(instance: instance, channelID: channelID)
        guard !path.isEmpty else { return }
        try? passwordStore.setChannelPassword(nil, for: serverID, channelPath: path)
    }

    // `channelPathLocked(instance:channelID:)` lives in `+Connection.swift`
    // (added by the auto-reconnect work, which rejoins by path). This branch
    // grew an identical copy while both were in flight; one is enough.

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

    /// How a person is named in chat lines, announcements, history and the tree
    /// sort. Same resolver as `ConnectedServerUser.displayName`, so the two never
    /// disagree. Queue-side: reads the cached preference, never the store.
    func displayName(for user: User) -> String {
        cachedUserNameDisplayStyle.displayName(
            nickname: ttString(from: user.szNickname),
            username: ttString(from: user.szUsername),
            userID: user.nUserID
        )
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
