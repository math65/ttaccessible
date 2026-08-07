//
//  AppPreferences.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct AppPreferences: Codable, Equatable {
    static func defaultNicknameFromAccount() -> String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = fullName.components(separatedBy: .whitespacesAndNewlines).first ?? ""
        return firstWord.isEmpty ? "tt-Accessible" : firstWord
    }

    enum ChannelSortMode: String, Codable, CaseIterable {
        case name
        case userCount
    }

    enum MicrophoneMode: String, Codable, CaseIterable {
        case alwaysOn
        case pushToTalk
        /// Mute-gated with a momentary PTT override. ⌘⇧A toggles an always-on
        /// gate; holding the PTT key transmits regardless, and releasing it
        /// closes the gate (goes silent). See PushToTalkController.
        case both
    }

    /// How per-user volume/stereo/pan adjustments are remembered (issue #24).
    /// - off: never remembered; reconnecting resets everyone to 50% (like the
    ///   official client).
    /// - session: remembered while the app runs, discarded on quit.
    /// - persistent: remembered across launches, scoped per server.
    enum UserVolumeMemoryMode: String, Codable, CaseIterable {
        case off
        case session
        case persistent
    }

    enum SavedServersSortField: String, Codable, CaseIterable {
        case manual
        case name
        case host
        case tcpPort
        case udpPort
    }

    struct SavedServersSortPreferences: Codable, Equatable {
        var field: SavedServersSortField
        var ascending: Bool

        init(field: SavedServersSortField = .manual, ascending: Bool = true) {
            self.field = field
            self.ascending = ascending
        }
    }

    struct AdvancedInputAudioProfiles: Codable, Equatable {
        var fallbackProfile: AdvancedInputAudioPreferences?
        var profilesByDeviceID: [String: AdvancedInputAudioPreferences]

        init(
            fallbackProfile: AdvancedInputAudioPreferences? = nil,
            profilesByDeviceID: [String: AdvancedInputAudioPreferences] = [:]
        ) {
            self.fallbackProfile = fallbackProfile
            self.profilesByDeviceID = profilesByDeviceID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case defaultNickname
        case defaultStatusMessage
        case defaultGender
        case autoAwayTimeoutMinutes
        case autoAwayStatusMessage
        case prefersAutomaticTeamTalkConfigDetection
        case useRelativeTimestamps
        case lastRecordingWasActive
        case lastActiveRecordingMode
        case autoRestartRecording
        case preferredInputDevice
        case preferredOutputDevice
        case advancedInputAudioProfiles
        case advancedInputAudio
        case outputChannelSelections
        case deviceStreamChannelPresets
        case voiceOverAnnouncements
        case inputGainDB
        case outputGainDB
        case soundEffectsGainDB
        case savedServersSort
        case autoJoinRootChannel
        case autoReconnect
        case rejoinLastChannelOnReconnect
        case connectToLastServerOnLaunch
        case subscribePrivateMessages
        case subscribeChannelMessages
        case subscribeBroadcastMessages
        case subscribeVoice
        case subscribeDesktop
        case subscribeMediaFile
        case interceptPrivateMessages
        case interceptChannelMessages
        case interceptVoice
        case interceptDesktop
        case interceptMediaFile
        case soundNotificationsEnabled
        case lastVoiceTransmissionEnabled
        case privateMessagesBackgroundMode
        case channelMessagesBackgroundMode
        case broadcastMessagesBackgroundMode
        case sessionHistoryBackgroundMode
        case useGlobalAnnouncementMode
        case globalAnnouncementMode
        case macOSTTSVoiceIdentifier
        case macOSTTSSpeechRate
        case macOSTTSVolume
        case recordingFolderBookmark
        case recordingAudioFileFormat
        case recordingMode
        case soundPack
        case disabledSoundEvents
        case skipKickConfirmation
        case adaptiveJitterBuffer
        case channelSortMode
        case autoCheckForUpdates
        case includeBetaUpdates
        case microphoneMode
        case pushToTalkBeepEnabled
        case pushToTalkKey
        case pushToTalkGlobal
        case muteHotkeyGlobal
        case muteHotkeyBinding
        case didMigrateLegacyPushToTalkKey
        case videoPanelExpanded
        case userVolumeMemoryMode
        case deviceStreamLastDeviceUID
        case deviceStreamLastSource
        case deviceStreamVoiceSyncTrimMSec
        case languagePreference
        case hasChosenInitialLanguage
    }

    var defaultNickname: String
    var defaultStatusMessage: String
    var defaultGender: TeamTalkGender
    var autoAwayTimeoutMinutes: Int
    var autoAwayStatusMessage: String
    var prefersAutomaticTeamTalkConfigDetection: Bool
    var useRelativeTimestamps: Bool
    var lastRecordingWasActive: Bool
    /// The recording mode (1 = single file, 2 = separate stems, 3 = both) of the
    /// recording that was active when it last stopped. Unlike `recordingMode`, this
    /// is stored raw (not clamped to 2/3) so auto-restart can faithfully restore a
    /// single-file (⌘R) recording rather than silently upgrading it to the preference.
    /// 0 means "no active recording to restore".
    var lastActiveRecordingMode: Int
    var autoRestartRecording: Bool
    var autoJoinRootChannel: Bool
    var autoReconnect: Bool
    var rejoinLastChannelOnReconnect: Bool
    var connectToLastServerOnLaunch: Bool
    var subscribePrivateMessages: Bool
    var subscribeChannelMessages: Bool
    var subscribeBroadcastMessages: Bool
    var subscribeVoice: Bool
    var subscribeDesktop: Bool
    var subscribeMediaFile: Bool
    var interceptPrivateMessages: Bool
    var interceptChannelMessages: Bool
    var interceptVoice: Bool
    var interceptDesktop: Bool
    var interceptMediaFile: Bool
    var soundNotificationsEnabled: Bool
    var lastVoiceTransmissionEnabled: Bool
    var privateMessagesBackgroundMode: BackgroundMessageAnnouncementMode
    var channelMessagesBackgroundMode: BackgroundMessageAnnouncementMode
    var broadcastMessagesBackgroundMode: BackgroundMessageAnnouncementMode
    var sessionHistoryBackgroundMode: BackgroundMessageAnnouncementMode
    var useGlobalAnnouncementMode: Bool
    var globalAnnouncementMode: BackgroundMessageAnnouncementMode
    var macOSTTSVoiceIdentifier: String?
    var macOSTTSSpeechRate: Double
    var macOSTTSVolume: Double
    var preferredInputDevice: AudioDevicePreference
    var preferredOutputDevice: AudioDevicePreference
    var advancedInputAudioProfiles: AdvancedInputAudioProfiles
    /// Which physical output channels carry the mix, per output-device UID —
    /// so a 32-out interface can keep TeamTalk on 5/6 while the built-in
    /// speakers stay on their only pair. Absent = `.auto` (channels 1/2).
    var outputChannelSelections: [String: OutputChannelSelection]
    /// Which channels of a captured input device the "Stream Audio Device"
    /// broadcast takes, per input-device UID. Absent = `.auto` (first pair).
    var deviceStreamChannelPresets: [String: InputChannelPreset]
    var voiceOverAnnouncements: VoiceOverAnnouncementPreferences
    var inputGainDB: Double
    var outputGainDB: Double
    // Base level for app notification sound effects (dB). The effective playback
    // volume is this gain combined with the output (master) volume, so master
    // scales the sound effects too.
    var soundEffectsGainDB: Double
    var savedServersSort: SavedServersSortPreferences
    var recordingFolderBookmark: Data?
    var recordingAudioFileFormat: Int
    var recordingMode: Int
    var soundPack: String
    var disabledSoundEvents: Set<NotificationSound>
    var skipKickConfirmation: Bool
    var adaptiveJitterBuffer: Bool
    var channelSortMode: ChannelSortMode
    var autoCheckForUpdates: Bool
    var includeBetaUpdates: Bool
    var microphoneMode: MicrophoneMode
    var pushToTalkBeepEnabled: Bool
    /// The push-to-talk key/chord. `nil` means unset.
    var pushToTalkKey: HotkeyBinding?
    /// When true, the PTT key works even when ttaccessible is not the active app
    /// (requires Input Monitoring permission).
    var pushToTalkGlobal: Bool
    /// When true, ⌘⇧A (mute / gate) works from any app (requires Input Monitoring).
    var muteHotkeyGlobal: Bool
    /// Custom binding for the GLOBAL mic-toggle hotkey (nil = the default,
    /// ⌘⇧ + the key that types "A" on the current layout). The in-app case is
    /// always the ⌘⇧A menu shortcut; this binding only drives the global
    /// listen-only tap used while another app is frontmost.
    var muteHotkeyBinding: HotkeyBinding?
    /// One-time migration marker: the old KeyboardShortcuts library's stored
    /// push-to-talk key has been imported (or found absent).
    var didMigrateLegacyPushToTalkKey: Bool
    var videoPanelExpanded: Bool
    var userVolumeMemoryMode: UserVolumeMemoryMode
    /// CoreAudio UID of the input device last streamed to a channel, so the
    /// device-stream dialog preselects it next time.
    var deviceStreamLastDeviceUID: String?
    /// Last streamed capture source as a token ("device:<uid>", "app:<bundleID>",
    /// "voiceover") — supersedes deviceStreamLastDeviceUID for preselection, which
    /// is still written for devices so older builds keep their memory.
    var deviceStreamLastSource: String?
    /// Signed manual trim (ms) added to the measured voice-sync delay while a
    /// live-capture stream runs. No UI — an escape hatch to absorb the voice
    /// path's own capture latency on unusual setups.
    var deviceStreamVoiceSyncTrimMSec: Int
    var languagePreference: AppLanguagePreference
    var hasChosenInitialLanguage: Bool
    init(
        defaultNickname: String = AppPreferences.defaultNicknameFromAccount(),
        defaultStatusMessage: String = "",
        defaultGender: TeamTalkGender = .neutral,
        autoAwayTimeoutMinutes: Int = 3,
        autoAwayStatusMessage: String = "",
        prefersAutomaticTeamTalkConfigDetection: Bool = true,
        useRelativeTimestamps: Bool = false,
        lastRecordingWasActive: Bool = false,
        lastActiveRecordingMode: Int = 0,
        autoRestartRecording: Bool = false,
        preferredInputDevice: AudioDevicePreference = .systemDefault,
        preferredOutputDevice: AudioDevicePreference = .systemDefault,
        advancedInputAudioProfiles: AdvancedInputAudioProfiles = AdvancedInputAudioProfiles(),
        outputChannelSelections: [String: OutputChannelSelection] = [:],
        deviceStreamChannelPresets: [String: InputChannelPreset] = [:],
        voiceOverAnnouncements: VoiceOverAnnouncementPreferences = VoiceOverAnnouncementPreferences(),
        inputGainDB: Double = 0,
        outputGainDB: Double = 0,
        soundEffectsGainDB: Double = 0,
        savedServersSort: SavedServersSortPreferences = SavedServersSortPreferences(),
        autoJoinRootChannel: Bool = true,
        autoReconnect: Bool = true,
        rejoinLastChannelOnReconnect: Bool = true,
        connectToLastServerOnLaunch: Bool = false,
        subscribePrivateMessages: Bool = true,
        subscribeChannelMessages: Bool = true,
        subscribeBroadcastMessages: Bool = true,
        subscribeVoice: Bool = true,
        subscribeDesktop: Bool = true,
        subscribeMediaFile: Bool = true,
        interceptPrivateMessages: Bool = false,
        interceptChannelMessages: Bool = false,
        interceptVoice: Bool = false,
        interceptDesktop: Bool = false,
        interceptMediaFile: Bool = false,
        soundNotificationsEnabled: Bool = true,
        lastVoiceTransmissionEnabled: Bool = false,
        privateMessagesBackgroundMode: BackgroundMessageAnnouncementMode = .systemNotification,
        channelMessagesBackgroundMode: BackgroundMessageAnnouncementMode = .systemNotification,
        broadcastMessagesBackgroundMode: BackgroundMessageAnnouncementMode = .systemNotification,
        sessionHistoryBackgroundMode: BackgroundMessageAnnouncementMode = .systemNotification,
        useGlobalAnnouncementMode: Bool = true,
        globalAnnouncementMode: BackgroundMessageAnnouncementMode = .systemNotification,
        macOSTTSVoiceIdentifier: String? = nil,
        macOSTTSSpeechRate: Double = 0.5,
        macOSTTSVolume: Double = 1.0,
        recordingFolderBookmark: Data? = nil,
        recordingAudioFileFormat: Int = 2,
        recordingMode: Int = 3,
        soundPack: String = "Default",
        disabledSoundEvents: Set<NotificationSound> = [],
        skipKickConfirmation: Bool = false,
        adaptiveJitterBuffer: Bool = false,
        channelSortMode: ChannelSortMode = .name,
        autoCheckForUpdates: Bool = true,
        includeBetaUpdates: Bool = false,
        microphoneMode: MicrophoneMode = .alwaysOn,
        pushToTalkBeepEnabled: Bool = true,
        pushToTalkKey: HotkeyBinding? = nil,
        pushToTalkGlobal: Bool = true,
        muteHotkeyGlobal: Bool = false,
        muteHotkeyBinding: HotkeyBinding? = nil,
        didMigrateLegacyPushToTalkKey: Bool = false,
        videoPanelExpanded: Bool = true,
        userVolumeMemoryMode: UserVolumeMemoryMode = .persistent,
        deviceStreamLastDeviceUID: String? = nil,
        deviceStreamLastSource: String? = nil,
        deviceStreamVoiceSyncTrimMSec: Int = 0,
        languagePreference: AppLanguagePreference = .system,
        hasChosenInitialLanguage: Bool = false
    ) {
        self.defaultNickname = defaultNickname
        self.defaultStatusMessage = defaultStatusMessage
        self.defaultGender = defaultGender
        self.autoAwayTimeoutMinutes = Self.clampAutoAwayTimeoutMinutes(autoAwayTimeoutMinutes)
        self.autoAwayStatusMessage = autoAwayStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prefersAutomaticTeamTalkConfigDetection = prefersAutomaticTeamTalkConfigDetection
        self.useRelativeTimestamps = useRelativeTimestamps
        self.lastRecordingWasActive = lastRecordingWasActive
        self.lastActiveRecordingMode = lastActiveRecordingMode
        self.autoRestartRecording = autoRestartRecording
        self.preferredInputDevice = preferredInputDevice
        self.preferredOutputDevice = preferredOutputDevice
        self.advancedInputAudioProfiles = advancedInputAudioProfiles
        self.outputChannelSelections = outputChannelSelections
        self.deviceStreamChannelPresets = deviceStreamChannelPresets
        self.voiceOverAnnouncements = voiceOverAnnouncements
        self.inputGainDB = Self.clampGainDB(inputGainDB)
        self.outputGainDB = Self.clampGainDB(outputGainDB)
        self.soundEffectsGainDB = Self.clampGainDB(soundEffectsGainDB)
        self.savedServersSort = savedServersSort
        self.autoJoinRootChannel = autoJoinRootChannel
        self.autoReconnect = autoReconnect
        self.rejoinLastChannelOnReconnect = rejoinLastChannelOnReconnect
        self.connectToLastServerOnLaunch = connectToLastServerOnLaunch
        self.subscribePrivateMessages = subscribePrivateMessages
        self.subscribeChannelMessages = subscribeChannelMessages
        self.subscribeBroadcastMessages = subscribeBroadcastMessages
        self.subscribeVoice = subscribeVoice
        self.subscribeDesktop = subscribeDesktop
        self.subscribeMediaFile = subscribeMediaFile
        self.interceptPrivateMessages = interceptPrivateMessages
        self.interceptChannelMessages = interceptChannelMessages
        self.interceptVoice = interceptVoice
        self.interceptDesktop = interceptDesktop
        self.interceptMediaFile = interceptMediaFile
        self.soundNotificationsEnabled = soundNotificationsEnabled
        self.lastVoiceTransmissionEnabled = lastVoiceTransmissionEnabled
        self.privateMessagesBackgroundMode = privateMessagesBackgroundMode.normalizedForBackground
        self.channelMessagesBackgroundMode = channelMessagesBackgroundMode.normalizedForBackground
        self.broadcastMessagesBackgroundMode = broadcastMessagesBackgroundMode.normalizedForBackground
        self.sessionHistoryBackgroundMode = sessionHistoryBackgroundMode.normalizedForBackground
        self.useGlobalAnnouncementMode = useGlobalAnnouncementMode
        self.globalAnnouncementMode = globalAnnouncementMode.normalizedForBackground
        self.macOSTTSVoiceIdentifier = macOSTTSVoiceIdentifier?.isEmpty == true ? nil : macOSTTSVoiceIdentifier
        self.macOSTTSSpeechRate = Self.clampMacOSTTSSpeechRate(macOSTTSSpeechRate)
        self.macOSTTSVolume = Self.clampMacOSTTSVolume(macOSTTSVolume)
        self.recordingFolderBookmark = recordingFolderBookmark
        self.recordingAudioFileFormat = Self.clampRecordingAudioFileFormat(recordingAudioFileFormat)
        self.recordingMode = Self.clampRecordingMode(recordingMode)
        self.soundPack = soundPack
        self.disabledSoundEvents = disabledSoundEvents
        self.skipKickConfirmation = skipKickConfirmation
        self.adaptiveJitterBuffer = adaptiveJitterBuffer
        self.channelSortMode = channelSortMode
        self.autoCheckForUpdates = autoCheckForUpdates
        self.includeBetaUpdates = includeBetaUpdates
        self.microphoneMode = microphoneMode
        self.pushToTalkBeepEnabled = pushToTalkBeepEnabled
        self.pushToTalkKey = pushToTalkKey
        self.pushToTalkGlobal = pushToTalkGlobal
        self.muteHotkeyGlobal = muteHotkeyGlobal
        self.muteHotkeyBinding = muteHotkeyBinding
        self.didMigrateLegacyPushToTalkKey = didMigrateLegacyPushToTalkKey
        self.videoPanelExpanded = videoPanelExpanded
        self.userVolumeMemoryMode = userVolumeMemoryMode
        self.deviceStreamLastDeviceUID = deviceStreamLastDeviceUID
        self.deviceStreamLastSource = deviceStreamLastSource
        self.deviceStreamVoiceSyncTrimMSec = deviceStreamVoiceSyncTrimMSec
        self.languagePreference = languagePreference
        self.hasChosenInitialLanguage = hasChosenInitialLanguage
    }

    nonisolated static let minGainDB: Double = -24
    nonisolated static let maxGainDB: Double = 24

    nonisolated static func clampGainDB(_ value: Double) -> Double {
        min(max(value, minGainDB), maxGainDB)
    }

    /// Linear gain for a slider dB value. The bottom of the scale — 0 % on every
    /// gain slider — is a REAL silence, not `minGainDB`: -24 dB is quiet but still
    /// perfectly audible, and a user who drags a volume to 0 % means "off".
    nonisolated static func linearGain(forGainDB value: Double) -> Double {
        let clamped = clampGainDB(value)
        if clamped <= minGainDB { return 0 }
        return pow(10, clamped / 20)
    }

    nonisolated static func clampAutoAwayTimeoutMinutes(_ value: Int) -> Int {
        min(max(value, 0), 720)
    }

    nonisolated static func clampMacOSTTSSpeechRate(_ value: Double) -> Double {
        min(max(value, 0.25), 0.75)
    }

    nonisolated static func clampMacOSTTSVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Recording audio file format: 1=WAV, 2=OGG.
    nonisolated static func clampRecordingAudioFileFormat(_ value: Int) -> Int {
        (value == 1 || value == 2) ? value : 2
    }

    /// Recording mode bitmask: 1=muxed, 2=separate, 3=both.
    // The stored recording mode drives ⌘⇧R (and the toolbar Record button), which record
    // separate files (2) or both muxed + separate (3). Single-file recording is always
    // available on ⌘R and is not a stored preference, so a legacy "single" (1) value
    // migrates to "both" (3) — a superset that still produces the single muxed file.
    nonisolated static func clampRecordingMode(_ value: Int) -> Int {
        value == 2 ? 2 : 3
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultNickname = try container.decodeIfPresent(String.self, forKey: .defaultNickname) ?? AppPreferences.defaultNicknameFromAccount()
        defaultStatusMessage = try container.decodeIfPresent(String.self, forKey: .defaultStatusMessage) ?? ""
        defaultGender = try container.decodeIfPresent(TeamTalkGender.self, forKey: .defaultGender) ?? .neutral
        autoAwayTimeoutMinutes = Self.clampAutoAwayTimeoutMinutes(try container.decodeIfPresent(Int.self, forKey: .autoAwayTimeoutMinutes) ?? 3)
        autoAwayStatusMessage = try container.decodeIfPresent(String.self, forKey: .autoAwayStatusMessage)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        prefersAutomaticTeamTalkConfigDetection = try container.decodeIfPresent(Bool.self, forKey: .prefersAutomaticTeamTalkConfigDetection) ?? true
        useRelativeTimestamps = try container.decodeIfPresent(Bool.self, forKey: .useRelativeTimestamps) ?? false
        lastRecordingWasActive = try container.decodeIfPresent(Bool.self, forKey: .lastRecordingWasActive) ?? false
        lastActiveRecordingMode = try container.decodeIfPresent(Int.self, forKey: .lastActiveRecordingMode) ?? 0
        autoRestartRecording = try container.decodeIfPresent(Bool.self, forKey: .autoRestartRecording) ?? false
        preferredInputDevice = try container.decodeIfPresent(AudioDevicePreference.self, forKey: .preferredInputDevice) ?? .systemDefault
        preferredOutputDevice = try container.decodeIfPresent(AudioDevicePreference.self, forKey: .preferredOutputDevice) ?? .systemDefault
        if let profiles = try container.decodeIfPresent(AdvancedInputAudioProfiles.self, forKey: .advancedInputAudioProfiles) {
            advancedInputAudioProfiles = profiles
        } else {
            let legacyAdvanced = try container.decodeIfPresent(AdvancedInputAudioPreferences.self, forKey: .advancedInputAudio)
            if let persistentID = preferredInputDevice.persistentID, persistentID.isEmpty == false, let legacyAdvanced {
                advancedInputAudioProfiles = AdvancedInputAudioProfiles(
                    profilesByDeviceID: [persistentID: legacyAdvanced]
                )
            } else {
                advancedInputAudioProfiles = AdvancedInputAudioProfiles(
                    fallbackProfile: legacyAdvanced
                )
            }
        }
        outputChannelSelections = try container.decodeIfPresent([String: OutputChannelSelection].self, forKey: .outputChannelSelections) ?? [:]
        deviceStreamChannelPresets = try container.decodeIfPresent([String: InputChannelPreset].self, forKey: .deviceStreamChannelPresets) ?? [:]
        voiceOverAnnouncements = try container.decodeIfPresent(VoiceOverAnnouncementPreferences.self, forKey: .voiceOverAnnouncements) ?? VoiceOverAnnouncementPreferences()
        inputGainDB = Self.clampGainDB(try container.decodeIfPresent(Double.self, forKey: .inputGainDB) ?? 0)
        outputGainDB = Self.clampGainDB(try container.decodeIfPresent(Double.self, forKey: .outputGainDB) ?? 0)
        soundEffectsGainDB = Self.clampGainDB(try container.decodeIfPresent(Double.self, forKey: .soundEffectsGainDB) ?? 0)
        savedServersSort = try container.decodeIfPresent(SavedServersSortPreferences.self, forKey: .savedServersSort) ?? SavedServersSortPreferences()
        autoJoinRootChannel = try container.decodeIfPresent(Bool.self, forKey: .autoJoinRootChannel) ?? true
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        rejoinLastChannelOnReconnect = try container.decodeIfPresent(Bool.self, forKey: .rejoinLastChannelOnReconnect) ?? true
        connectToLastServerOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .connectToLastServerOnLaunch) ?? false
        subscribePrivateMessages = try container.decodeIfPresent(Bool.self, forKey: .subscribePrivateMessages) ?? true
        subscribeChannelMessages = try container.decodeIfPresent(Bool.self, forKey: .subscribeChannelMessages) ?? true
        subscribeBroadcastMessages = try container.decodeIfPresent(Bool.self, forKey: .subscribeBroadcastMessages) ?? true
        subscribeVoice = try container.decodeIfPresent(Bool.self, forKey: .subscribeVoice) ?? true
        subscribeDesktop = try container.decodeIfPresent(Bool.self, forKey: .subscribeDesktop) ?? true
        subscribeMediaFile = try container.decodeIfPresent(Bool.self, forKey: .subscribeMediaFile) ?? true
        interceptPrivateMessages = try container.decodeIfPresent(Bool.self, forKey: .interceptPrivateMessages) ?? false
        interceptChannelMessages = try container.decodeIfPresent(Bool.self, forKey: .interceptChannelMessages) ?? false
        interceptVoice = try container.decodeIfPresent(Bool.self, forKey: .interceptVoice) ?? false
        interceptDesktop = try container.decodeIfPresent(Bool.self, forKey: .interceptDesktop) ?? false
        interceptMediaFile = try container.decodeIfPresent(Bool.self, forKey: .interceptMediaFile) ?? false
        soundNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundNotificationsEnabled) ?? true
        lastVoiceTransmissionEnabled = try container.decodeIfPresent(Bool.self, forKey: .lastVoiceTransmissionEnabled) ?? false
        privateMessagesBackgroundMode = (try container.decodeIfPresent(BackgroundMessageAnnouncementMode.self, forKey: .privateMessagesBackgroundMode) ?? .systemNotification).normalizedForBackground
        channelMessagesBackgroundMode = (try container.decodeIfPresent(BackgroundMessageAnnouncementMode.self, forKey: .channelMessagesBackgroundMode) ?? .systemNotification).normalizedForBackground
        broadcastMessagesBackgroundMode = (try container.decodeIfPresent(BackgroundMessageAnnouncementMode.self, forKey: .broadcastMessagesBackgroundMode) ?? .systemNotification).normalizedForBackground
        sessionHistoryBackgroundMode = (try container.decodeIfPresent(BackgroundMessageAnnouncementMode.self, forKey: .sessionHistoryBackgroundMode) ?? .systemNotification).normalizedForBackground
        let storedUseGlobal = try container.decodeIfPresent(Bool.self, forKey: .useGlobalAnnouncementMode)
        let storedGlobalMode = try container.decodeIfPresent(BackgroundMessageAnnouncementMode.self, forKey: .globalAnnouncementMode)?.normalizedForBackground
        if let storedUseGlobal {
            useGlobalAnnouncementMode = storedUseGlobal
            globalAnnouncementMode = storedGlobalMode ?? privateMessagesBackgroundMode
        } else {
            // Migration depuis une version sans mode global : si les 4 modes per-event
            // sont identiques (cas le plus fréquent), on active le mode global avec cette
            // valeur. Sinon, on garde le mode désactivé pour préserver la config existante.
            let allEqual = privateMessagesBackgroundMode == channelMessagesBackgroundMode
                && privateMessagesBackgroundMode == broadcastMessagesBackgroundMode
                && privateMessagesBackgroundMode == sessionHistoryBackgroundMode
            useGlobalAnnouncementMode = allEqual
            globalAnnouncementMode = storedGlobalMode ?? privateMessagesBackgroundMode
        }
        macOSTTSVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .macOSTTSVoiceIdentifier)
        macOSTTSSpeechRate = Self.clampMacOSTTSSpeechRate(try container.decodeIfPresent(Double.self, forKey: .macOSTTSSpeechRate) ?? 0.5)
        macOSTTSVolume = Self.clampMacOSTTSVolume(try container.decodeIfPresent(Double.self, forKey: .macOSTTSVolume) ?? 1.0)
        recordingFolderBookmark = try container.decodeIfPresent(Data.self, forKey: .recordingFolderBookmark)
        recordingAudioFileFormat = Self.clampRecordingAudioFileFormat(try container.decodeIfPresent(Int.self, forKey: .recordingAudioFileFormat) ?? 2)
        recordingMode = Self.clampRecordingMode(try container.decodeIfPresent(Int.self, forKey: .recordingMode) ?? 3)
        soundPack = try container.decodeIfPresent(String.self, forKey: .soundPack) ?? "Default"
        disabledSoundEvents = try container.decodeIfPresent(Set<NotificationSound>.self, forKey: .disabledSoundEvents) ?? []
        skipKickConfirmation = try container.decodeIfPresent(Bool.self, forKey: .skipKickConfirmation) ?? false
        adaptiveJitterBuffer = try container.decodeIfPresent(Bool.self, forKey: .adaptiveJitterBuffer) ?? false
        channelSortMode = try container.decodeIfPresent(ChannelSortMode.self, forKey: .channelSortMode) ?? .name
        autoCheckForUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckForUpdates) ?? true
        includeBetaUpdates = try container.decodeIfPresent(Bool.self, forKey: .includeBetaUpdates) ?? false
        microphoneMode = try container.decodeIfPresent(MicrophoneMode.self, forKey: .microphoneMode) ?? .alwaysOn
        pushToTalkBeepEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushToTalkBeepEnabled) ?? true
        pushToTalkKey = try container.decodeIfPresent(HotkeyBinding.self, forKey: .pushToTalkKey)
        pushToTalkGlobal = try container.decodeIfPresent(Bool.self, forKey: .pushToTalkGlobal) ?? true
        muteHotkeyGlobal = try container.decodeIfPresent(Bool.self, forKey: .muteHotkeyGlobal) ?? false
        muteHotkeyBinding = try container.decodeIfPresent(HotkeyBinding.self, forKey: .muteHotkeyBinding)
        didMigrateLegacyPushToTalkKey = try container.decodeIfPresent(Bool.self, forKey: .didMigrateLegacyPushToTalkKey) ?? false
        videoPanelExpanded = try container.decodeIfPresent(Bool.self, forKey: .videoPanelExpanded) ?? true
        userVolumeMemoryMode = try container.decodeIfPresent(UserVolumeMemoryMode.self, forKey: .userVolumeMemoryMode) ?? .persistent
        deviceStreamLastDeviceUID = try container.decodeIfPresent(String.self, forKey: .deviceStreamLastDeviceUID)
        deviceStreamLastSource = try container.decodeIfPresent(String.self, forKey: .deviceStreamLastSource)
        deviceStreamVoiceSyncTrimMSec = try container.decodeIfPresent(Int.self, forKey: .deviceStreamVoiceSyncTrimMSec) ?? 0
        languagePreference = try container.decodeIfPresent(AppLanguagePreference.self, forKey: .languagePreference) ?? .system
        hasChosenInitialLanguage = try container.decodeIfPresent(Bool.self, forKey: .hasChosenInitialLanguage) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultNickname, forKey: .defaultNickname)
        try container.encode(defaultStatusMessage, forKey: .defaultStatusMessage)
        try container.encode(defaultGender, forKey: .defaultGender)
        try container.encode(Self.clampAutoAwayTimeoutMinutes(autoAwayTimeoutMinutes), forKey: .autoAwayTimeoutMinutes)
        try container.encode(autoAwayStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .autoAwayStatusMessage)
        try container.encode(prefersAutomaticTeamTalkConfigDetection, forKey: .prefersAutomaticTeamTalkConfigDetection)
        try container.encode(useRelativeTimestamps, forKey: .useRelativeTimestamps)
        try container.encode(lastRecordingWasActive, forKey: .lastRecordingWasActive)
        try container.encode(lastActiveRecordingMode, forKey: .lastActiveRecordingMode)
        try container.encode(autoRestartRecording, forKey: .autoRestartRecording)
        try container.encode(preferredInputDevice, forKey: .preferredInputDevice)
        try container.encode(preferredOutputDevice, forKey: .preferredOutputDevice)
        try container.encode(advancedInputAudioProfiles, forKey: .advancedInputAudioProfiles)
        try container.encode(outputChannelSelections, forKey: .outputChannelSelections)
        try container.encode(deviceStreamChannelPresets, forKey: .deviceStreamChannelPresets)
        try container.encode(voiceOverAnnouncements, forKey: .voiceOverAnnouncements)
        try container.encode(Self.clampGainDB(inputGainDB), forKey: .inputGainDB)
        try container.encode(Self.clampGainDB(outputGainDB), forKey: .outputGainDB)
        try container.encode(Self.clampGainDB(soundEffectsGainDB), forKey: .soundEffectsGainDB)
        try container.encode(savedServersSort, forKey: .savedServersSort)
        try container.encode(autoJoinRootChannel, forKey: .autoJoinRootChannel)
        try container.encode(autoReconnect, forKey: .autoReconnect)
        try container.encode(rejoinLastChannelOnReconnect, forKey: .rejoinLastChannelOnReconnect)
        try container.encode(connectToLastServerOnLaunch, forKey: .connectToLastServerOnLaunch)
        try container.encode(subscribePrivateMessages, forKey: .subscribePrivateMessages)
        try container.encode(subscribeChannelMessages, forKey: .subscribeChannelMessages)
        try container.encode(subscribeBroadcastMessages, forKey: .subscribeBroadcastMessages)
        try container.encode(subscribeVoice, forKey: .subscribeVoice)
        try container.encode(subscribeDesktop, forKey: .subscribeDesktop)
        try container.encode(subscribeMediaFile, forKey: .subscribeMediaFile)
        try container.encode(interceptPrivateMessages, forKey: .interceptPrivateMessages)
        try container.encode(interceptChannelMessages, forKey: .interceptChannelMessages)
        try container.encode(interceptVoice, forKey: .interceptVoice)
        try container.encode(interceptDesktop, forKey: .interceptDesktop)
        try container.encode(interceptMediaFile, forKey: .interceptMediaFile)
        try container.encode(soundNotificationsEnabled, forKey: .soundNotificationsEnabled)
        try container.encode(lastVoiceTransmissionEnabled, forKey: .lastVoiceTransmissionEnabled)
        try container.encode(privateMessagesBackgroundMode, forKey: .privateMessagesBackgroundMode)
        try container.encode(channelMessagesBackgroundMode, forKey: .channelMessagesBackgroundMode)
        try container.encode(broadcastMessagesBackgroundMode, forKey: .broadcastMessagesBackgroundMode)
        try container.encode(sessionHistoryBackgroundMode, forKey: .sessionHistoryBackgroundMode)
        try container.encode(useGlobalAnnouncementMode, forKey: .useGlobalAnnouncementMode)
        try container.encode(globalAnnouncementMode, forKey: .globalAnnouncementMode)
        try container.encodeIfPresent(macOSTTSVoiceIdentifier, forKey: .macOSTTSVoiceIdentifier)
        try container.encode(Self.clampMacOSTTSSpeechRate(macOSTTSSpeechRate), forKey: .macOSTTSSpeechRate)
        try container.encode(Self.clampMacOSTTSVolume(macOSTTSVolume), forKey: .macOSTTSVolume)
        try container.encodeIfPresent(recordingFolderBookmark, forKey: .recordingFolderBookmark)
        try container.encode(Self.clampRecordingAudioFileFormat(recordingAudioFileFormat), forKey: .recordingAudioFileFormat)
        try container.encode(Self.clampRecordingMode(recordingMode), forKey: .recordingMode)
        try container.encode(soundPack, forKey: .soundPack)
        try container.encode(disabledSoundEvents, forKey: .disabledSoundEvents)
        try container.encode(skipKickConfirmation, forKey: .skipKickConfirmation)
        try container.encode(adaptiveJitterBuffer, forKey: .adaptiveJitterBuffer)
        try container.encode(channelSortMode, forKey: .channelSortMode)
        try container.encode(autoCheckForUpdates, forKey: .autoCheckForUpdates)
        try container.encode(includeBetaUpdates, forKey: .includeBetaUpdates)
        try container.encode(microphoneMode, forKey: .microphoneMode)
        try container.encode(pushToTalkBeepEnabled, forKey: .pushToTalkBeepEnabled)
        try container.encodeIfPresent(pushToTalkKey, forKey: .pushToTalkKey)
        try container.encode(pushToTalkGlobal, forKey: .pushToTalkGlobal)
        try container.encode(muteHotkeyGlobal, forKey: .muteHotkeyGlobal)
        try container.encodeIfPresent(muteHotkeyBinding, forKey: .muteHotkeyBinding)
        try container.encode(didMigrateLegacyPushToTalkKey, forKey: .didMigrateLegacyPushToTalkKey)
        try container.encode(videoPanelExpanded, forKey: .videoPanelExpanded)
        try container.encode(userVolumeMemoryMode, forKey: .userVolumeMemoryMode)
        try container.encodeIfPresent(deviceStreamLastDeviceUID, forKey: .deviceStreamLastDeviceUID)
        try container.encodeIfPresent(deviceStreamLastSource, forKey: .deviceStreamLastSource)
        try container.encode(deviceStreamVoiceSyncTrimMSec, forKey: .deviceStreamVoiceSyncTrimMSec)
        try container.encode(languagePreference, forKey: .languagePreference)
        try container.encode(hasChosenInitialLanguage, forKey: .hasChosenInitialLanguage)
    }

    func isSubscriptionEnabledByDefault(_ option: UserSubscriptionOption) -> Bool {
        switch option {
        case .privateMessages:
            return subscribePrivateMessages
        case .channelMessages:
            return subscribeChannelMessages
        case .broadcastMessages:
            return subscribeBroadcastMessages
        case .voice:
            return subscribeVoice
        case .desktop:
            return subscribeDesktop
        case .mediaFile:
            return subscribeMediaFile
        case .interceptPrivateMessages:
            return interceptPrivateMessages
        case .interceptChannelMessages:
            return interceptChannelMessages
        case .interceptVoice:
            return interceptVoice
        case .interceptDesktop:
            return interceptDesktop
        case .interceptMediaFile:
            return interceptMediaFile
        }
    }

    mutating func setSubscriptionEnabledByDefault(_ enabled: Bool, for option: UserSubscriptionOption) {
        switch option {
        case .privateMessages:
            subscribePrivateMessages = enabled
        case .channelMessages:
            subscribeChannelMessages = enabled
        case .broadcastMessages:
            subscribeBroadcastMessages = enabled
        case .voice:
            subscribeVoice = enabled
        case .desktop:
            subscribeDesktop = enabled
        case .mediaFile:
            subscribeMediaFile = enabled
        case .interceptPrivateMessages:
            interceptPrivateMessages = enabled
        case .interceptChannelMessages:
            interceptChannelMessages = enabled
        case .interceptVoice:
            interceptVoice = enabled
        case .interceptDesktop:
            interceptDesktop = enabled
        case .interceptMediaFile:
            interceptMediaFile = enabled
        }
    }

    func backgroundAnnouncementMode(for type: BackgroundMessageAnnouncementType) -> BackgroundMessageAnnouncementMode {
        if useGlobalAnnouncementMode {
            return globalAnnouncementMode
        }
        return perEventBackgroundAnnouncementMode(for: type)
    }

    /// Returns the per-event mode stored on disk, ignoring the global override.
    /// Used by the preferences UI so that toggling the global switch off restores
    /// the user's previous per-event configuration.
    func perEventBackgroundAnnouncementMode(for type: BackgroundMessageAnnouncementType) -> BackgroundMessageAnnouncementMode {
        switch type {
        case .privateMessages:
            return privateMessagesBackgroundMode
        case .channelMessages:
            return channelMessagesBackgroundMode
        case .broadcastMessages:
            return broadcastMessagesBackgroundMode
        case .sessionHistory:
            return sessionHistoryBackgroundMode
        }
    }

    mutating func setBackgroundAnnouncementMode(_ mode: BackgroundMessageAnnouncementMode, for type: BackgroundMessageAnnouncementType) {
        switch type {
        case .privateMessages:
            privateMessagesBackgroundMode = mode
        case .channelMessages:
            channelMessagesBackgroundMode = mode
        case .broadcastMessages:
            broadcastMessagesBackgroundMode = mode
        case .sessionHistory:
            sessionHistoryBackgroundMode = mode
        }
    }

    mutating func setMacOSTTSVoiceIdentifier(_ identifier: String?) {
        macOSTTSVoiceIdentifier = identifier?.isEmpty == true ? nil : identifier
    }

    mutating func setMacOSTTSSpeechRate(_ value: Double) {
        macOSTTSSpeechRate = Self.clampMacOSTTSSpeechRate(value)
    }

    mutating func setMacOSTTSVolume(_ value: Double) {
        macOSTTSVolume = Self.clampMacOSTTSVolume(value)
    }
}
