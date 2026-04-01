//
//  AppPreferences.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct AppPreferences: Codable, Equatable {
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
        case preferredInputDevice
        case preferredOutputDevice
        case advancedInputAudioProfiles
        case advancedInputAudio
        case voiceOverAnnouncements
        case inputGainDB
        case outputGainDB
        case savedServersSort
        case autoJoinRootChannel
        case autoReconnect
        case rejoinLastChannelOnReconnect
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
        case macOSTTSVoiceIdentifier
        case macOSTTSSpeechRate
        case macOSTTSVolume
        case recordingFolderBookmark
        case recordingAudioFileFormat
        case recordingMode
        case soundPack
    }

    var defaultNickname: String
    var defaultStatusMessage: String
    var defaultGender: TeamTalkGender
    var autoAwayTimeoutMinutes: Int
    var autoAwayStatusMessage: String
    var prefersAutomaticTeamTalkConfigDetection: Bool
    var autoJoinRootChannel: Bool
    var autoReconnect: Bool
    var rejoinLastChannelOnReconnect: Bool
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
    var macOSTTSVoiceIdentifier: String?
    var macOSTTSSpeechRate: Double
    var macOSTTSVolume: Double
    var preferredInputDevice: AudioDevicePreference
    var preferredOutputDevice: AudioDevicePreference
    var advancedInputAudioProfiles: AdvancedInputAudioProfiles
    var voiceOverAnnouncements: VoiceOverAnnouncementPreferences
    var inputGainDB: Double
    var outputGainDB: Double
    var savedServersSort: SavedServersSortPreferences
    var recordingFolderBookmark: Data?
    var recordingAudioFileFormat: Int
    var recordingMode: Int
    var soundPack: String
    init(
        defaultNickname: String = "TTAccessible",
        defaultStatusMessage: String = "",
        defaultGender: TeamTalkGender = .neutral,
        autoAwayTimeoutMinutes: Int = 3,
        autoAwayStatusMessage: String = "",
        prefersAutomaticTeamTalkConfigDetection: Bool = true,
        preferredInputDevice: AudioDevicePreference = .systemDefault,
        preferredOutputDevice: AudioDevicePreference = .systemDefault,
        advancedInputAudioProfiles: AdvancedInputAudioProfiles = AdvancedInputAudioProfiles(),
        voiceOverAnnouncements: VoiceOverAnnouncementPreferences = VoiceOverAnnouncementPreferences(),
        inputGainDB: Double = 0,
        outputGainDB: Double = 0,
        savedServersSort: SavedServersSortPreferences = SavedServersSortPreferences(),
        autoJoinRootChannel: Bool = true,
        autoReconnect: Bool = true,
        rejoinLastChannelOnReconnect: Bool = true,
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
        macOSTTSVoiceIdentifier: String? = nil,
        macOSTTSSpeechRate: Double = 0.5,
        macOSTTSVolume: Double = 1.0,
        recordingFolderBookmark: Data? = nil,
        recordingAudioFileFormat: Int = 2,
        recordingMode: Int = 1,
        soundPack: String = "Default"
    ) {
        self.defaultNickname = defaultNickname
        self.defaultStatusMessage = defaultStatusMessage
        self.defaultGender = defaultGender
        self.autoAwayTimeoutMinutes = Self.clampAutoAwayTimeoutMinutes(autoAwayTimeoutMinutes)
        self.autoAwayStatusMessage = autoAwayStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prefersAutomaticTeamTalkConfigDetection = prefersAutomaticTeamTalkConfigDetection
        self.preferredInputDevice = preferredInputDevice
        self.preferredOutputDevice = preferredOutputDevice
        self.advancedInputAudioProfiles = advancedInputAudioProfiles
        self.voiceOverAnnouncements = voiceOverAnnouncements
        self.inputGainDB = Self.clampGainDB(inputGainDB)
        self.outputGainDB = Self.clampGainDB(outputGainDB)
        self.savedServersSort = savedServersSort
        self.autoJoinRootChannel = autoJoinRootChannel
        self.autoReconnect = autoReconnect
        self.rejoinLastChannelOnReconnect = rejoinLastChannelOnReconnect
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
        self.macOSTTSVoiceIdentifier = macOSTTSVoiceIdentifier?.isEmpty == true ? nil : macOSTTSVoiceIdentifier
        self.macOSTTSSpeechRate = Self.clampMacOSTTSSpeechRate(macOSTTSSpeechRate)
        self.macOSTTSVolume = Self.clampMacOSTTSVolume(macOSTTSVolume)
        self.recordingFolderBookmark = recordingFolderBookmark
        self.recordingAudioFileFormat = recordingAudioFileFormat
        self.recordingMode = recordingMode
        self.soundPack = soundPack
    }

    nonisolated static func clampGainDB(_ value: Double) -> Double {
        min(max(value.rounded(), -24), 24)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultNickname = try container.decodeIfPresent(String.self, forKey: .defaultNickname) ?? "TTAccessible"
        defaultStatusMessage = try container.decodeIfPresent(String.self, forKey: .defaultStatusMessage) ?? ""
        defaultGender = try container.decodeIfPresent(TeamTalkGender.self, forKey: .defaultGender) ?? .neutral
        autoAwayTimeoutMinutes = Self.clampAutoAwayTimeoutMinutes(try container.decodeIfPresent(Int.self, forKey: .autoAwayTimeoutMinutes) ?? 3)
        autoAwayStatusMessage = try container.decodeIfPresent(String.self, forKey: .autoAwayStatusMessage)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        prefersAutomaticTeamTalkConfigDetection = try container.decodeIfPresent(Bool.self, forKey: .prefersAutomaticTeamTalkConfigDetection) ?? true
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
        voiceOverAnnouncements = try container.decodeIfPresent(VoiceOverAnnouncementPreferences.self, forKey: .voiceOverAnnouncements) ?? VoiceOverAnnouncementPreferences()
        inputGainDB = Self.clampGainDB(try container.decodeIfPresent(Double.self, forKey: .inputGainDB) ?? 0)
        outputGainDB = Self.clampGainDB(try container.decodeIfPresent(Double.self, forKey: .outputGainDB) ?? 0)
        savedServersSort = try container.decodeIfPresent(SavedServersSortPreferences.self, forKey: .savedServersSort) ?? SavedServersSortPreferences()
        autoJoinRootChannel = try container.decodeIfPresent(Bool.self, forKey: .autoJoinRootChannel) ?? true
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        rejoinLastChannelOnReconnect = try container.decodeIfPresent(Bool.self, forKey: .rejoinLastChannelOnReconnect) ?? true
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
        macOSTTSVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .macOSTTSVoiceIdentifier)
        macOSTTSSpeechRate = Self.clampMacOSTTSSpeechRate(try container.decodeIfPresent(Double.self, forKey: .macOSTTSSpeechRate) ?? 0.5)
        macOSTTSVolume = Self.clampMacOSTTSVolume(try container.decodeIfPresent(Double.self, forKey: .macOSTTSVolume) ?? 1.0)
        recordingFolderBookmark = try container.decodeIfPresent(Data.self, forKey: .recordingFolderBookmark)
        recordingAudioFileFormat = try container.decodeIfPresent(Int.self, forKey: .recordingAudioFileFormat) ?? 2
        recordingMode = try container.decodeIfPresent(Int.self, forKey: .recordingMode) ?? 1
        soundPack = try container.decodeIfPresent(String.self, forKey: .soundPack) ?? "Default"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultNickname, forKey: .defaultNickname)
        try container.encode(defaultStatusMessage, forKey: .defaultStatusMessage)
        try container.encode(defaultGender, forKey: .defaultGender)
        try container.encode(Self.clampAutoAwayTimeoutMinutes(autoAwayTimeoutMinutes), forKey: .autoAwayTimeoutMinutes)
        try container.encode(autoAwayStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .autoAwayStatusMessage)
        try container.encode(prefersAutomaticTeamTalkConfigDetection, forKey: .prefersAutomaticTeamTalkConfigDetection)
        try container.encode(preferredInputDevice, forKey: .preferredInputDevice)
        try container.encode(preferredOutputDevice, forKey: .preferredOutputDevice)
        try container.encode(advancedInputAudioProfiles, forKey: .advancedInputAudioProfiles)
        try container.encode(voiceOverAnnouncements, forKey: .voiceOverAnnouncements)
        try container.encode(Self.clampGainDB(inputGainDB), forKey: .inputGainDB)
        try container.encode(Self.clampGainDB(outputGainDB), forKey: .outputGainDB)
        try container.encode(savedServersSort, forKey: .savedServersSort)
        try container.encode(autoJoinRootChannel, forKey: .autoJoinRootChannel)
        try container.encode(autoReconnect, forKey: .autoReconnect)
        try container.encode(rejoinLastChannelOnReconnect, forKey: .rejoinLastChannelOnReconnect)
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
        try container.encodeIfPresent(macOSTTSVoiceIdentifier, forKey: .macOSTTSVoiceIdentifier)
        try container.encode(Self.clampMacOSTTSSpeechRate(macOSTTSSpeechRate), forKey: .macOSTTSSpeechRate)
        try container.encode(Self.clampMacOSTTSVolume(macOSTTSVolume), forKey: .macOSTTSVolume)
        try container.encodeIfPresent(recordingFolderBookmark, forKey: .recordingFolderBookmark)
        try container.encode(recordingAudioFileFormat, forKey: .recordingAudioFileFormat)
        try container.encode(recordingMode, forKey: .recordingMode)
        try container.encode(soundPack, forKey: .soundPack)
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
