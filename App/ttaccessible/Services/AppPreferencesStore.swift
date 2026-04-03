//
//  AppPreferencesStore.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import Combine
import Foundation

final class AppPreferencesStore: ObservableObject {
    private enum Keys {
        static let preferences = "appPreferences.value"
    }

    @Published private(set) var preferences: AppPreferences

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingPersistWorkItem: DispatchWorkItem?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: Keys.preferences),
           let decoded = try? decoder.decode(AppPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = AppPreferences()
        }
        SoundPlayer.shared.isEnabled = preferences.soundNotificationsEnabled
        SoundPlayer.shared.loadPack(preferences.soundPack)
        SoundPlayer.shared.disabledSounds = preferences.disabledSoundEvents
    }

    func updateDefaultNickname(_ nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }
        mutate { $0.defaultNickname = trimmed }
    }

    func updateDefaultStatusMessage(_ message: String) {
        mutate { $0.defaultStatusMessage = message.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func updateDefaultGender(_ gender: TeamTalkGender) {
        mutate { $0.defaultGender = gender }
    }

    func updateAutoAwayTimeoutMinutes(_ minutes: Int) {
        mutate { $0.autoAwayTimeoutMinutes = AppPreferences.clampAutoAwayTimeoutMinutes(minutes) }
    }

    func updateAutoAwayStatusMessage(_ message: String) {
        mutate { $0.autoAwayStatusMessage = message.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func updatePrefersAutomaticTeamTalkConfigDetection(_ enabled: Bool) {
        mutate { $0.prefersAutomaticTeamTalkConfigDetection = enabled }
    }

    func updateUseRelativeTimestamps(_ enabled: Bool) {
        mutate { $0.useRelativeTimestamps = enabled }
    }

    func updateLastRecordingWasActive(_ active: Bool) {
        mutate { $0.lastRecordingWasActive = active }
    }

    func updateAutoRestartRecording(_ enabled: Bool) {
        mutate { $0.autoRestartRecording = enabled }
    }

    func updatePreferredInputDevice(_ preference: AudioDevicePreference) {
        mutate { $0.preferredInputDevice = preference }
    }

    func updatePreferredOutputDevice(_ preference: AudioDevicePreference) {
        mutate { $0.preferredOutputDevice = preference }
    }

    func advancedInputAudio(for deviceID: String?) -> AdvancedInputAudioPreferences {
        guard let deviceID, deviceID.isEmpty == false else {
            return preferences.advancedInputAudioProfiles.fallbackProfile ?? AdvancedInputAudioPreferences()
        }
        return preferences.advancedInputAudioProfiles.profilesByDeviceID[deviceID]
            ?? preferences.advancedInputAudioProfiles.fallbackProfile
            ?? AdvancedInputAudioPreferences()
    }

    func updateAdvancedInputAudio(_ preferences: AdvancedInputAudioPreferences, for deviceID: String?) {
        mutate {
            guard let deviceID, deviceID.isEmpty == false else {
                $0.advancedInputAudioProfiles.fallbackProfile = preferences
                return
            }
            $0.advancedInputAudioProfiles.profilesByDeviceID[deviceID] = preferences
        }
    }

    func clearAdvancedInputAudioFallbackProfile() {
        mutate { $0.advancedInputAudioProfiles.fallbackProfile = nil }
    }

    func updateVoiceOverChannelMessagesEnabled(_ enabled: Bool) {
        mutate { $0.voiceOverAnnouncements.channelMessagesEnabled = enabled }
    }

    func updateVoiceOverPrivateMessagesEnabled(_ enabled: Bool) {
        mutate { $0.voiceOverAnnouncements.privateMessagesEnabled = enabled }
    }

    func updateVoiceOverBroadcastMessagesEnabled(_ enabled: Bool) {
        mutate { $0.voiceOverAnnouncements.broadcastMessagesEnabled = enabled }
    }

    func updateVoiceOverSessionHistoryEnabled(_ enabled: Bool) {
        mutate { $0.voiceOverAnnouncements.sessionHistoryEnabled = enabled }
    }

    func updateDisabledSessionHistoryKinds(_ kinds: Set<SessionHistoryEntry.Kind>) {
        mutate { $0.voiceOverAnnouncements.disabledSessionHistoryKinds = kinds }
    }

    func updateSessionHistoryKindEnabled(_ kind: SessionHistoryEntry.Kind, _ enabled: Bool) {
        mutate {
            if enabled {
                $0.voiceOverAnnouncements.disabledSessionHistoryKinds.remove(kind)
            } else {
                $0.voiceOverAnnouncements.disabledSessionHistoryKinds.insert(kind)
            }
        }
    }

    func updateInputGainDB(_ value: Double) {
        mutate { $0.inputGainDB = AppPreferences.clampGainDB(value) }
    }

    func updateOutputGainDB(_ value: Double) {
        mutate { $0.outputGainDB = AppPreferences.clampGainDB(value) }
    }

    func updateSavedServersSortField(_ field: AppPreferences.SavedServersSortField) {
        mutate { $0.savedServersSort.field = field }
    }

    func updateSavedServersSortAscending(_ ascending: Bool) {
        mutate { $0.savedServersSort.ascending = ascending }
    }

    func updateAutoJoinRootChannel(_ enabled: Bool) {
        mutate { $0.autoJoinRootChannel = enabled }
    }

    func updateAutoReconnect(_ enabled: Bool) {
        mutate { $0.autoReconnect = enabled }
    }

    func updateRejoinLastChannelOnReconnect(_ enabled: Bool) {
        mutate { $0.rejoinLastChannelOnReconnect = enabled }
    }

    func updateSubscribeBroadcastMessages(_ enabled: Bool) {
        mutate { $0.subscribeBroadcastMessages = enabled }
    }

    func updateSubscriptionEnabledByDefault(_ enabled: Bool, for option: UserSubscriptionOption) {
        mutate { $0.setSubscriptionEnabledByDefault(enabled, for: option) }
    }

    func updateSoundNotificationsEnabled(_ enabled: Bool) {
        mutate { $0.soundNotificationsEnabled = enabled }
        SoundPlayer.shared.isEnabled = enabled
    }

    func updateLastVoiceTransmissionEnabled(_ enabled: Bool) {
        mutate { $0.lastVoiceTransmissionEnabled = enabled }
    }

    func updateBackgroundAnnouncementMode(_ mode: BackgroundMessageAnnouncementMode, for type: BackgroundMessageAnnouncementType) {
        mutate { $0.setBackgroundAnnouncementMode(mode, for: type) }
    }

    func updateMacOSTTSVoiceIdentifier(_ identifier: String?) {
        mutate { $0.setMacOSTTSVoiceIdentifier(identifier) }
    }

    func updateMacOSTTSSpeechRate(_ value: Double) {
        mutate { $0.setMacOSTTSSpeechRate(value) }
    }

    func updateMacOSTTSVolume(_ value: Double) {
        mutate { $0.setMacOSTTSVolume(value) }
    }

    func updateRecordingFolderBookmark(_ bookmark: Data?) {
        mutate { $0.recordingFolderBookmark = bookmark }
    }

    func updateRecordingAudioFileFormat(_ format: Int) {
        mutate { $0.recordingAudioFileFormat = format }
    }

    func updateRecordingMode(_ mode: Int) {
        mutate { $0.recordingMode = mode }
    }

    func updateSoundPack(_ pack: String) {
        mutate { $0.soundPack = pack }
        SoundPlayer.shared.loadPack(pack)
    }

    func updateDisabledSoundEvents(_ disabled: Set<NotificationSound>) {
        mutate { $0.disabledSoundEvents = disabled }
        SoundPlayer.shared.disabledSounds = disabled
    }

    func resolveRecordingFolderURL() -> URL? {
        guard let bookmark = preferences.recordingFolderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            if let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                updateRecordingFolderBookmark(fresh)
            }
        }
        return url
    }

    func makeConnectionStore(onSubscriptionPreferencesChanged: (() -> Void)? = nil) -> ConnectionPreferencesStore {
        ConnectionPreferencesStore(rootStore: self, onSubscriptionPreferencesChanged: onSubscriptionPreferencesChanged)
    }

    func makeAudioStore(
        connectionController: TeamTalkConnectionController,
        advancedSettingsStore: AdvancedMicrophoneSettingsStore
    ) -> AudioPreferencesStore {
        AudioPreferencesStore(
            rootStore: self,
            connectionController: connectionController,
            advancedSettingsStore: advancedSettingsStore
        )
    }

    func makeNotificationsStore() -> NotificationsPreferencesStore {
        NotificationsPreferencesStore(rootStore: self)
    }

    func makeAccessibilityStore() -> AccessibilityPreferencesStore {
        AccessibilityPreferencesStore(rootStore: self)
    }

    func makeRecordingStore() -> RecordingPreferencesStore {
        RecordingPreferencesStore(rootStore: self)
    }

    private func mutate(_ mutation: (inout AppPreferences) -> Void) {
        var updated = preferences
        mutation(&updated)
        guard updated != preferences else {
            return
        }
        preferences = updated
        persist(updated)
    }

    private func persist(_ preferences: AppPreferences) {
        pendingPersistWorkItem?.cancel()
        let snapshot = preferences
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let data = try? self.encoder.encode(snapshot) else {
                return
            }
            self.userDefaults.set(data, forKey: Keys.preferences)
        }
        pendingPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }
}

