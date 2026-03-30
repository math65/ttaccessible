//
//  AdvancedMicrophoneSettingsStore.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Combine
import Foundation

@MainActor
final class AdvancedMicrophoneSettingsStore: ObservableObject {
    @Published private(set) var deviceInfo: InputAudioDeviceInfo?
    @Published private(set) var presetOptions: [InputChannelPresetOption] = [
        InputChannelPresetOption(preset: .auto, title: InputAudioDeviceResolver.title(for: .auto))
    ]
    @Published private(set) var summaryText: String
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isPreviewRunning = false

    private let preferencesStore: AppPreferencesStore
    private let connectionController: TeamTalkConnectionController
    private let previewController = AdvancedMicrophonePreviewController()
    private var cancellables = Set<AnyCancellable>()
    private var isNormalizing = false

    init(preferencesStore: AppPreferencesStore, connectionController: TeamTalkConnectionController) {
        self.preferencesStore = preferencesStore
        self.connectionController = connectionController
        let initialDeviceID = InputAudioDeviceResolver.currentInputDeviceID(for: preferencesStore.preferences.preferredInputDevice)
        self.summaryText = InputAudioDeviceResolver.summary(for: preferencesStore.advancedInputAudio(for: initialDeviceID))

        preferencesStore.$preferences
            .sink { [weak self] _ in
                self?.refreshState(normalizeIfNeeded: true)
            }
            .store(in: &cancellables)

        refreshState(normalizeIfNeeded: true)
    }

    var advancedPreferences: AdvancedInputAudioPreferences {
        let deviceID = deviceInfo?.uid ?? InputAudioDeviceResolver.currentInputDeviceID(for: preferencesStore.preferences.preferredInputDevice)
        return preferencesStore.advancedInputAudio(for: deviceID)
    }

    var deviceName: String {
        deviceInfo?.name ?? L10n.text("preferences.audio.advanced.device.unavailable")
    }

    func refresh() {
        refreshState(normalizeIfNeeded: true)
    }

    func normalizeCurrentPreferencesIfNeeded() {
        refreshState(normalizeIfNeeded: true)
    }

    func handleInputDevicePreferenceChange() {
        refreshState(normalizeIfNeeded: true)
    }

    func updateAdvancedEnabled(_ enabled: Bool) {
        var preferences = advancedPreferences
        preferences.isEnabled = enabled
        apply(preferences)
    }

    func updateEchoCancellationEnabled(_ enabled: Bool) {
        var preferences = advancedPreferences
        preferences.echoCancellationEnabled = enabled
        apply(preferences)
    }

    func updatePreset(_ preset: InputChannelPreset) {
        var preferences = advancedPreferences
        preferences.preset = preset
        apply(preferences)
    }

    func updateLimiterEnabled(_ enabled: Bool) {
        var preferences = advancedPreferences
        preferences.limiterEnabled = enabled
        apply(preferences)
    }

    func updateDynamicProcessorEnabled(_ enabled: Bool) {
        var preferences = advancedPreferences
        preferences.dynamicProcessorEnabled = enabled
        apply(preferences)
    }

    func updateDynamicProcessorMode(_ mode: DynamicProcessorMode) {
        var preferences = advancedPreferences
        preferences.dynamicProcessorMode = mode
        apply(preferences)
    }

    func updateGateThresholdDB(_ value: Double) {
        var preferences = advancedPreferences
        preferences.gate.thresholdDB = AdvancedInputAudioPreferences.clampNoiseGateThresholdDB(value)
        apply(preferences)
    }

    func updateGateAttackMilliseconds(_ value: Double) {
        var preferences = advancedPreferences
        preferences.gate.attackMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateAttackMilliseconds(value)
        apply(preferences)
    }

    func updateGateHoldMilliseconds(_ value: Double) {
        var preferences = advancedPreferences
        preferences.gate.holdMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateHoldMilliseconds(value)
        apply(preferences)
    }

    func updateGateReleaseMilliseconds(_ value: Double) {
        var preferences = advancedPreferences
        preferences.gate.releaseMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateReleaseMilliseconds(value)
        apply(preferences)
    }

    func updateExpanderThresholdDB(_ value: Double) {
        var preferences = advancedPreferences
        preferences.expander.thresholdDB = AdvancedInputAudioPreferences.clampNoiseGateThresholdDB(value)
        apply(preferences)
    }

    func updateExpanderRatio(_ value: Double) {
        var preferences = advancedPreferences
        preferences.expander.ratio = AdvancedInputAudioPreferences.clampExpanderRatio(value)
        apply(preferences)
    }

    func updateExpanderAttackMilliseconds(_ value: Double) {
        var preferences = advancedPreferences
        preferences.expander.attackMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateAttackMilliseconds(value)
        apply(preferences)
    }

    func updateExpanderReleaseMilliseconds(_ value: Double) {
        var preferences = advancedPreferences
        preferences.expander.releaseMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateReleaseMilliseconds(value)
        apply(preferences)
    }

