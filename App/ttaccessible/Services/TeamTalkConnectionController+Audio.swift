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

    @MainActor
    func availableAudioDevices() -> AudioDeviceCatalog {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return availableAudioDevicesLocked(forceRefresh: false)
        }
        return queue.sync {
            availableAudioDevicesLocked(forceRefresh: false)
        }
    }

    @MainActor
    func refreshAvailableAudioDevices() -> AudioDeviceCatalog {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = nil
            return availableAudioDevicesLocked(forceRefresh: true)
        }
        return queue.sync {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = nil
            return availableAudioDevicesLocked(forceRefresh: true)
        }
    }

    func invalidateAudioDeviceCache() {
        queue.async { [weak self] in
            self?.cachedSoundDevices = []
            self?.cachedAudioDeviceCatalog = nil
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
                _ = TT_CloseSoundOutputDevice(instance)
                self.outputAudioReady = false
            }

            let ok = TT_RestartSoundSystem()
            self.cachedSoundDevices = []
            self.cachedAudioDeviceCatalog = nil

            AudioLogger.log("restartSoundSystem: TT_RestartSoundSystem returned %d", ok)

            guard ok != 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("preferences.audio.refreshDevices.error"))))
                }
                return
            }

            if hadOutput, let instance = self.instance {
                do {
                    try self.ensureDirectOutputAudioReadyLocked(instance: instance)
                    if self.masterMuted {
                        _ = TT_SetSoundOutputMute(instance, 1)
                    }
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
                    SoundPlayer.shared.play(.voxMeDisable)
                    if let connectedRecord = self.connectedRecord {
                        self.publishSessionLocked(instance: instance, record: connectedRecord)
                    }
                }
            }

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

            do {
                try self.reinitializeAudioDevicesLocked(instance: instance, preferences: preferences)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
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
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            guard TT_GetMyChannelID(instance) > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.notInChannel"))))
                }
                return
            }

            do {
                try self.ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                self.voiceTransmissionEnabled = true
                SoundPlayer.shared.play(.voxMeEnable)
                self.publishSessionLocked(instance: instance, record: record)
                let preferencesStore = self.preferencesStore
                DispatchQueue.main.async {
                    preferencesStore.updateLastVoiceTransmissionEnabled(true)
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func deactivateVoiceTransmission(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
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
                completion(.success(()))
            }
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

            // Monitor sample rate changes on the active input device.
            let activeDeviceUID = deviceInfo.uid
            DispatchQueue.main.async { [weak self] in
                let deviceID = InputAudioDeviceResolver.audioDeviceID(forUID: activeDeviceUID)
                self?.audioDeviceChangeMonitor?.monitorSampleRate(forDeviceID: deviceID)
            }

            // Enable muxed audio block events for AEC reference signal.
            // Use the Ex variant to have the SDK resample the reference to the capture sample rate,
            // avoiding manual linear interpolation in EchoCanceller.feedReference().
            if aecEnabled {
                let captureSampleRate = advancedMicrophoneEngine.effectiveSampleRate ?? Double(targetFormat.sampleRate)
                var audioFormat = AudioFormat(
                    nAudioFmt: AFF_WAVE_FORMAT,
                    nSampleRate: Int32(captureSampleRate),
                    nChannels: Int32(max(targetFormat.channels, 1))
                )
                TT_EnableAudioBlockEventEx(instance, TT_MUXED_USERID, UInt32(STREAMTYPE_VOICE.rawValue), &audioFormat, 1)
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
        preferences: AppPreferences
    ) throws {
        AudioLogger.log("reinitializeAudioDevicesLocked: begin")
        let wasVoiceTransmissionEnabled = voiceTransmissionEnabled
        let wasInputAudioReady = inputAudioReady
        if wasVoiceTransmissionEnabled || wasInputAudioReady || isAnyMicrophoneEngineRunning {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "reinitializeAudioDevicesLocked")
        }
        voiceTransmissionEnabled = false
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil

        if teamTalkVirtualInputReady {
            _ = TT_CloseSoundInputDevice(instance)
            teamTalkVirtualInputReady = false
        }

        if outputAudioReady {
            _ = TT_CloseSoundOutputDevice(instance)
            outputAudioReady = false
        }

        try ensureDirectOutputAudioReadyLocked(instance: instance)

        if wasVoiceTransmissionEnabled || wasInputAudioReady {
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
        }

        if wasVoiceTransmissionEnabled {
            voiceTransmissionEnabled = true
        }
    }

    func makeAudioStatusText() -> String {
        var status: String
        if voiceTransmissionEnabled {
            status = L10n.text("connectedServer.audio.status.microphoneActive")
        } else if inputAudioReady {
            status = L10n.text("connectedServer.audio.status.inputReady")
        } else if outputAudioReady {
            status = L10n.text("connectedServer.audio.status.outputReady")
        } else {
            status = L10n.text("connectedServer.audio.status.unavailable")
        }
        if recordingMuxedActive || recordingSeparateActive {
            status += " — " + L10n.text("connectedServer.audio.status.recording")
        }
        return status
    }

    func loadSoundDevicesLocked(forceRefresh: Bool) -> [SoundDevice] {
        if forceRefresh == false, cachedSoundDevices.isEmpty == false {
            return cachedSoundDevices
        }

        var count: INT32 = 0
        guard TT_GetSoundDevices(nil, &count) != 0, count > 0 else {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = .empty
            return []
        }

        var devices = Array(repeating: SoundDevice(), count: Int(count))
        guard TT_GetSoundDevices(&devices, &count) != 0 else {
            cachedSoundDevices = []
            cachedAudioDeviceCatalog = .empty
            return []
        }

        cachedSoundDevices = Array(devices.prefix(Int(count)))
        AudioLogger.log("loadSoundDevicesLocked: loaded %d devices", cachedSoundDevices.count)
        return cachedSoundDevices
    }

    func availableAudioDevicesLocked(forceRefresh: Bool) -> AudioDeviceCatalog {
        if forceRefresh == false, let cachedAudioDeviceCatalog {
            return cachedAudioDeviceCatalog
        }

        let activeDevices = loadSoundDevicesLocked(forceRefresh: forceRefresh)
            .filter { ttString(from: $0.szDeviceName).hasPrefix("CADefaultDeviceAggregate") == false }
        let inputDevices = activeDevices
            .filter { $0.nMaxInputChannels > 0 && $0.nDeviceID != TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL }
            .map(makeAudioDeviceOption(from:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let outputDevices = activeDevices
            .filter { $0.nMaxOutputChannels > 0 && $0.nDeviceID != TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL }
            .map(makeAudioDeviceOption(from:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let catalog = AudioDeviceCatalog(inputDevices: inputDevices, outputDevices: outputDevices)
        cachedAudioDeviceCatalog = catalog
        return catalog
    }

    func makeAudioDeviceOption(from device: SoundDevice) -> AudioDeviceOption {
        let persistentID = ttString(from: device.szDeviceID).isEmpty
            ? "legacy:\(device.nDeviceID)"
            : ttString(from: device.szDeviceID)
        return AudioDeviceOption(
            id: persistentID,
            persistentID: persistentID,
            displayName: ttString(from: device.szDeviceName)
        )
    }

    func ensureDirectOutputAudioReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard outputAudioReady == false else {
            return
        }

        let outputDeviceID = try selectedOutputDeviceIDLocked()
        AudioLogger.log("ensureDirectOutputAudioReady: opening output device ID=%d", outputDeviceID)
        guard TT_InitSoundOutputDevice(instance, outputDeviceID) != 0 else {
            AudioLogger.log("ensureDirectOutputAudioReady: FAILED to open output device")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        outputAudioReady = true
        applyOutputGainLocked(instance: instance, gainDB: preferencesStore.preferences.outputGainDB)
        AudioLogger.log("ensureDirectOutputAudioReady: output ready")
    }

    func stopAdvancedMicrophoneInputLocked(instance: UnsafeMutableRawPointer, reason: String) {
        AudioLogger.log("stopAdvancedMicrophoneInput: reason=%@", reason)
        // Disable muxed audio block events (AEC reference).
        TT_EnableAudioBlockEventEx(instance, TT_MUXED_USERID, UInt32(STREAMTYPE_VOICE.rawValue), nil, 0)
        advancedMicrophoneEngine.stop()
        _ = TT_InsertAudioBlock(instance, nil)
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil
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
        guard voiceTransmissionEnabled,
              let instance,
              TT_GetMyChannelID(instance) > 0 else {
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
            if TT_InsertAudioBlock(instance, &audioBlock) == 0 {
                AudioLogger.log("TT_InsertAudioBlock: queue full, audio block dropped")
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

    func selectedOutputDeviceIDLocked() throws -> INT32 {
        try selectedDeviceIDLocked(
            preference: preferencesStore.preferences.preferredOutputDevice,
            availableDevices: availableAudioDevicesLocked(forceRefresh: false).outputDevices,
            direction: .output
        )
    }

    func selectedInputDeviceIDLocked() throws -> INT32 {
        try selectedDeviceIDLocked(
            preference: preferencesStore.preferences.preferredInputDevice,
            availableDevices: availableAudioDevicesLocked(forceRefresh: false).inputDevices,
            direction: .input
        )
    }

    func applyOutputGainLocked(instance: UnsafeMutableRawPointer, gainDB: Double) {
        let volume = Self.teamTalkVolume(for: gainDB)
        _ = TT_SetSoundOutputVolume(instance, volume)
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
            let myUserID = TT_GetMyUserID(instance)
            guard myUserID > 0 else { return }
            let newEnabled = !self.hearMyselfEnabled
            let sub = Subscriptions(SUBSCRIBE_VOICE.rawValue)
            if newEnabled {
                _ = TT_DoSubscribe(instance, myUserID, sub)
            } else {
                _ = TT_DoUnsubscribe(instance, myUserID, sub)
            }
            self.hearMyselfEnabled = newEnabled
            DispatchQueue.main.async { completion(newEnabled) }
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
            guard let self, let instance = self.instance else { return }
            let newMuted = !self.masterMuted
            _ = TT_SetSoundOutputMute(instance, newMuted ? 1 : 0)
            self.masterMuted = newMuted
            SoundPlayer.shared.play(newMuted ? .muteAll : .unmuteAll)
            DispatchQueue.main.async {
                completion(newMuted)
            }
        }
    }

    func selectedDeviceIDLocked(
        preference: AudioDevicePreference,
        availableDevices: [AudioDeviceOption],
        direction: AudioDirection
    ) throws -> INT32 {
        var defaultInputDeviceID: INT32 = 0
        var defaultOutputDeviceID: INT32 = 0
        guard TT_GetDefaultSoundDevices(&defaultInputDeviceID, &defaultOutputDeviceID) != 0 else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.defaultDevicesUnavailable"))
        }

        guard let persistentID = preference.persistentID, persistentID.isEmpty == false else {
            return direction == .input ? defaultInputDeviceID : defaultOutputDeviceID
        }

        guard availableDevices.contains(where: { $0.persistentID == persistentID }) else {
            return direction == .input ? defaultInputDeviceID : defaultOutputDeviceID
        }

        for device in loadSoundDevicesLocked(forceRefresh: false) {
            let candidatePersistentID = ttString(from: device.szDeviceID).isEmpty
                ? "legacy:\(device.nDeviceID)"
                : ttString(from: device.szDeviceID)
            guard candidatePersistentID == persistentID else {
                continue
            }
            if direction == .input, device.nMaxInputChannels > 0 {
                return device.nDeviceID
            }
            if direction == .output, device.nMaxOutputChannels > 0 {
                return device.nDeviceID
            }
        }

        return direction == .input ? defaultInputDeviceID : defaultOutputDeviceID
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

    nonisolated static func userVolumeFromPercent(_ percent: Double) -> INT32 {
        let raw = 82.832 * exp(0.0508 * percent) - 50
        let clamped = min(max(raw.rounded(), Double(SOUND_VOLUME_MIN.rawValue)), Double(SOUND_VOLUME_MAX.rawValue))
        return INT32(clamped)
    }

    nonisolated static func percentFromUserVolume(_ volume: INT32) -> Int {
        let v = Double(volume)
        let percent = log((v + 50) / 82.832) / 0.0508
        return Int(min(max(percent.rounded(), 0), 100))
    }

    nonisolated static func formatGainDB(_ value: Double) -> String {
        let rounded = AppPreferences.clampGainDB(value)
        if rounded > 0 {
            return String(format: "+%.0f dB", rounded)
        }
        return String(format: "%.0f dB", rounded)
    }

}