@MainActor
final class ConnectionPreferencesStore: ObservableObject {
    struct State: Equatable {
        var defaultNickname: String
        var defaultStatusMessage: String
        var defaultGender: TeamTalkGender
        var autoAwayTimeoutMinutes: Int
        var autoAwayStatusMessage: String
        var autoJoinRootChannel: Bool
        var autoReconnect: Bool
        var rejoinLastChannelOnReconnect: Bool
        var subscriptions: [UserSubscriptionOption: Bool]
    }

    @Published private(set) var state: State

    private let rootStore: AppPreferencesStore
    private let onSubscriptionPreferencesChanged: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init(rootStore: AppPreferencesStore, onSubscriptionPreferencesChanged: (() -> Void)? = nil) {
        self.rootStore = rootStore
        self.onSubscriptionPreferencesChanged = onSubscriptionPreferencesChanged
        self.state = Self.makeState(from: rootStore.preferences)

        rootStore.$preferences
            .map(Self.makeState)
            .removeDuplicates()
            .sink { [weak self] state in
                self?.state = state
            }
            .store(in: &cancellables)
    }

    func updateDefaultNickname(_ nickname: String) {
        rootStore.updateDefaultNickname(nickname)
    }

    func updateDefaultStatusMessage(_ message: String) {
        rootStore.updateDefaultStatusMessage(message)
    }

