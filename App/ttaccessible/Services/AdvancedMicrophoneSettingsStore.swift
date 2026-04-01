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
    @Published private(set) var summaryText: String = ""
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

    func handleInputDevicePreferenceChange() {
        refreshState(normalizeIfNeeded: true)
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

        let targetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: deviceInfo.nominalSampleRate > 0 ? deviceInfo.nominalSampleRate : 48_000,
            channels: previewChannelCount(for: normalized.preset, availableChannels: deviceInfo.inputChannels),
            txIntervalMSec: 40
        )

        let configuration = AdvancedMicrophoneAudioConfiguration(
            device: deviceInfo,
            preset: normalized.preset,
            inputGainDB: preferencesStore.preferences.inputGainDB,
            targetFormat: targetFormat,
            echoCancellationEnabled: false
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