    func updateLimiterMode(_ mode: LimiterControlMode) {
        var preferences = advancedPreferences
        preferences.limiterMode = mode
        apply(preferences)
    }

    func updateLimiterPreset(_ preset: LimiterPreset) {
        var preferences = advancedPreferences
        preferences.limiterPreset = preset
        apply(preferences)
    }

    func updateLimiterThresholdDB(_ value: Double) {
        var preferences = advancedPreferences
        preferences.limiterThresholdDB = AdvancedInputAudioPreferences.clampThresholdDB(value)
        apply(preferences)
    }

    func updateLimiterReleaseMilliseconds(_ value: Double) {
        var preferences = advancedPreferences
        preferences.limiterReleaseMilliseconds = AdvancedInputAudioPreferences.clampReleaseMilliseconds(value)
        apply(preferences)
    }

    func togglePreview() {
        if isPreviewRunning {
            stopPreview()
            return
        }

        do {
            try startPreview()
            lastErrorMessage = nil
            isPreviewRunning = true
        } catch {
            lastErrorMessage = error.localizedDescription
            isPreviewRunning = false
        }
    }

    func stopPreview() {
        previewController.stop()
        isPreviewRunning = false
    }

    private func apply(_ preferences: AdvancedInputAudioPreferences) {
        feedbackMessage = nil
        preferencesStore.updateAdvancedInputAudio(preferences, for: deviceInfo?.uid)
        refreshState(normalizeIfNeeded: true)
        if isPreviewRunning {
            do {
                try startPreview()
                lastErrorMessage = nil
            } catch {
                stopPreview()
                lastErrorMessage = error.localizedDescription
            }
        }
        connectionController.applyAudioPreferences(preferencesStore.preferences) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.lastErrorMessage = nil
            case .failure(let error):
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func refreshState(normalizeIfNeeded: Bool) -> Bool {
        let selectedDevice = InputAudioDeviceResolver.resolveCurrentInputDevice(for: preferencesStore.preferences.preferredInputDevice)
        let deviceID = selectedDevice?.uid
        let storedPreferences = preferencesStore.advancedInputAudio(for: deviceID)
        let normalized = InputAudioDeviceResolver.normalizedPreferences(
            storedPreferences,
            for: selectedDevice
        )

        deviceInfo = selectedDevice
        presetOptions = InputAudioDeviceResolver.availablePresetOptions(for: selectedDevice)
        summaryText = InputAudioDeviceResolver.summary(for: normalized.preferences)

        let shouldMaterializeFallbackProfile =
            deviceID != nil &&
            preferencesStore.preferences.advancedInputAudioProfiles.profilesByDeviceID[deviceID ?? ""] == nil &&
            preferencesStore.preferences.advancedInputAudioProfiles.fallbackProfile != nil

        if normalized.didFallbackToAuto {
            feedbackMessage = L10n.text("preferences.audio.advanced.feedback.fallbackAuto")
        } else if isNormalizing == false {
            feedbackMessage = nil
        }

        guard normalizeIfNeeded,
              (normalized.didFallbackToAuto || shouldMaterializeFallbackProfile),
              isNormalizing == false else {
            return normalized.didFallbackToAuto
        }

        isNormalizing = true
        preferencesStore.updateAdvancedInputAudio(normalized.preferences, for: deviceID)
        if shouldMaterializeFallbackProfile {
            preferencesStore.clearAdvancedInputAudioFallbackProfile()
        }
        isNormalizing = false
        return true
    }

    private func startPreview() throws {
        guard let deviceInfo else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        let normalized = InputAudioDeviceResolver.normalizedPreferences(
            advancedPreferences,
            for: deviceInfo
        ).preferences

        let effectivePreferences: AdvancedInputAudioPreferences
        if normalized.isEnabled {
            effectivePreferences = normalized
        } else {
            var disabled = normalized
            disabled.preset = .auto
            disabled.dynamicProcessorEnabled = false
            disabled.limiterEnabled = false
            effectivePreferences = disabled
        }

        let targetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: deviceInfo.nominalSampleRate > 0 ? deviceInfo.nominalSampleRate : 48_000,
            channels: previewChannelCount(for: effectivePreferences.preset, availableChannels: deviceInfo.inputChannels),
            txIntervalMSec: 40
        )

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
            limiterThresholdDB: effectivePreferences.limiterThresholdDB,
            limiterReleaseMilliseconds: effectivePreferences.limiterReleaseMilliseconds,
            targetFormat: targetFormat
        )

        try previewController.start(configuration: configuration)
    }

    private func previewChannelCount(for preset: InputChannelPreset, availableChannels: Int) -> Int {
        switch preset {
        case .auto:
            return availableChannels >= 2 ? 2 : 1
        case .mono, .monoMix:
            return 1
        case .stereoPair:
            return 2
        }
    }
}