    func updateDefaultGender(_ gender: TeamTalkGender) {
        rootStore.updateDefaultGender(gender)
    }

    func updateAutoAwayTimeoutMinutes(_ minutes: Int) {
        rootStore.updateAutoAwayTimeoutMinutes(minutes)
    }

    func updateAutoAwayStatusMessage(_ message: String) {
        rootStore.updateAutoAwayStatusMessage(message)
    }

    func updateAutoJoinRootChannel(_ enabled: Bool) {
        rootStore.updateAutoJoinRootChannel(enabled)
    }

    func updateAutoReconnect(_ enabled: Bool) {
        rootStore.updateAutoReconnect(enabled)
    }

    func updateRejoinLastChannelOnReconnect(_ enabled: Bool) {
        rootStore.updateRejoinLastChannelOnReconnect(enabled)
    }

    func isSubscriptionEnabledByDefault(_ option: UserSubscriptionOption) -> Bool {
        state.subscriptions[option] ?? false
    }

    func updateSubscriptionEnabledByDefault(_ enabled: Bool, for option: UserSubscriptionOption) {
        rootStore.updateSubscriptionEnabledByDefault(enabled, for: option)
        onSubscriptionPreferencesChanged?()
    }

    private static func makeState(from preferences: AppPreferences) -> State {
        State(
            defaultNickname: preferences.defaultNickname,
            defaultStatusMessage: preferences.defaultStatusMessage,
            defaultGender: preferences.defaultGender,
            autoAwayTimeoutMinutes: preferences.autoAwayTimeoutMinutes,
            autoAwayStatusMessage: preferences.autoAwayStatusMessage,
            autoJoinRootChannel: preferences.autoJoinRootChannel,
            autoReconnect: preferences.autoReconnect,
            rejoinLastChannelOnReconnect: preferences.rejoinLastChannelOnReconnect,
            subscriptions: Dictionary(
                uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
                    (option, preferences.isSubscriptionEnabledByDefault(option))
                }
            )
        )
    }
}

@MainActor
final class AudioPreferencesStore: ObservableObject {
    struct State: Equatable {
        var preferredInputDevice: AudioDevicePreference
        var preferredOutputDevice: AudioDevicePreference
        var catalog: AudioDeviceCatalog
        var isCatalogLoading: Bool
        var lastErrorMessage: String?
        var advancedFeedbackMessage: String?
        var advancedErrorMessage: String?
    }

