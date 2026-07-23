//
//  TeamTalkConnectionController+Audio.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 30/03/2026.
//

import AVFoundation
import CoreAudio
import Foundation

extension TeamTalkConnectionController {
    enum AudioDirection {
        case input
        case output
    }

    // Build the audio-device catalog on the connection queue and deliver it on
    // the main actor. The TeamTalk SDK's TT_GetSoundDevices can take many
    // seconds to probe a large CoreAudio setup (27 devices ≈ 15s on a Pro
    // Tools / aggregate-heavy rig), so this must never run through a main-thread
    // queue.sync — doing so froze the app for the entire probe during launch.
    func availableAudioDevices(completion: @escaping @MainActor (AudioDeviceCatalog) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion(.empty) }
                return
            }
            if let cached = self.cachedAudioDeviceCatalog {
                Task { @MainActor in completion(cached) }
                return
            }
            let catalog = Self.buildCoreAudioCatalog()
            self.cachedAudioDeviceCatalog = catalog
            Task { @MainActor in completion(catalog) }
        }
    }

    func refreshAvailableAudioDevices(completion: @escaping @MainActor (AudioDeviceCatalog) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion(.empty) }
                return
            }
            let catalog = Self.buildCoreAudioCatalog()
            self.cachedAudioDeviceCatalog = catalog
            Task { @MainActor in completion(catalog) }
        }
    }

    /// Build the device-picker catalog directly from CoreAudio, identifying every
    /// device by its stable `kAudioDevicePropertyDeviceUID`. This is the same
    /// identity the audio engines actually bind by (see InputAudioDeviceResolver /
    /// OutputAudioRenderEngine), so the picker, the persisted preference, and the
    /// binding layer all share ONE stable key. The SDK is bypassed (both
    /// directions open the TeamTalk virtual device), so its sound-device list —
    /// whose `nDeviceID` reshuffles across launches/hot-plug and whose
    /// `szDeviceID` is empty on macOS — is no longer consulted for device
    /// identity. CoreAudio enumeration is a few ms, so no off-queue probe needed.
    nonisolated static func buildCoreAudioCatalog() -> AudioDeviceCatalog {
        func option(uid: String, name: String) -> AudioDeviceOption {
            AudioDeviceOption(id: uid, persistentID: uid, displayName: name)
        }
        let inputDevices = InputAudioDeviceResolver.availableInputDevices()
            .filter { $0.name.hasPrefix("CADefaultDeviceAggregate") == false }
            .map { option(uid: $0.uid, name: $0.name) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let outputDevices = InputAudioDeviceResolver.availableOutputDevices()
            .filter { $0.name.hasPrefix("CADefaultDeviceAggregate") == false }
            .map { option(uid: $0.uid, name: $0.name) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let catalog = AudioDeviceCatalog(inputDevices: inputDevices, outputDevices: outputDevices)
        AudioLogger.log("buildCoreAudioCatalog: %d input, %d output", inputDevices.count, outputDevices.count)
        return catalog
    }

    func invalidateAudioDeviceCache() {
        queue.async { [weak self] in
            self?.cachedAudioDeviceCatalog = nil
        }
    }

    func setPushToTalkPressed(_ pressed: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let wasPressed = self.pushToTalkPressed
            guard wasPressed != pressed else { return }
            self.pushToTalkPressed = pressed
            // Both mode: releasing PTT closes the always-on gate — the mic goes
            // silent (stays silent until ⌘⇧A reopens it or PTT is held again),
            // matching the "PTT takes over" behavior.
            if self.currentMicrophoneMode == .both, wasPressed, pressed == false, self.bothGateOpen {
                self.bothGateOpen = false
            }
            // Publish on EVERY press/release transition: the snapshot's own
            // isTalking tracks isEffectivelyTransmittingLocked, so VoiceOver's
            // talking state must refresh with the key, not only on gate closes.
            if let instance = self.instance, let record = self.connectedRecord {
                self.publishSessionLocked(instance: instance, record: record)
            }
        }
    }

    /// The active microphone mode, cached queue-side: the hot paths (every mic
    /// chunk) must not read the `@Published` preferences struct across threads
    /// (data race with main-thread mutation + a whole-struct copy per chunk).
    /// Updated via applyMicrophoneHotkeySettings from the preferences sink.
    var currentMicrophoneMode: AppPreferences.MicrophoneMode {
        cachedMicrophoneMode
    }

    /// The persistent, user-controlled transmit gate reflected by the mic mute
    /// button / menu. In "both" mode this is the always-on gate; otherwise it is
    /// the engine-armed flag (unchanged behavior for always-on / push-to-talk).
    var microphoneGateOpenLocked: Bool {
        currentMicrophoneMode == .both ? bothGateOpen : voiceTransmissionEnabled
    }

    /// Whether voice is actually flowing to the channel right now (momentary —
    /// tracks PTT). This is THE transmit gate: the chunk-insert path guards on
    /// it directly.
    var isEffectivelyTransmittingLocked: Bool {
        guard voiceTransmissionEnabled else { return false }
        switch currentMicrophoneMode {
        case .alwaysOn:
            return true
        case .pushToTalk:
            // PTT only gates transmission when a key is actually configured.
            // Without one, pushToTalkPressed could never become true and the
            // mic would be silently muted forever — fall back to always-on so
            // the user is at least heard.
            return cachedPushToTalkKeyConfigured == false || pushToTalkPressed
        case .both:
            return pushToTalkPressed || bothGateOpen
        }
    }

    /// Toggles the "both" mode gate (⌘⇧A). Ensures the engine is hot when
    /// opening, so this is instant and never tears the mic engine down.
    /// The success value is the AUTHORITATIVE gate state after the toggle
    /// (computed on the controller queue) — callers must announce/act on it,
    /// not on a main-thread session snapshot, which can be stale under quick
    /// repeated toggles.
    func toggleBothModeGate(completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let instance = self.instance, let record = self.connectedRecord else {
                self.healStaleSessionIfNeededLocked()
                self.finishOnMain(.failure(self.sessionUnavailableErrorLocked()), completion: completion)
                return
            }
            guard TT_GetMyChannelID(instance) > 0 else {
                self.finishOnMain(
                    .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel"))),
                    completion: completion
                )
                return
            }

            let opening = self.bothGateOpen == false
            if opening {
                if self.voiceTransmissionEnabled == false {
                    do {
                        try self.ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                        self.voiceTransmissionEnabled = true
                    } catch {
                        self.finishOnMain(.failure(error), completion: completion)
                        return
                    }
                }
                self.bothGateOpen = true
                SoundPlayer.shared.play(.voxMeEnable)
            } else {
                self.bothGateOpen = false
                SoundPlayer.shared.play(.voxMeDisable)
            }
            self.publishSessionLocked(instance: instance, record: record)
            self.finishOnMain(.success(opening), completion: completion)
        }
    }

    /// Arms the mic engine hot (silent, gated) whenever "both" mode needs it and
    /// the app is on the current controller queue. Called on channel join and on
    /// a mode change to "both". Starts with the gate closed (muted).
    func armBothModeEngineIfNeededLocked(instance: UnsafeMutableRawPointer) {
        guard currentMicrophoneMode == .both else { return }
        guard voiceTransmissionEnabled == false else { return }
        guard TT_GetMyChannelID(instance) > 0 else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        do {
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
            voiceTransmissionEnabled = true
            bothGateOpen = false
            // Deliberately silent: the mic is hot but not transmitting.
        } catch {
            AudioLogger.log("both-mode engine arm failed: %@", error.localizedDescription)
        }
    }

    /// Called when our own user joins a channel. In "both" mode the mic engine
    /// is armed hot (silent, gated) for instant PTT; in always-on / push-to-talk
    /// it restores the last transmit state, as before.
    func armMicrophoneEngineOnJoinLocked(instance: UnsafeMutableRawPointer) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        if currentMicrophoneMode == .both {
            armBothModeEngineIfNeededLocked(instance: instance)
            if let connectedRecord {
                publishSessionLocked(instance: instance, record: connectedRecord)
            }
            return
        }
        guard voiceTransmissionEnabled == false,
              preferencesStore.preferences.lastVoiceTransmissionEnabled else { return }
        do {
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
            voiceTransmissionEnabled = true
            SoundPlayer.shared.play(.voxMeEnable)
            if let connectedRecord {
                publishSessionLocked(instance: instance, record: connectedRecord)
            }
        } catch {
            AudioLogger.log("auto-restore mic on join failed: %@", error.localizedDescription)
        }
    }

    /// Applies the current microphone hotkey settings (from the preferences
    /// sink — the passed values are the PUBLISHED ones; @Published fires in
    /// willSet, so re-reading the store here would see stale prefs).
    ///
    /// On a mode CHANGE the transmit state is normalized explicitly, so no
    /// mode can inherit another mode's flags in a way that opens the mic
    /// without user action: `pushToTalkPressed`/`bothGateOpen` always reset,
    /// and `voiceTransmissionEnabled` is re-derived from whether the
    /// user-facing gate was open under the OLD mode. Concretely: leaving a
    /// muted "both" (engine hot, gate closed) for always-on tears the engine
    /// down instead of going live; entering "both" always starts gated-closed.
    func applyMicrophoneHotkeySettings(mode: AppPreferences.MicrophoneMode, pushToTalkKeyConfigured: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cachedPushToTalkKeyConfigured = pushToTalkKeyConfigured
            let oldMode = self.cachedMicrophoneMode
            guard mode != oldMode else { return }
            // The user-facing "mic on" gate under the OLD mode — the intent
            // the new mode must honor (read before the cache flips).
            let wasGateOpen = self.microphoneGateOpenLocked
            self.cachedMicrophoneMode = mode
            self.pushToTalkPressed = false
            self.bothGateOpen = false
            guard let instance = self.instance else { return }
            switch mode {
            case .alwaysOn:
                if wasGateOpen == false, self.voiceTransmissionEnabled {
                    // Engine hot but user-muted (both-mode gate closed): going
                    // live silently is the one transition that must not happen.
                    self.stopAdvancedMicrophoneInputLocked(instance: instance, reason: "mode change to always-on while muted")
                    self.voiceTransmissionEnabled = false
                }
            case .pushToTalk:
                // An armed state carries over only if the user-facing gate was
                // open. Engine hot but user-muted (both-mode gate closed) must
                // tear down like the always-on case: with no PTT key configured
                // this mode falls back to always-transmit, so leaving the
                // engine armed would open the mic without user action.
                if wasGateOpen == false, self.voiceTransmissionEnabled {
                    self.stopAdvancedMicrophoneInputLocked(instance: instance, reason: "mode change to push-to-talk while muted")
                    self.voiceTransmissionEnabled = false
                }
            case .both:
                // Arm hot with the gate closed (silent) for instant PTT.
                self.armBothModeEngineIfNeededLocked(instance: instance)
            }
            if let record = self.connectedRecord {
                self.publishSessionLocked(instance: instance, record: record)
            }
        }
    }

    /// Briefly ignore the next device-change-triggered restart. Used by paths that
    /// intentionally create transient CoreAudio aggregates (speaker tap, audio preview),
    /// since those creations fire `kAudioHardwarePropertyDevices` and would otherwise
    /// trigger a debounced `restartSoundSystem` that disrupts the new audio graph.
    func suppressNextDeviceChange(for duration: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            self.extendDeviceChangeSuppressionLocked(duration: duration)
        }
    }

    func handleDebouncedAudioHardwareChange(selector: UInt32) {
        queue.async { [weak self] in
            guard let self else { return }
            self.audioHardwareChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.processAudioHardwareChangeLocked(selector: selector)
            }
            self.audioHardwareChangeWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + .milliseconds(500), execute: workItem)
        }
    }

    func restartSoundSystem(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }

            guard !self.isRestartingSoundSystem else {
                AudioLogger.log("restartSoundSystem: skipped (already restarting)")
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            self.isRestartingSoundSystem = true
            defer { self.isRestartingSoundSystem = false }

            self.extendDeviceChangeSuppressionLocked(duration: 5.0)
            AudioLogger.log("restartSoundSystem: begin")

            let hadMic = self.isAnyMicrophoneEngineRunning || self.inputAudioReady
            let hadVoice = self.voiceTransmissionEnabled
            if hadMic, let instance = self.instance {
                self.stopAdvancedMicrophoneInputLocked(instance: instance, reason: "restartSoundSystem")
            }

            if self.teamTalkVirtualInputReady, let instance = self.instance {
                _ = TT_CloseSoundInputDevice(instance)
                self.teamTalkVirtualInputReady = false
            }

            let hadOutput = self.outputAudioReady
            if hadOutput, let instance = self.instance {
                self.teardownOutputRenderLocked(instance: instance)
                _ = TT_CloseSoundOutputDevice(instance)
                self.outputAudioReady = false
            }

            let ok = TT_RestartSoundSystem()
            self.cachedAudioDeviceCatalog = nil

            AudioLogger.log("restartSoundSystem: TT_RestartSoundSystem returned %d", ok)

            guard ok != 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("preferences.audio.refreshDevices.error"))))
                }
                return
            }

            // Re-open output if either: (a) it was open before the restart, or
            // (b) it wasn't open but the user's current preference is a real
            // device. Case (b) covers the no-output→device switch while only
            // the mic is active: hadOutput is false, but the user does want
            // playback after the change. ensureDirectOutputAudioReadyLocked
            // self-skips when the preference is no-output, so an unconditional
            // call would also be safe — this guard just avoids the function
            // call when there's clearly nothing to do.
            let prefersOutputDevice = !self.preferencesStore.preferences.preferredOutputDevice.usesNoOutput
            if (hadOutput || prefersOutputDevice), let instance = self.instance {
                do {
                    // Reopens the virtual output + muxed event and starts the render
                    // engine directly (gain/mute reapplied inside).
                    try self.ensureDirectOutputAudioReadyLocked(instance: instance)
                } catch {
                    AudioLogger.log("restartSoundSystem: output re-open failed — %@", error.localizedDescription)
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
            }

            if hadMic, let instance = self.instance {
                do {
                    try self.ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                    if hadVoice { self.voiceTransmissionEnabled = true }
                } catch {
                    AudioLogger.log("restartSoundSystem: mic restart failed — %@", error.localizedDescription)
                    self.voiceTransmissionEnabled = false
                    self.inputAudioReady = false
                    self.advancedMicrophoneTargetFormat = nil
                    SoundPlayer.shared.play(.voxMeDisable)
                    if let connectedRecord = self.connectedRecord {
                        self.publishSessionLocked(instance: instance, record: connectedRecord)
                    }
                    self.lastAudioWarningMessage = L10n.text("connectedServer.audio.error.microphoneRestartFailed")
                }
            }

            self.captureAudioRoutingSnapshotLocked()
            AudioLogger.log("restartSoundSystem: done")
            DispatchQueue.main.async { completion(.success(())) }
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

            // Fast path: close and reopen just the affected devices (~0.1s, a
            // brief stutter). This is the behavior that shipped before ee7af8b
            // rerouted active-audio changes through a full TT_RestartSoundSystem,
            // which takes ~12s on large device setups (27 devices measured) and
            // drops ALL audio for the whole call. reinitializeAudioDevicesLocked
            // is unchanged from that prior version; the cached device list is
            // valid for routing-only changes (hardware add/remove is handled
            // separately and refreshes the cache). Fall back to the full restart
            // only if the fast reopen actually throws.
            // Only reinitialize the device(s) that actually changed. An input-only
            // change must NOT close/reopen the output (and vice versa) — both to
            // avoid a needless playback gap and to keep input switches away from
            // the intermittent TT_CloseSoundOutputDevice deadlock entirely.
            let outputChanged = self.appliedOutputPreference == nil
                || preferences.preferredOutputDevice != self.appliedOutputPreference
            let inputChanged = self.appliedInputPreference == nil
                || preferences.preferredInputDevice != self.appliedInputPreference
            // Microphone processing (AEC / noise-suppression mode / channel preset)
            // changed without a device change — the capture engine must be rebuilt so
            // the WebRTC processor is recreated with the new flags, otherwise the change
            // only takes effect after the user manually stops & restarts transmission.
            let micProcessingChanged = self.advancedMicrophoneProcessingChangedLocked(preferences: preferences)

            guard outputChanged || inputChanged || micProcessingChanged else {
                self.appliedOutputPreference = preferences.preferredOutputDevice
                self.appliedInputPreference = preferences.preferredInputDevice
                DispatchQueue.main.async { completion(.success(())) }
                return
            }

            do {
                try self.reinitializeAudioDevicesLocked(
                    instance: instance,
                    preferences: preferences,
                    reinitInput: inputChanged || micProcessingChanged,
                    reinitOutput: outputChanged
                )
                self.captureAudioRoutingSnapshotLocked()
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                AudioLogger.log("applyAudioPreferences: fast reinit failed (%@) — falling back to full sound-system restart", error.localizedDescription)
                self.restartSoundSystem { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        if let instance = self.instance, let record = self.connectedRecord {
                            self.publishSessionLocked(instance: instance, record: record)
                        }
                        DispatchQueue.main.async { completion(.success(())) }
                    case .failure(let error):
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                }
            }
        }
    }

    func reloadPreferredAudioDevicesIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        applyAudioPreferences(preferencesStore.preferences, completion: completion)
    }

    func applyInputGainDB(_ value: Double) {
        let clamped = AppPreferences.clampGainDB(value)
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.advancedMicrophoneEngine.updateInputGainDB(clamped)
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
            guard let self else { return }
            guard let instance = self.instance, let record = self.connectedRecord else {
                self.healStaleSessionIfNeededLocked()
                self.finishOnMain(.failure(self.sessionUnavailableErrorLocked()), completion: completion)
                return
            }

            guard TT_GetMyChannelID(instance) > 0 else {
                self.finishOnMain(
                    .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel"))),
                    completion: completion
                )
                return
            }

            self.extendDeviceChangeSuppressionLocked(duration: 3.0)
            do {
                try self.ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                self.voiceTransmissionEnabled = true
                SoundPlayer.shared.play(.voxMeEnable)
                self.publishSessionLocked(instance: instance, record: record)
                let preferencesStore = self.preferencesStore
                DispatchQueue.main.async {
                    preferencesStore.updateLastVoiceTransmissionEnabled(true)
                }
                self.captureAudioRoutingSnapshotLocked()
                self.finishOnMain(.success(()), completion: completion)
            } catch {
                self.finishOnMain(.failure(error), completion: completion)
            }
        }
    }

    func deactivateVoiceTransmission(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let instance = self.instance, let record = self.connectedRecord else {
                self.healStaleSessionIfNeededLocked()
                self.finishOnMain(.failure(self.sessionUnavailableErrorLocked()), completion: completion)
                return
            }

            if self.isAnyMicrophoneEngineRunning || self.inputAudioReady {
                self.stopAdvancedMicrophoneInputLocked(instance: instance, reason: "deactivateVoiceTransmission")
            }
            self.voiceTransmissionEnabled = false
            self.inputAudioReady = false
            self.advancedMicrophoneTargetFormat = nil
            SoundPlayer.shared.play(.voxMeDisable)
            self.publishSessionLocked(instance: instance, record: record)

            let preferencesStore = self.preferencesStore
            DispatchQueue.main.async {
                preferencesStore.updateLastVoiceTransmissionEnabled(false)
            }
            self.finishOnMain(.success(()), completion: completion)
        }
    }

    func ensureOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard outputAudioReady == false else {
            return
        }

        try ensureDirectOutputAudioReadyLocked(instance: instance)
    }

    func ensureAdvancedMicrophoneInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard inputAudioReady == false else {
            return
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .stopAdvancedMicrophonePreview, object: nil)
        }

        guard let deviceInfo = InputAudioDeviceResolver.resolveCurrentInputDevice(for: preferencesStore.preferences.preferredInputDevice) else {
            throw TeamTalkConnectionError.internalError(L10n.text("preferences.audio.advanced.error.deviceUnavailable"))
        }

        AudioLogger.log("ensureAdvancedMicrophoneInputReady: device=%@ channels=%d rate=%.0f", deviceInfo.name, deviceInfo.inputChannels, deviceInfo.nominalSampleRate)

        let effectivePreferences = effectiveMicrophoneProcessingPreferencesLocked(for: deviceInfo)
        let targetFormat = try currentAdvancedMicrophoneTargetFormatLocked(instance: instance)

        AudioLogger.log("ensureAdvancedMicrophoneInputReady: targetFormat rate=%.0f channels=%d txInterval=%d", targetFormat.sampleRate, targetFormat.channels, targetFormat.txIntervalMSec)

        do {
            let aecEnabled = effectivePreferences.echoCancellationEnabled
            let configuration = AdvancedMicrophoneAudioConfiguration(
                device: deviceInfo,
                preset: effectivePreferences.preset,
                inputGainDB: preferencesStore.preferences.inputGainDB,
                targetFormat: targetFormat,
                echoCancellationEnabled: aecEnabled,
                noiseSuppressionEnabled: effectivePreferences.noiseSuppressionEnabled
            )
            try ensureTeamTalkVirtualInputReadyLocked(instance: instance)
            try ensureDirectOutputAudioReadyLocked(instance: instance)
            _ = try advancedMicrophoneEngine.start(configuration: configuration)
            advancedMicrophoneTargetFormat = targetFormat
            inputAudioReady = true
            appliedInputPreference = preferencesStore.preferences.preferredInputDevice
            appliedAdvancedInputAudio = effectivePreferences
            lastAudioWarningMessage = nil

            // Monitor sample rate changes on the active input device.
            let activeDeviceUID = deviceInfo.uid
            DispatchQueue.main.async { [weak self] in
                let deviceID = InputAudioDeviceResolver.audioDeviceID(forUID: activeDeviceUID)
                self?.audioDeviceChangeMonitor?.monitorSampleRate(forDeviceID: deviceID)
            }

            // Enable AEC reference signal.
            if aecEnabled {
                if #available(macOS 14.2, *), startSpeakerTapForAEC() {
                    AudioLogger.log("AEC: using speaker tap for reference signal")
                } else {
                    // Fallback (pre-macOS 14.2): use the SDK muxed (remote) stream as
                    // the AEC far-end reference. Playback uses per-user mixing, so this
                    // muxed event is for AEC only; handleAudioBlockLocked feeds it.
                    TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, UInt32(STREAMTYPE_VOICE.rawValue), 1)
                    AudioLogger.log("AEC: using SDK muxed audio for reference signal (fallback)")
                }
            }
        } catch {
            if teamTalkVirtualInputReady {
                _ = TT_CloseSoundInputDevice(instance)
                teamTalkVirtualInputReady = false
            }
            inputAudioReady = false
            advancedMicrophoneTargetFormat = nil
            do {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
            } catch { }
            throw error
        }
    }

    func reinitializeAudioDevicesLocked(
        instance: UnsafeMutableRawPointer,
        preferences: AppPreferences,
        reinitInput: Bool = true,
        reinitOutput: Bool = true
    ) throws {
        let aecTapActive = speakerTapCaptureStorage != nil
        AudioLogger.log("reinitializeAudioDevicesLocked: begin (reinitInput=%d reinitOutput=%d voice=%d inputReady=%d outputReady=%d micEngine=%d aecTap=%d virtualInput=%d)",
            reinitInput ? 1 : 0,
            reinitOutput ? 1 : 0,
            voiceTransmissionEnabled ? 1 : 0,
            inputAudioReady ? 1 : 0,
            outputAudioReady ? 1 : 0,
            isAnyMicrophoneEngineRunning ? 1 : 0,
            aecTapActive ? 1 : 0,
            teamTalkVirtualInputReady ? 1 : 0)
        let wasVoiceTransmissionEnabled = voiceTransmissionEnabled
        let wasInputAudioReady = inputAudioReady

        if reinitInput {
            if wasVoiceTransmissionEnabled || wasInputAudioReady || isAnyMicrophoneEngineRunning {
                stopAdvancedMicrophoneInputLocked(instance: instance, reason: "reinitializeAudioDevicesLocked")
            }
            AudioLogger.log("reinit: mic input stopped")
            voiceTransmissionEnabled = false
            inputAudioReady = false
            advancedMicrophoneTargetFormat = nil

            if teamTalkVirtualInputReady {
                AudioLogger.log("reinit: closing virtual input device")
                _ = TT_CloseSoundInputDevice(instance)
                AudioLogger.log("reinit: closed virtual input device")
                teamTalkVirtualInputReady = false
            }
        }

        if reinitOutput {
            // Output bypass: the SDK output stays on the virtual device and is
            // NEVER closed here — that close (TT_CloseSoundOutputDevice -> ACE
            // recursive_mutex -> ResetAudioPlayers) is the call that intermittently
            // deadlocks under HAL overload. Switching the output device is purely a
            // rebind of OUR render engine to the newly-selected CoreAudio device:
            // all our code, fast, and no SDK audio mutex involved. Master gain/mute
            // persist in the engine across the switch.
            if let device = resolveOutputEngineDeviceLocked() {
                if outputRenderEngine.isRunning {
                    AudioLogger.log("reinit: switching output engine to %@", device.name)
                    try outputRenderEngine.switchDevice(device.deviceID)
                    AudioLogger.log("reinit: output engine switched")
                } else {
                    AudioLogger.log("reinit: output engine idle; starts on next muxed block")
                }
            } else {
                AudioLogger.log("reinit: no output device resolved for switch")
            }
            appliedOutputPreference = preferencesStore.preferences.preferredOutputDevice
        }

        if reinitInput, wasVoiceTransmissionEnabled || wasInputAudioReady {
            AudioLogger.log("reinit: restarting mic input")
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
            AudioLogger.log("reinit: mic input restarted")
        }

        if reinitInput, wasVoiceTransmissionEnabled {
            voiceTransmissionEnabled = true
        }

        captureAudioRoutingSnapshotLocked()
        AudioLogger.log("reinitializeAudioDevicesLocked: done")
    }

    func makeAudioStatusText() -> String {
        var status: String
        if microphoneGateOpenLocked {
            status = L10n.text("connectedServer.audio.status.microphoneActive")
        } else if inputAudioReady {
            status = L10n.text("connectedServer.audio.status.inputReady")
        } else if outputAudioReady {
            status = L10n.text("connectedServer.audio.status.outputReady")
        } else if preferencesStore.preferences.preferredOutputDevice.usesNoOutput {
            // No output is a deliberate choice, not a failure — don't report it
            // as "unavailable" (which reads as an error, esp. via VoiceOver).
            status = L10n.text("connectedServer.audio.status.noOutput")
        } else {
            status = L10n.text("connectedServer.audio.status.unavailable")
        }
        if recordingMuxedActive || recordingSeparateActive {
            status += " — " + L10n.text("connectedServer.audio.status.recording")
        }
        if let lastAudioWarningMessage {
            status += " — " + lastAudioWarningMessage
        }
        return status
    }

    func ensureDirectOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard outputAudioReady == false else {
            return
        }

        // Explicit "no output device" preference: the user wants this profile
        // to transmit and stay connected while another instance carries the
        // audio. Skip the SDK init entirely and leave outputAudioReady=false.
        if preferencesStore.preferences.preferredOutputDevice.usesNoOutput {
            AudioLogger.log("ensureDirectOutputAudioReady: preference is no-output — skipping init")
            return
        }

        // Output bypass: point the SDK at the virtual output device so it never
        // owns a physical CoreAudio output device (whose close intermittently
        // deadlocks). We receive each remote user's decoded PCM as per-user audio
        // blocks and MIX them ourselves (the local user is never fed in, so you
        // never hear yourself) through OutputAudioRenderEngine, which also lets us
        // own per-person pan/volume/mute. The physical output device is chosen by
        // the render engine (resolveOutputEngineDeviceLocked), not the SDK.
        AudioLogger.log("ensureDirectOutputAudioReady: opening virtual output device (bypass)")
        guard TT_InitSoundOutputDevice(instance, TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) != 0 else {
            AudioLogger.log("ensureDirectOutputAudioReady: FAILED to open virtual output device")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        outputAudioReady = true
        appliedOutputPreference = preferencesStore.preferences.preferredOutputDevice
        startOutputRenderEngineLocked()
        // Start the dedicated block drainer BEFORE enabling events, so the user
        // set pushed by the refresh below lands on a running pump.
        audioBlockPump.start(instance: instance, engine: outputRenderEngine)
        // Enable per-user audio block events for whoever is already in our channel.
        refreshPerUserAudioEventsLocked(instance: instance)
        // Re-arm our own media subscription if a stream is already active (e.g. the
        // output path was (re)opened mid-stream after a reconnect).
        refreshLocalMediaAudioEventLocked(instance: instance)
        AudioLogger.log("ensureDirectOutputAudioReady: virtual output ready")
    }

    /// Resolve the CoreAudio output device the render engine should bind to,
    /// honoring the user's explicit preference and falling back to the system
    /// default output.
    func resolveOutputEngineDeviceLocked() -> InputAudioDeviceResolver.OutputAudioDeviceInfo? {
        let pref = preferencesStore.preferences.preferredOutputDevice
        if pref.usesSystemDefault == false,
           let info = InputAudioDeviceResolver.resolveOutputDevice(
               persistentID: pref.persistentID,
               displayName: pref.displayName
           ) {
            return info
        }
        let devices = InputAudioDeviceResolver.availableOutputDevices()
        if let defaultUID = InputAudioDeviceResolver.defaultOutputDeviceUID(),
           let match = devices.first(where: { $0.uid == defaultUID }) {
            return match
        }
        return devices.first
    }

    /// Start the output render engine on the currently-selected output device.
    func startOutputRenderEngineLocked() {
        guard outputAudioReady, outputRenderEngine.isRunning == false else { return }
        guard let device = resolveOutputEngineDeviceLocked() else {
            AudioLogger.log("outputRenderEngine: no output device available to start")
            return
        }
        outputRenderEngine.setMasterGainDB(preferencesStore.preferences.outputGainDB)
        outputRenderEngine.setMuted(masterMuted)
        do {
            try outputRenderEngine.start(deviceID: device.deviceID)
            AudioLogger.log("outputRenderEngine: started on %@", device.name)
        } catch {
            AudioLogger.log("outputRenderEngine: start failed — %@", error.localizedDescription)
        }
    }

    /// Separate mixer key for a user's media-file stream (kept distinct from their
    /// voice stream). Static so AudioBlockPump shares the same mapping.
    nonisolated static func outputMediaSourceKey(_ userID: Int32) -> Int32 { userID | 0x4000_0000 }
    func outputMediaSourceKey(_ userID: Int32) -> Int32 { Self.outputMediaSourceKey(userID) }

    /// Reserved mixer key for the local "hear myself" monitor (negative, so it
    /// never collides with real user IDs or media keys, both positive).
    var localMonitorEngineKey: Int32 { -1 }

    /// Reserved mixer key for our OWN streamed media file, so the local user hears
    /// what they broadcast. Negative for the same no-collision reason. Static so
    /// AudioBlockPump shares the same key.
    nonisolated static let localMediaEngineKey: Int32 = -2
    var localMediaEngineKey: Int32 { Self.localMediaEngineKey }

    /// Subscribe (or unsubscribe) to our OWN media-file stream so the local user
    /// hears the media they broadcast into the channel. The SDK delivers this on
    /// TT_LOCAL_USERID + STREAMTYPE_MEDIAFILE_AUDIO. Voice is intentionally never
    /// self-monitored here — "hear myself" handles that separately.
    func refreshLocalMediaAudioEventLocked(instance: UnsafeMutableRawPointer) {
        // Device streams self-monitor only when the user opted in (the source is
        // usually audible locally already — hearing it back would be an echo).
        let monitorAllowed = deviceStreamSource == nil || deviceStreamMonitorEnabled
        let shouldEnable = outputAudioReady && mediaStreamingActive && monitorAllowed
        guard shouldEnable != localMediaAudioEnabled else { return }
        let media = UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue)
        if shouldEnable {
            TT_EnableAudioBlockEvent(instance, TT_LOCAL_USERID, media, 1)
            AudioLogger.log("local media: subscribed to own media stream for local playback")
        } else {
            TT_EnableAudioBlockEvent(instance, TT_LOCAL_USERID, media, 0)
            AudioLogger.log("local media: unsubscribed from own media stream")
        }
        localMediaAudioEnabled = shouldEnable
        // The pump drains this stream and removes its mix source on disable
        // (ordered after its final enqueue).
        audioBlockPump.setLocalMediaEnabled(shouldEnable)
    }

    /// Reconcile per-user audio block events with the users currently in our
    /// channel: enable for newly-present remote users, disable + drop for users
    /// who left. The local user is never enabled, so our own voice is never mixed.
    func refreshPerUserAudioEventsLocked(instance: UnsafeMutableRawPointer) {
        perUserAudioNeedsRefresh = false
        guard outputAudioReady else { return }
        let myUserID = TT_GetMyUserID(instance)
        let myChannel = TT_GetMyChannelID(instance)
        // Per-user audio block events want a SINGLE stream type (unlike the muxed
        // user, which accepts an OR'd mask), so enable VOICE and MEDIA separately.
        let voice = UInt32(STREAMTYPE_VOICE.rawValue)
        let media = UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue)

        var desired = Set<Int32>()
        if myChannel > 0 {
            for user in channelUsersLocked(instance: instance, channelID: myChannel)
            where user.nUserID != myUserID && user.nUserID > 0 {
                desired.insert(user.nUserID)
            }
        }

        let toEnable = desired.subtracting(perUserAudioEnabled)
        let toDisable = perUserAudioEnabled.subtracting(desired)
        for userID in toEnable {
            TT_EnableAudioBlockEvent(instance, userID, voice, 1)
            TT_EnableAudioBlockEvent(instance, userID, media, 1)
        }
        for userID in toDisable {
            TT_EnableAudioBlockEvent(instance, userID, voice, 0)
            TT_EnableAudioBlockEvent(instance, userID, media, 0)
        }
        perUserAudioEnabled = desired
        // The pump removes departed users' mix sources itself, ordered after its
        // final block enqueue for them (so no ghost source reappears).
        audioBlockPump.setUsers(desired)
    }

    func channelUsersLocked(instance: UnsafeMutableRawPointer, channelID: Int32) -> [User] {
        var count: INT32 = 0
        guard TT_GetChannelUsers(instance, channelID, nil, &count) != 0, count > 0 else { return [] }
        var users = Array(repeating: User(), count: Int(count))
        guard TT_GetChannelUsers(instance, channelID, &users, &count) != 0 else { return [] }
        return Array(users.prefix(Int(count)))
    }

    /// Dispatch a CLIENTEVENT_USER_AUDIOBLOCK. Only the muxed stream (the
    /// pre-14.2 AEC reference fallback, whose consumer is confined to this
    /// queue) is acquired here. Per-user voice/media and our own media stream
    /// are drained by AudioBlockPump on its dedicated timer — acquiring them on
    /// this queue starved every mix source at once whenever a tick ran long
    /// (heavy publish in a crowded channel), making everyone sound choppy.
    func handleAudioBlockLocked(instance: UnsafeMutableRawPointer, source: Int32) {
        guard source == TT_MUXED_USERID else { return }
        guard let block = TT_AcquireUserAudioBlock(instance, UInt32(STREAMTYPE_VOICE.rawValue), TT_MUXED_USERID) else { return }
        if speakerTapCaptureStorage == nil,
           let aec = advancedMicrophoneEngine.echoCanceller,
           let rawAudio = block.pointee.lpRawAudio {
            let int16Ptr = rawAudio.assumingMemoryBound(to: Int16.self)
            aec.feedReference(int16Ptr, count: Int(block.pointee.nSamples), channels: Int(block.pointee.nChannels), sampleRate: Int(block.pointee.nSampleRate))
        }
        TT_ReleaseUserAudioBlock(instance, block)
    }

    /// Tear down the output render path (engine + all per-user / muxed events).
    func teardownOutputRenderLocked(instance: UnsafeMutableRawPointer?) {
        // Stop the block pump FIRST (synchronous): after this no SDK calls come
        // from its queue, so the events below can be disabled and the instance
        // torn down without racing an in-flight acquire.
        audioBlockPump.stop()
        outputRenderEngine.stop()
        if let instance {
            let voice = UInt32(STREAMTYPE_VOICE.rawValue)
            let media = UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue)
            for userID in perUserAudioEnabled {
                TT_EnableAudioBlockEvent(instance, userID, voice, 0)
                TT_EnableAudioBlockEvent(instance, userID, media, 0)
            }
            TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, voice, 0)
            if localMediaAudioEnabled {
                TT_EnableAudioBlockEvent(instance, TT_LOCAL_USERID, media, 0)
            }
        }
        perUserAudioEnabled.removeAll()
        localMediaAudioEnabled = false
        perUserAudioNeedsRefresh = false
    }

    func stopAdvancedMicrophoneInputLocked(instance: UnsafeMutableRawPointer, reason: String) {
        AudioLogger.log("stopAdvancedMicrophoneInput: reason=%@", reason)
        // Stop AEC reference source.
        if #available(macOS 14.2, *) {
            (speakerTapCaptureStorage as? SpeakerTapCapture)?.stop()
        }
        speakerTapCaptureStorage = nil
        // Disable the muxed AEC-reference event (playback uses per-user events,
        // managed separately by refreshPerUserAudioEventsLocked).
        TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, UInt32(STREAMTYPE_VOICE.rawValue), 0)
        advancedMicrophoneEngine.stop()
        outputRenderEngine.removeUser(localMonitorEngineKey)
        _ = TT_InsertAudioBlock(instance, nil)
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil
        appliedAdvancedInputAudio = nil
    }

    @available(macOS 14.2, *)
    private func startSpeakerTapForAEC() -> Bool {
        let tap = SpeakerTapCapture { [weak self] samples, frameCount, channels, sampleRate in
            guard let aec = self?.advancedMicrophoneEngine.echoCanceller else { return }
            aec.feedReference(samples, count: frameCount, channels: channels, sampleRate: sampleRate)
        }
        // Suppress device change notifications briefly — creating the aggregate device
        // triggers kAudioHardwarePropertyDevices which would restart the sound system.
        extendDeviceChangeSuppressionLocked(duration: 2.0)
        guard tap.start() else {
            AudioLogger.log("AEC: speaker tap failed to start")
            suppressDeviceChangeUntil = .distantPast
            return false
        }
        speakerTapCaptureStorage = tap
        return true
    }

    func ensureTeamTalkVirtualInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard teamTalkVirtualInputReady == false else {
            return
        }

        AudioLogger.log("ensureTeamTalkVirtualInputReady: opening virtual input device")
        guard TT_InitSoundInputDevice(instance, TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) != 0 else {
            AudioLogger.log("ensureTeamTalkVirtualInputReady: FAILED")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.inputStartFailed"))
        }

        teamTalkVirtualInputReady = true
        AudioLogger.log("ensureTeamTalkVirtualInputReady: virtual input ready")
    }

    /// Whether the microphone processing preferences (AEC/noise-suppression mode or
    /// channel preset) for the currently-active input device differ from what the
    /// running capture engine was built with. Returns false when no engine is live.
    func advancedMicrophoneProcessingChangedLocked(preferences: AppPreferences) -> Bool {
        guard inputAudioReady || isAnyMicrophoneEngineRunning,
              let applied = appliedAdvancedInputAudio,
              let deviceInfo = InputAudioDeviceResolver.resolveCurrentInputDevice(for: preferences.preferredInputDevice) else {
            return false
        }
        return effectiveMicrophoneProcessingPreferencesLocked(for: deviceInfo) != applied
    }

    func effectiveMicrophoneProcessingPreferencesLocked(
        for deviceInfo: InputAudioDeviceInfo
    ) -> AdvancedInputAudioPreferences {
        let effectivePreferences = preferencesStore.advancedInputAudio(for: deviceInfo.uid)
        return InputAudioDeviceResolver.normalizedPreferences(
            effectivePreferences,
            for: deviceInfo
        ).preferences
    }

    func currentAdvancedInputAudioPreferencesLocked(
        preferences: AppPreferences
    ) -> AdvancedInputAudioPreferences {
        let deviceID = InputAudioDeviceResolver.currentInputDeviceID(for: preferences.preferredInputDevice)
        return preferencesStore.advancedInputAudio(for: deviceID)
    }

    func insertAdvancedMicrophoneAudioChunkLocked(_ chunk: AdvancedMicrophoneAudioChunk) {
        guard let instance else {
            AudioCaptureDiagnostics.shared.recordInsertAttempt(
                sampleRate: chunk.sampleRate,
                accepted: false,
                gated: true
            )
            return
        }
        let inChannel = TT_GetMyChannelID(instance) > 0
        guard isEffectivelyTransmittingLocked, inChannel else {
            AudioCaptureDiagnostics.shared.recordInsertAttempt(
                sampleRate: chunk.sampleRate,
                accepted: false,
                gated: true
            )
            return
        }

        chunk.samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var audioBlock = AudioBlock()
            audioBlock.nStreamID = chunk.streamID
            audioBlock.nSampleRate = chunk.sampleRate
            audioBlock.nChannels = chunk.channels
            audioBlock.lpRawAudio = UnsafeMutableRawPointer(mutating: baseAddress)
            audioBlock.nSamples = chunk.sampleCount
            audioBlock.uSampleIndex = 0
            let accepted = TT_InsertAudioBlock(instance, &audioBlock) != 0
            AudioCaptureDiagnostics.shared.recordInsertAttempt(
                sampleRate: chunk.sampleRate,
                accepted: accepted,
                gated: false
            )
            if accepted == false {
                AudioLogger.log("TT_InsertAudioBlock: queue full, audio block dropped")
            }

            // Local monitor: feed the same processed mic audio we're transmitting
            // straight into the output mixer — local, no SDK round-trip. Drives both
            // "hear myself" and the connected-mode Audio-preferences mic preview
            // (one shared source key, so enabling both never doubles the audio).
            if hearMyselfEnabled || previewMonitorEnabled {
                let pcm = Array(UnsafeBufferPointer(start: baseAddress,
                                                    count: Int(chunk.sampleCount) * Int(chunk.channels)))
                outputRenderEngine.enqueueUser(
                    localMonitorEngineKey,
                    pcm: pcm,
                    frames: Int(chunk.sampleCount),
                    channels: Int(chunk.channels),
                    sampleRate: Double(chunk.sampleRate),
                    profile: .lowLatency
                )
            }
        }
    }

    func refreshAdvancedMicrophoneTargetIfNeededLocked(instance: UnsafeMutableRawPointer) {
        guard isAnyMicrophoneEngineRunning else {
            return
        }

        guard let currentTargetFormat = try? currentAdvancedMicrophoneTargetFormatLocked(instance: instance) else {
            return
        }

        guard currentTargetFormat != advancedMicrophoneTargetFormat else {
            return
        }

        do {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "refreshAdvancedMicrophoneTargetIfNeededLocked")
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
        } catch {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "refreshAdvancedMicrophoneTargetIfNeededLocked rollback")
            voiceTransmissionEnabled = false
            SoundPlayer.shared.play(.voxMeDisable)
            if let connectedRecord {
                publishSessionLocked(instance: instance, record: connectedRecord)
            }
        }
    }

    func currentAdvancedMicrophoneTargetFormatLocked(instance: UnsafeMutableRawPointer) throws -> AdvancedMicrophoneAudioTargetFormat {
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

    func sampleRate(forSpeexBandmode bandmode: Int32) -> Double {
        switch bandmode {
        case 1:
            return 16_000
        case 2:
            return 32_000
        default:
            return 8_000
        }
    }

    func applyOutputGainLocked(instance: UnsafeMutableRawPointer, gainDB: Double) {
        // Master output gain is applied by our render engine on the muxed stream.
        outputRenderEngine.setMasterGainDB(gainDB)
    }

    // MARK: - Jitter Control

    func applyJitterControlLocked(instance: UnsafeMutableRawPointer, userID: Int32) {
        let enabled = preferencesStore.preferences.adaptiveJitterBuffer
        var config = JitterConfig()
        config.nFixedDelayMSec = 0
        config.bUseAdativeDejitter = enabled ? 1 : 0
        config.nMaxAdaptiveDelayMSec = enabled ? 1000 : 0
        config.nActiveAdaptiveDelayMSec = 0
        _ = TT_SetUserJitterControl(instance, userID, StreamType(STREAMTYPE_VOICE.rawValue), &config)
    }

    // MARK: - Hear Myself

    func toggleHearMyself(completion: @escaping @MainActor (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            guard TT_GetMyUserID(instance) > 0 else { return }
            let newEnabled = !self.hearMyselfEnabled
            self.hearMyselfEnabled = newEnabled
            // LOCAL monitor — no SDK round-trip. When on, the mic-chunk path feeds
            // your own processed audio straight into the output mixer (see
            // insertAdvancedMicrophoneAudioChunkLocked), so you hear yourself with
            // only local buffering latency instead of mic→server→back. When off,
            // drop the monitor source.
            if newEnabled == false && self.previewMonitorEnabled == false {
                self.outputRenderEngine.removeUser(self.localMonitorEngineKey)
            }
            DispatchQueue.main.async { completion(newEnabled) }
        }
    }

    /// Connected-mode mic preview: monitor the live mic through the output engine
    /// (the input device is already owned by the live capture, so a second capture
    /// can't open). Shares the local-monitor source with hearMyself. Produces audio
    /// only while the mic is actually capturing/transmitting.
    func setPreviewMonitor(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.previewMonitorEnabled = enabled
            if enabled == false && self.hearMyselfEnabled == false {
                self.outputRenderEngine.removeUser(self.localMonitorEngineKey)
            }
        }
    }

    // MARK: - Recording

    func startMuxedRecording(folder: URL, format: AudioFileFormat, completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let channelID = TT_GetMyChannelID(instance)
            guard channelID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel")))) }
                return
            }
            var channel = Channel()
            guard TT_GetChannel(instance, channelID, &channel) != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel")))) }
                return
            }
            // Check CHANNEL_NO_RECORDING flag (unless user has USERRIGHT_RECORD_VOICE).
            if (channel.uChannelType & UInt32(CHANNEL_NO_RECORDING.rawValue)) != 0 {
                var account = UserAccount()
                let hasRecordRight = TT_GetMyUserAccount(instance, &account) != 0
                    && (account.uUserRights & UInt32(USERRIGHT_RECORD_VOICE.rawValue)) != 0
                if !hasRecordRight {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError(L10n.text("recording.error.channelNoRecording")))) }
                    return
                }
            }
            var audioCodec = channel.audiocodec
            let ext = Self.fileExtension(for: format)
            let timestamp = Self.recordingTimestamp()
            let fileName = "\(timestamp) Conference\(ext)"
            let filePath = folder.appendingPathComponent(fileName).path

            let streamTypes = StreamTypes(UInt32(STREAMTYPE_VOICE.rawValue) | UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue))
            let ok = filePath.withCString { cPath in
                TT_StartRecordingMuxedStreams(instance, streamTypes, &audioCodec, cPath, format)
            }
            guard ok != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError(L10n.text("recording.error.startFailed")))) }
                return
            }
            self.recordingMuxedActive = true
            self.recordingFolder = folder
            self.recordingFormat = format
            self.publishSessionLocked(instance: instance, record: record)
            DispatchQueue.main.async { completion(.success(fileName)) }
        }
    }

    func stopMuxedRecording(completion: (@MainActor () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                if let completion { DispatchQueue.main.async { completion() } }
                return
            }
            if self.recordingMuxedActive {
                _ = TT_StopRecordingMuxedAudioFile(instance)
                self.recordingMuxedActive = false
                if let record = self.connectedRecord {
                    self.publishSessionLocked(instance: instance, record: record)
                }
            }
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    func restartMuxedRecordingForChannelChange() {
        guard recordingMuxedActive, let folder = recordingFolder else { return }
        let format = recordingFormat
        stopMuxedRecording { [weak self] in
            self?.startMuxedRecording(folder: folder, format: format) { _ in }
        }
    }

    func startSeparateRecording(folder: URL, format: AudioFileFormat, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let folderPath = folder.path
            var users = self.fetchServerUsersLocked(instance: instance)
            var localUser = User()
            localUser.nUserID = TT_LOCAL_USERID
            users.append(localUser)
            for user in users {
                folderPath.withCString { cPath in
                    _ = TT_SetUserMediaStorageDirEx(instance, user.nUserID, cPath, nil, format, 1000)
                }
            }
            self.recordingSeparateActive = true
            self.recordingFolder = folder
            self.recordingFormat = format
            self.publishSessionLocked(instance: instance, record: record)
            DispatchQueue.main.async { completion(.success(())) }
        }
    }

    func stopSeparateRecording(completion: (@MainActor () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                if let completion { DispatchQueue.main.async { completion() } }
                return
            }
            if self.recordingSeparateActive {
                var users = self.fetchServerUsersLocked(instance: instance)
                var localUser = User()
                localUser.nUserID = TT_LOCAL_USERID
                users.append(localUser)
                let emptyPath = ""
                for user in users {
                    emptyPath.withCString { cPath in
                        _ = TT_SetUserMediaStorageDir(instance, user.nUserID, cPath, nil, self.recordingFormat)
                    }
                }
                self.recordingSeparateActive = false
                if let record = self.connectedRecord {
                    self.publishSessionLocked(instance: instance, record: record)
                }
            }
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }

    func setUserMediaStorageDirForNewUser(_ userID: Int32) {
        guard recordingSeparateActive, let folder = recordingFolder else { return }
        let folderPath = folder.path
        let format = recordingFormat
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            folderPath.withCString { cPath in
                _ = TT_SetUserMediaStorageDir(instance, userID, cPath, nil, format)
            }
        }
    }

    nonisolated static func fileExtension(for format: AudioFileFormat) -> String {
        switch format {
        case AFF_WAVE_FORMAT: return ".wav"
        case AFF_CHANNELCODEC_FORMAT: return ".ogg"
        case AFF_MP3_16KBIT_FORMAT, AFF_MP3_32KBIT_FORMAT, AFF_MP3_64KBIT_FORMAT,
             AFF_MP3_128KBIT_FORMAT, AFF_MP3_256KBIT_FORMAT, AFF_MP3_320KBIT_FORMAT:
            return ".mp3"
        default: return ".wav"
        }
    }

    nonisolated static func recordingTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    // MARK: - Master Mute

    func toggleMasterMute(completion: @escaping @MainActor (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self, self.instance != nil else { return }
            let newMuted = !self.masterMuted
            self.outputRenderEngine.setMuted(newMuted)
            self.masterMuted = newMuted
            SoundPlayer.shared.play(newMuted ? .muteAll : .unmuteAll)
            DispatchQueue.main.async {
                completion(newMuted)
            }
        }
    }

    nonisolated static func teamTalkVolume(for gainDB: Double) -> INT32 {
        let defaultVolume = Double(SOUND_VOLUME_DEFAULT.rawValue)
        let minVolume = Double(SOUND_VOLUME_MIN.rawValue)
        let maxVolume = Double(SOUND_VOLUME_MAX.rawValue)
        let linear = pow(10.0, gainDB / 20.0)
        let scaled = defaultVolume * linear
        let clamped = min(max(scaled.rounded(), minVolume), maxVolume)
        return INT32(clamped)
    }

    // Percent <-> SDK volume uses a GEOMETRIC (perceptually-uniform / dB-linear) curve:
    // 50% = SOUND_VOLUME_DEFAULT (unity), 100% = SOUND_VOLUME_MAX, 0% = silence. Each
    // percent is a constant ~0.6 dB step, so the slider sounds even across its range. A
    // plain linear-gain mapping made the top half brutal — at SOUND_VOLUME_MAX=32000
    // (32x), 50->51% jumped 1x->1.6x (~+4 dB) while 99->100% barely moved.
    nonisolated static func userVolumeFromPercent(_ percent: Double) -> INT32 {
        let pct = min(max(percent, 0), 100)
        if pct <= 0 { return INT32(SOUND_VOLUME_MIN.rawValue) }
        let defaultVolume = Double(SOUND_VOLUME_DEFAULT.rawValue)
        let maxVolume = Double(SOUND_VOLUME_MAX.rawValue)
        let ratio = pow(maxVolume / defaultVolume, (pct - 50) / 50)
        let raw = (defaultVolume * ratio).rounded()
        return INT32(min(max(raw, 1), maxVolume))
    }

    nonisolated static func percentFromUserVolume(_ volume: INT32) -> Int {
        let v = Double(volume)
        if v <= 0 { return 0 }
        let defaultVolume = Double(SOUND_VOLUME_DEFAULT.rawValue)
        let maxVolume = Double(SOUND_VOLUME_MAX.rawValue)
        let pct = 50 + 50 * (log(v / defaultVolume) / log(maxVolume / defaultVolume))
        return Int(min(max(pct.rounded(), 0), 100))
    }

    /// Stable per-server scope used to namespace stored per-user volumes (issue #24).
    /// Host:port identifies the physical server, so it is shared correctly across
    /// duplicate saved entries that point to the same server. Host is lowercased for
    /// case-insensitive matching.
    nonisolated static func serverVolumeScope(for record: SavedServerRecord) -> String {
        "\(record.host.lowercased()):\(record.tcpPort)"
    }

    nonisolated static func formatGainDB(_ value: Double) -> String {
        let rounded = AppPreferences.clampGainDB(value)
        if rounded > 0 {
            return String(format: "+%.0f dB", rounded)
        }
        return String(format: "%.0f dB", rounded)
    }

    // MARK: - Hardware change handling

    func extendDeviceChangeSuppressionLocked(duration: TimeInterval) {
        suppressDeviceChangeUntil = max(suppressDeviceChangeUntil, Date().addingTimeInterval(duration))
    }

    func processAudioHardwareChangeLocked(selector: UInt32) {
        if Date() < suppressDeviceChangeUntil {
            AudioLogger.log("processAudioHardwareChange: suppressed")
            return
        }

        let previous = lastAudioRoutingSnapshot
        cachedAudioDeviceCatalog = nil
        let current = makeAudioRoutingSnapshotLocked()

        let needsReinit = needsAudioReinitializationLocked(
            previous: previous,
            current: current,
            selector: selector
        )

        AudioLogger.log(
            "processAudioHardwareChange: selector=0x%08X needsReinit=%d in=%@ out=%@",
            selector,
            needsReinit ? 1 : 0,
            current.resolvedInputUID ?? "nil",
            current.preferredOutputPersistentID ?? "default"
        )

        lastAudioRoutingSnapshot = current

        guard needsReinit,
              let instance,
              connectedRecord != nil,
              outputAudioReady || inputAudioReady || isAnyMicrophoneEngineRunning else {
            AudioLogger.log("processAudioHardwareChange: catalog refresh only")
            return
        }

        AudioLogger.log("processAudioHardwareChange: restarting sound system for route change")
        restartSoundSystem { [weak self] result in
            guard let self else { return }
            if case .success = result,
               let instance = self.instance,
               let record = self.connectedRecord {
                self.publishSessionLocked(instance: instance, record: record)
            }
        }
    }

    func captureAudioRoutingSnapshotLocked() {
        lastAudioRoutingSnapshot = makeAudioRoutingSnapshotLocked()
    }

    func makeAudioRoutingSnapshotLocked() -> AudioRoutingSnapshot {
        let preferences = preferencesStore.preferences
        let resolvedInput = InputAudioDeviceResolver.resolveCurrentInputDevice(
            for: preferences.preferredInputDevice
        )
        let outputPreference = preferences.preferredOutputDevice
        let outputPersistentID = outputPreference.persistentID
        // Read ONLY the already-cached SDK device catalog — never trigger a load
        // here. On a large rig the SDK's TT_GetSoundDevices probe takes ~12 s; doing
        // it on the connect path (this snapshot runs during connect) is what made
        // connecting slow. If the catalog hasn't been loaded yet, assume the chosen
        // output is present — a later snapshot corrects it once the cache populates
        // (the device picker, or processAudioHardwareChangeLocked on a real change).
        let outputInCatalog: Bool
        if let catalog = cachedAudioDeviceCatalog {
            if let outputPersistentID, outputPersistentID.isEmpty == false {
                outputInCatalog = catalog.outputDevices.contains { $0.persistentID == outputPersistentID }
            } else {
                outputInCatalog = catalog.outputDevices.isEmpty == false
            }
        } else {
            outputInCatalog = true
        }

        return AudioRoutingSnapshot(
            resolvedInputUID: resolvedInput?.uid,
            defaultInputUID: InputAudioDeviceResolver.defaultInputDeviceUID(),
            defaultOutputUID: InputAudioDeviceResolver.defaultOutputDeviceUID(),
            preferredOutputPersistentID: outputPersistentID,
            outputPersistentIDInCatalog: outputInCatalog,
            activeInputSampleRate: resolvedInput?.nominalSampleRate ?? 0
        )
    }

    func needsAudioReinitializationLocked(
        previous: AudioRoutingSnapshot?,
        current: AudioRoutingSnapshot,
        selector: UInt32
    ) -> Bool {
        guard let previous else {
            return false
        }

        let inputPreference = preferencesStore.preferences.preferredInputDevice
        let outputPreference = preferencesStore.preferences.preferredOutputDevice

        if inputPreference.usesSystemDefault,
           previous.defaultInputUID != current.defaultInputUID {
            return true
        }

        if outputPreference.usesSystemDefault,
           previous.defaultOutputUID != current.defaultOutputUID {
            return true
        }

        // Explicit input preference: only react when the chosen device disappears,
        // not when unrelated devices (e.g. Continuity) are added to the global list.
        if inputPreference.usesSystemDefault == false,
           let persistentID = inputPreference.persistentID,
           persistentID.isEmpty == false {
            let stillAvailable = InputAudioDeviceResolver.availableInputDevices()
                .contains { $0.uid == persistentID }
            if previous.resolvedInputUID != nil, stillAvailable == false {
                return true
            }
        }

        if outputPreference.usesSystemDefault == false,
           let persistentID = outputPreference.persistentID,
           persistentID.isEmpty == false,
           previous.outputPersistentIDInCatalog != current.outputPersistentIDInCatalog {
            return true
        }

        if selector == kAudioDevicePropertyNominalSampleRate,
           previous.resolvedInputUID == current.resolvedInputUID,
           previous.activeInputSampleRate != current.activeInputSampleRate {
            return true
        }

        return false
    }

}
