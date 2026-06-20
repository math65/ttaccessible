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
            self?.pushToTalkPressed = pressed
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
                    // Reopens the virtual output + muxed event; the render engine
                    // restarts on the next muxed block (gain/mute reapplied inside).
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

            guard outputChanged || inputChanged else {
                self.appliedOutputPreference = preferences.preferredOutputDevice
                self.appliedInputPreference = preferences.preferredInputDevice
                DispatchQueue.main.async { completion(.success(())) }
                return
            }

            do {
                try self.reinitializeAudioDevicesLocked(
                    instance: instance,
                    preferences: preferences,
                    reinitInput: inputChanged,
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
                echoCancellationEnabled: aecEnabled
            )
            try ensureTeamTalkVirtualInputReadyLocked(instance: instance)
            try ensureDirectOutputAudioReadyLocked(instance: instance)
            _ = try advancedMicrophoneEngine.start(configuration: configuration)
            advancedMicrophoneTargetFormat = targetFormat
            inputAudioReady = true
            appliedInputPreference = preferencesStore.preferences.preferredInputDevice
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
        if voiceTransmissionEnabled {
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
        // Enable per-user audio block events for whoever is already in our channel.
        refreshPerUserAudioEventsLocked(instance: instance)
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
    /// voice stream).
    func outputMediaSourceKey(_ userID: Int32) -> Int32 { userID | 0x4000_0000 }

    /// Reserved mixer key for the local "hear myself" monitor (negative, so it
    /// never collides with real user IDs or media keys, both positive).
    var localMonitorEngineKey: Int32 { -1 }

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
            outputRenderEngine.removeUser(userID)
            outputRenderEngine.removeUser(outputMediaSourceKey(userID))
        }
        perUserAudioEnabled = desired
    }

    func channelUsersLocked(instance: UnsafeMutableRawPointer, channelID: Int32) -> [User] {
        var count: INT32 = 0
        guard TT_GetChannelUsers(instance, channelID, nil, &count) != 0, count > 0 else { return [] }
        var users = Array(repeating: User(), count: Int(count))
        guard TT_GetChannelUsers(instance, channelID, &users, &count) != 0 else { return [] }
        return Array(users.prefix(Int(count)))
    }

    /// Dispatch a CLIENTEVENT_USER_AUDIOBLOCK. A remote user's voice/media goes to
    /// the mixer for playback; the muxed stream (only enabled as the pre-14.2 AEC
    /// fallback) feeds the echo canceller's far-end reference.
    func handleAudioBlockLocked(instance: UnsafeMutableRawPointer, source: Int32) {
        if source == TT_MUXED_USERID {
            guard let block = TT_AcquireUserAudioBlock(instance, UInt32(STREAMTYPE_VOICE.rawValue), TT_MUXED_USERID) else { return }
            if speakerTapCaptureStorage == nil,
               let aec = advancedMicrophoneEngine.echoCanceller,
               let rawAudio = block.pointee.lpRawAudio {
                let int16Ptr = rawAudio.assumingMemoryBound(to: Int16.self)
                aec.feedReference(int16Ptr, count: Int(block.pointee.nSamples), channels: Int(block.pointee.nChannels), sampleRate: Int(block.pointee.nSampleRate))
            }
            TT_ReleaseUserAudioBlock(instance, block)
            return
        }

        let myUserID = TT_GetMyUserID(instance)
        guard source > 0, source != myUserID else { return }
        enqueueUserAudioBlockLocked(instance: instance, userID: source, streamType: STREAMTYPE_VOICE, engineKey: source)
        enqueueUserAudioBlockLocked(instance: instance, userID: source, streamType: STREAMTYPE_MEDIAFILE_AUDIO, engineKey: outputMediaSourceKey(source))
    }

    private func enqueueUserAudioBlockLocked(instance: UnsafeMutableRawPointer, userID: Int32, streamType: StreamType, engineKey: Int32) {
        guard let block = TT_AcquireUserAudioBlock(instance, UInt32(streamType.rawValue), userID) else { return }
        defer { TT_ReleaseUserAudioBlock(instance, block) }
        let frames = Int(block.pointee.nSamples)
        let channels = Int(block.pointee.nChannels)
        let sampleRate = Int(block.pointee.nSampleRate)
        guard frames > 0, channels > 0, sampleRate > 0, let rawAudio = block.pointee.lpRawAudio else { return }
        // Copy the SDK PCM out before the block is released — the engine consumes it
        // asynchronously on its own queue.
        let samplePtr = rawAudio.assumingMemoryBound(to: Int16.self)
        let pcm = Array(UnsafeBufferPointer(start: samplePtr, count: frames * channels))
        outputRenderEngine.enqueueUser(
            engineKey,
            pcm: pcm,
            frames: frames, channels: channels, sampleRate: Double(sampleRate)
        )
    }

    /// Tear down the output render path (engine + all per-user / muxed events).
    func teardownOutputRenderLocked(instance: UnsafeMutableRawPointer?) {
        outputRenderEngine.stop()
        if let instance {
            let voice = UInt32(STREAMTYPE_VOICE.rawValue)
            let media = UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue)
            for userID in perUserAudioEnabled {
                TT_EnableAudioBlockEvent(instance, userID, voice, 0)
                TT_EnableAudioBlockEvent(instance, userID, media, 0)
            }
            TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, voice, 0)
        }
        perUserAudioEnabled.removeAll()
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
        // PTT only gates transmission when a global shortcut is actually
        // configured. Without a shortcut, pushToTalkPressed could never become
        // true and the mic would be silently muted forever — fall back to
        // always-on so the user is at least heard.
        let pttEnforced = preferencesStore.preferences.microphoneMode == .pushToTalk
            && (pushToTalkShortcutResolver?() ?? false)
        let allowTransmission = !pttEnforced || pushToTalkPressed
        guard voiceTransmissionEnabled, inChannel, allowTransmission else {
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
                    sampleRate: Double(chunk.sampleRate)
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