    @Published private(set) var state: State

    private let rootStore: AppPreferencesStore
    private let connectionController: TeamTalkConnectionController
    private let advancedSettingsStore: AdvancedMicrophoneSettingsStore
    private var cancellables = Set<AnyCancellable>()
    private var hasPrepared = false
    private var isVisible = false
    private var applyWorkItem: DispatchWorkItem?
    private var lastAppliedInputPreference: AudioDevicePreference
    private var lastAppliedOutputPreference: AudioDevicePreference

    var advancedPreferences: AdvancedInputAudioPreferences {
        advancedSettingsStore.advancedPreferences
    }

    var presetOptions: [InputChannelPresetOption] {
        advancedSettingsStore.presetOptions
    }

    var isPreviewRunning: Bool {
        advancedSettingsStore.isPreviewRunning
    }

    var advancedDeviceInfo: InputAudioDeviceInfo? {
        advancedSettingsStore.deviceInfo
    }

    init(
        rootStore: AppPreferencesStore,
        connectionController: TeamTalkConnectionController,
        advancedSettingsStore: AdvancedMicrophoneSettingsStore
    ) {
        self.rootStore = rootStore
        self.connectionController = connectionController
        self.advancedSettingsStore = advancedSettingsStore
        self.lastAppliedInputPreference = rootStore.preferences.preferredInputDevice
        self.lastAppliedOutputPreference = rootStore.preferences.preferredOutputDevice
        self.state = State(
            preferredInputDevice: rootStore.preferences.preferredInputDevice,
            preferredOutputDevice: rootStore.preferences.preferredOutputDevice,
            catalog: .empty,
            isCatalogLoading: false,
            lastErrorMessage: nil,
            advancedFeedbackMessage: advancedSettingsStore.feedbackMessage,
            advancedErrorMessage: advancedSettingsStore.lastErrorMessage
        )

        rootStore.$preferences
            .sink { [weak self] preferences in
                guard let self else { return }
                let input = preferences.preferredInputDevice
                let output = preferences.preferredOutputDevice
                guard self.state.preferredInputDevice != input
                    || self.state.preferredOutputDevice != output else {
                    return
                }
                self.state.preferredInputDevice = input
                self.state.preferredOutputDevice = output
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            advancedSettingsStore.$feedbackMessage.removeDuplicates(),
            advancedSettingsStore.$lastErrorMessage.removeDuplicates()
        )
        .sink { [weak self] feedbackMessage, lastErrorMessage in
            guard let self else { return }
            self.state.advancedFeedbackMessage = feedbackMessage
            self.state.advancedErrorMessage = lastErrorMessage
        }
        .store(in: &cancellables)

        // Forward objectWillChange from advancedSettingsStore so SwiftUI picks up
        // changes to advancedPreferences, presetOptions, isPreviewRunning.
        advancedSettingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AudioDeviceChangeMonitor.audioDevicesDidChange)
            .sink { [weak self] _ in
                self?.handleAudioDeviceChange()
            }
            .store(in: &cancellables)
    }

    func prepareIfNeeded() {
        isVisible = true
        guard hasPrepared == false else {
            return
        }
        hasPrepared = true
        loadCatalogIfNeeded(forceRefresh: false)
        advancedSettingsStore.refresh()
    }

    func refreshIfVisible() {
        guard isVisible else {
            return
        }
        loadCatalogIfNeeded(forceRefresh: true)
        advancedSettingsStore.refresh()
    }

    private func handleAudioDeviceChange() {
        // Invalidate the TeamTalk SDK device cache so the next query picks up changes.
        connectionController.invalidateAudioDeviceCache()
        loadCatalogIfNeeded(forceRefresh: true)
        advancedSettingsStore.refresh()
    }

    func suspendWhenHidden() {
        isVisible = false
    }

    func warmup() {
        loadCatalogIfNeeded(forceRefresh: false)
    }

    func refreshDevices() {
        loadCatalogIfNeeded(forceRefresh: true)
        advancedSettingsStore.refresh()
    }

    func updateEchoCancellationEnabled(_ enabled: Bool) {
        advancedSettingsStore.updateEchoCancellationEnabled(enabled)
    }

    func updatePreset(_ preset: InputChannelPreset) {
        advancedSettingsStore.updatePreset(preset)
    }

    func togglePreview() {
        advancedSettingsStore.togglePreview()
    }

    func stopPreview() {
        advancedSettingsStore.stopPreview()
    }

    func updateSelectedDevices(inputID: String, outputID: String) {
        let inputPreference = preference(for: inputID, devices: state.catalog.inputDevices)
        let outputPreference = preference(for: outputID, devices: state.catalog.outputDevices)

        guard inputPreference != state.preferredInputDevice || outputPreference != state.preferredOutputDevice else {
            return
        }

        rootStore.updatePreferredOutputDevice(outputPreference)
        rootStore.updatePreferredInputDevice(inputPreference)
        advancedSettingsStore.handleInputDevicePreferenceChange()
        scheduleApplyAudioPreferencesIfNeeded(
            inputPreference: inputPreference,
            outputPreference: outputPreference
        )
    }

    func selectionID(for preference: AudioDevicePreference, devices: [AudioDeviceOption]) -> String {
        guard let persistentID = preference.persistentID,
              devices.contains(where: { $0.persistentID == persistentID }) else {
            return Self.defaultDeviceTag
        }
        return persistentID
    }

    private func loadCatalogIfNeeded(forceRefresh: Bool) {
        if forceRefresh == false, state.catalog != .empty || state.isCatalogLoading {
            return
        }

        state.isCatalogLoading = true
        Task { @MainActor [weak self, connectionController] in
            let catalog = forceRefresh
                ? connectionController.refreshAvailableAudioDevices()
                : connectionController.availableAudioDevices()
            guard let self else { return }
            self.state.catalog = catalog
            self.state.isCatalogLoading = false
        }
    }

    private func scheduleApplyAudioPreferencesIfNeeded(
        inputPreference: AudioDevicePreference,
        outputPreference: AudioDevicePreference
    ) {
        applyWorkItem?.cancel()

        guard inputPreference != lastAppliedInputPreference || outputPreference != lastAppliedOutputPreference else {
            state.lastErrorMessage = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.connectionController.applyAudioPreferences(self.rootStore.preferences) { result in
                switch result {
                case .success:
                    self.lastAppliedInputPreference = inputPreference
                    self.lastAppliedOutputPreference = outputPreference
                    self.state.lastErrorMessage = nil
                case .failure(let error):
                    self.state.lastErrorMessage = error.localizedDescription
                }
            }
        }
        applyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func preference(for selectionID: String, devices: [AudioDeviceOption]) -> AudioDevicePreference {
        guard selectionID != Self.defaultDeviceTag,
              let device = devices.first(where: { $0.id == selectionID }) else {
            return .systemDefault
        }
        return AudioDevicePreference(persistentID: device.persistentID, displayName: device.displayName)
    }

    private static let defaultDeviceTag = "__system_default__"
}

