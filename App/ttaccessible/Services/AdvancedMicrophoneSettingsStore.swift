//
//  AdvancedMicrophoneSettingsStore.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Combine
import CoreAudio
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

        // dropFirst() skips the synchronous emit Combine delivers at
        // subscription time. That initial emit re-ran the same device
        // enumeration as the explicit warm-up below — a redundant second
        // synchronous CoreAudio pass during construction. We only want this
        // sink to react to *subsequent* preference changes.
        preferencesStore.$preferences
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshState(normalizeIfNeeded: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopPreviewNotification),
            name: .stopAdvancedMicrophonePreview,
            object: nil
        )

        // The app eagerly constructs this store at launch to warm the
        // Preferences window, but refreshState() does synchronous CoreAudio
        // device enumeration that blocked the launch run-loop tick. Defer it so
        // construction returns immediately; the Audio pane re-runs refresh()
        // via prepareIfNeeded() before it is ever shown, so nothing user-facing
        // depends on this having completed synchronously.
        DispatchQueue.main.async { [weak self] in
            self?.refreshState(normalizeIfNeeded: true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func handleStopPreviewNotification() {
        stopPreview()
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

    func updateProcessingMode(_ mode: MicrophoneProcessingMode) {
        var preferences = advancedPreferences
        preferences.processingMode = mode
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

        // While connected, the live mic engine owns the input device, so a second
        // capture can't open. Instead monitor the live mic through the output engine
        // (it produces sound while the mic is actually capturing/transmitting).
        if connectionController.isConnected {
            connectionController.setPreviewMonitor(true)
            lastErrorMessage = nil
            isPreviewRunning = true
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
        connectionController.setPreviewMonitor(false)
        previewController.stop()
        isPreviewRunning = false
    }

    private func apply(_ preferences: AdvancedInputAudioPreferences) {
        feedbackMessage = nil
        preferencesStore.updateAdvancedInputAudio(preferences, for: deviceInfo?.uid)
        refreshState(normalizeIfNeeded: true)
        // Only the local (disconnected) preview needs restarting to pick up new
        // settings; the connected monitor follows the live engine, which
        // applyAudioPreferences below reconfigures.
        if isPreviewRunning && connectionController.isConnected == false {
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

        // AVAudioEngine's playback path creates a CADefaultDeviceAggregate, which fires
        // kAudioHardwarePropertyDevices — without this suppression the debounced
        // restartSoundSystem fires ~500 ms later and silently kills the capture AUHAL.
        connectionController.suppressNextDeviceChange(for: 2.0)

        let normalized = InputAudioDeviceResolver.normalizedPreferences(
            advancedPreferences,
            for: deviceInfo
        ).preferences

        // Resolve the selected output device so preview monitoring plays through
        // it (not the system default) and at its native sample rate. The output
        // preference is a TeamTalk device id, which doesn't translate directly to
        // a CoreAudio device, so resolveOutputDevice matches by UID then name.
        let outputPreference = preferencesStore.preferences.preferredOutputDevice
        let resolvedOutput = outputPreference.usesSystemDefault
            ? nil
            : InputAudioDeviceResolver.resolveOutputDevice(
                persistentID: outputPreference.persistentID,
                displayName: outputPreference.displayName
            )
        let outputDeviceID = resolvedOutput?.deviceID
        let previewSampleRate = resolvedOutput?.nominalSampleRate
            ?? (deviceInfo.nominalSampleRate > 0 ? deviceInfo.nominalSampleRate : 48_000)

        let targetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: previewSampleRate,
            channels: previewChannelCount(for: normalized.preset, availableChannels: deviceInfo.inputChannels),
            txIntervalMSec: 40
        )

        let configuration = AdvancedMicrophoneAudioConfiguration(
            device: deviceInfo,
            preset: normalized.preset,
            inputGainDB: preferencesStore.preferences.inputGainDB,
            targetFormat: targetFormat,
            // Echo cancellation needs a speaker reference that the local preview can't
            // provide, so it stays off here; noise suppression works standalone.
            echoCancellationEnabled: false,
            noiseSuppressionEnabled: normalized.noiseSuppressionEnabled
        )

        try previewController.start(configuration: configuration, outputDeviceID: outputDeviceID)
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