@MainActor
final class NotificationsPreferencesStore: ObservableObject {
    struct State: Equatable {
        var soundNotificationsEnabled: Bool
        var soundPack: String
        var disabledSoundEvents: Set<NotificationSound>
        var modes: [BackgroundMessageAnnouncementType: BackgroundMessageAnnouncementMode]
        var macOSTTSVoiceIdentifier: String?
        var macOSTTSSpeechRate: Double
        var macOSTTSVolume: Double
        var voiceOptions: [MacOSTextToSpeechVoiceOption]
        var isVoiceOptionsLoading: Bool
    }

    @Published private(set) var state: State

    private let rootStore: AppPreferencesStore
    private var cancellables = Set<AnyCancellable>()
    private var hasPrepared = false

    init(rootStore: AppPreferencesStore) {
        self.rootStore = rootStore
        self.state = Self.makeState(from: rootStore.preferences)

        rootStore.$preferences
            .sink { [weak self] preferences in
                guard let self else { return }
                let nextState = Self.makeState(from: preferences)
                guard self.state.soundNotificationsEnabled != nextState.soundNotificationsEnabled
                    || self.state.soundPack != nextState.soundPack
                    || self.state.disabledSoundEvents != nextState.disabledSoundEvents
                    || self.state.modes != nextState.modes
                    || self.state.macOSTTSVoiceIdentifier != nextState.macOSTTSVoiceIdentifier
                    || self.state.macOSTTSSpeechRate != nextState.macOSTTSSpeechRate
                    || self.state.macOSTTSVolume != nextState.macOSTTSVolume else {
                    return
                }
                self.state.soundNotificationsEnabled = nextState.soundNotificationsEnabled
                self.state.soundPack = nextState.soundPack
                self.state.disabledSoundEvents = nextState.disabledSoundEvents
                self.state.modes = nextState.modes
                self.state.macOSTTSVoiceIdentifier = nextState.macOSTTSVoiceIdentifier
                self.state.macOSTTSSpeechRate = nextState.macOSTTSSpeechRate
                self.state.macOSTTSVolume = nextState.macOSTTSVolume
            }
            .store(in: &cancellables)
    }

    func prepareIfNeeded() {
        guard hasPrepared == false else {
            return
        }
        hasPrepared = true
        state.isVoiceOptionsLoading = true
        Task { @MainActor [weak self] in
            let voices = MacOSTextToSpeechAnnouncementService.availableVoices()
            self?.state.voiceOptions = voices
            self?.state.isVoiceOptionsLoading = false
        }
    }

    func updateSoundNotificationsEnabled(_ enabled: Bool) {
        rootStore.updateSoundNotificationsEnabled(enabled)
    }

    func updateSoundPack(_ pack: String) {
        rootStore.updateSoundPack(pack)
    }

    func isSoundEventEnabled(_ sound: NotificationSound) -> Bool {
        !state.disabledSoundEvents.contains(sound)
    }

    func setSoundEventEnabled(_ sound: NotificationSound, enabled: Bool) {
        var disabled = state.disabledSoundEvents
        if enabled {
            disabled.remove(sound)
        } else {
            disabled.insert(sound)
        }
        rootStore.updateDisabledSoundEvents(disabled)
    }

    func backgroundAnnouncementMode(for type: BackgroundMessageAnnouncementType) -> BackgroundMessageAnnouncementMode {
        state.modes[type] ?? .systemNotification
    }

    func updateBackgroundAnnouncementMode(_ mode: BackgroundMessageAnnouncementMode, for type: BackgroundMessageAnnouncementType) {
        rootStore.updateBackgroundAnnouncementMode(mode, for: type)
    }

    func updateMacOSTTSVoiceIdentifier(_ identifier: String?) {
        rootStore.updateMacOSTTSVoiceIdentifier(identifier)
    }

    func updateMacOSTTSSpeechRate(_ value: Double) {
        rootStore.updateMacOSTTSSpeechRate(value)
    }

    func updateMacOSTTSVolume(_ value: Double) {
        rootStore.updateMacOSTTSVolume(value)
    }

    private static func makeState(from preferences: AppPreferences) -> State {
        State(
            soundNotificationsEnabled: preferences.soundNotificationsEnabled,
            soundPack: preferences.soundPack,
            disabledSoundEvents: preferences.disabledSoundEvents,
            modes: Dictionary(
                uniqueKeysWithValues: BackgroundMessageAnnouncementType.allCases.map { type in
                    (type, preferences.backgroundAnnouncementMode(for: type))
                }
            ),
            macOSTTSVoiceIdentifier: preferences.macOSTTSVoiceIdentifier,
            macOSTTSSpeechRate: preferences.macOSTTSSpeechRate,
            macOSTTSVolume: preferences.macOSTTSVolume,
            voiceOptions: [],
            isVoiceOptionsLoading: false
        )
    }
}

@MainActor
final class AccessibilityPreferencesStore: ObservableObject {
    struct State: Equatable {
        var channelMessagesEnabled: Bool
        var privateMessagesEnabled: Bool
        var broadcastMessagesEnabled: Bool
        var sessionHistoryEnabled: Bool
        var disabledSessionHistoryKinds: Set<SessionHistoryEntry.Kind>
    }

    @Published private(set) var state: State

    private let rootStore: AppPreferencesStore
    private var cancellables = Set<AnyCancellable>()

    init(rootStore: AppPreferencesStore) {
        self.rootStore = rootStore
        self.state = Self.makeState(from: rootStore.preferences)

        rootStore.$preferences
            .map(Self.makeState)
            .removeDuplicates()
            .sink { [weak self] state in
                self?.state = state
            }
            .store(in: &cancellables)
    }

    func updateVoiceOverChannelMessagesEnabled(_ enabled: Bool) {
        rootStore.updateVoiceOverChannelMessagesEnabled(enabled)
    }

    func updateVoiceOverPrivateMessagesEnabled(_ enabled: Bool) {
        rootStore.updateVoiceOverPrivateMessagesEnabled(enabled)
    }

    func updateVoiceOverBroadcastMessagesEnabled(_ enabled: Bool) {
        rootStore.updateVoiceOverBroadcastMessagesEnabled(enabled)
    }

    func updateVoiceOverSessionHistoryEnabled(_ enabled: Bool) {
        rootStore.updateVoiceOverSessionHistoryEnabled(enabled)
    }

    func isSessionHistoryKindEnabled(_ kind: SessionHistoryEntry.Kind) -> Bool {
        !state.disabledSessionHistoryKinds.contains(kind)
    }

    func updateSessionHistoryKindEnabled(_ kind: SessionHistoryEntry.Kind, _ enabled: Bool) {
        rootStore.updateSessionHistoryKindEnabled(kind, enabled)
    }

    func enableAllSessionHistoryKinds() {
        rootStore.updateDisabledSessionHistoryKinds([])
    }

    func disableAllSessionHistoryKinds() {
        rootStore.updateDisabledSessionHistoryKinds(Set(SessionHistoryEntry.Kind.announceable))
    }

    private static func makeState(from preferences: AppPreferences) -> State {
        State(
            channelMessagesEnabled: preferences.voiceOverAnnouncements.channelMessagesEnabled,
            privateMessagesEnabled: preferences.voiceOverAnnouncements.privateMessagesEnabled,
            broadcastMessagesEnabled: preferences.voiceOverAnnouncements.broadcastMessagesEnabled,
            sessionHistoryEnabled: preferences.voiceOverAnnouncements.sessionHistoryEnabled,
            disabledSessionHistoryKinds: preferences.voiceOverAnnouncements.disabledSessionHistoryKinds
        )
    }
}

@MainActor
final class RecordingPreferencesStore: ObservableObject {
    struct FormatOption: Identifiable, Hashable {
        let id: Int
        let label: String
    }

    static let formatOptions: [FormatOption] = [
        FormatOption(id: 2, label: "WAV"),
        FormatOption(id: 1, label: "OGG (Opus)"),
    ]

    struct ModeOption: Identifiable, Hashable {
        let id: Int
        let label: String
    }

    static let modeOptions: [ModeOption] = [
        ModeOption(id: 1, label: L10n.text("preferences.recording.mode.muxed")),
        ModeOption(id: 2, label: L10n.text("preferences.recording.mode.separate")),
        ModeOption(id: 3, label: L10n.text("preferences.recording.mode.both")),
    ]

    struct State: Equatable {
        var folderBookmark: Data?
        var audioFileFormat: Int
        var recordingMode: Int
        var folderDisplayPath: String?
        var autoRestartRecording: Bool
    }

    @Published private(set) var state: State

    private let rootStore: AppPreferencesStore
    private var cancellables = Set<AnyCancellable>()

    init(rootStore: AppPreferencesStore) {
        self.rootStore = rootStore
        self.state = Self.makeState(from: rootStore)

        rootStore.$preferences
            .sink { [weak self] _ in
                guard let self else { return }
                let next = Self.makeState(from: rootStore)
                if self.state != next { self.state = next }
            }
            .store(in: &cancellables)
    }

    func updateAudioFileFormat(_ format: Int) {
        rootStore.updateRecordingAudioFileFormat(format)
    }

    func updateRecordingMode(_ mode: Int) {
        rootStore.updateRecordingMode(mode)
    }

    func chooseFolder(from window: NSWindow) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("recording.panel.choose")
        panel.message = L10n.text("recording.panel.message")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                self.rootStore.updateRecordingFolderBookmark(bookmark)
            }
        }
    }

    func clearFolder() {
        rootStore.updateRecordingFolderBookmark(nil)
    }

    func updateAutoRestartRecording(_ enabled: Bool) {
        rootStore.updateAutoRestartRecording(enabled)
    }

    private static func makeState(from rootStore: AppPreferencesStore) -> State {
        let folderURL = rootStore.resolveRecordingFolderURL()
        return State(
            folderBookmark: rootStore.preferences.recordingFolderBookmark,
            audioFileFormat: rootStore.preferences.recordingAudioFileFormat,
            recordingMode: rootStore.preferences.recordingMode,
            folderDisplayPath: folderURL?.path,
            autoRestartRecording: rootStore.preferences.autoRestartRecording
        )
    }
}
