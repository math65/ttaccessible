//
//  TeamTalkConnectionController+Audio.swift
//  ttaccessible
//
//  Created by Codex on 30/03/2026.
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
        queue.sync {
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

            DispatchQueue.main.async {
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

        let effectivePreferences = effectiveMicrophoneProcessingPreferencesLocked(for: deviceInfo)
        let targetFormat = try currentAdvancedMicrophoneTargetFormatLocked(instance: instance)

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

            // Enable muxed audio block events for AEC reference signal.
            if aecEnabled {
                TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, UInt32(STREAMTYPE_VOICE.rawValue), 1)
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
        let wasVoiceTransmissionEnabled = voiceTransmissionEnabled
        let wasInputAudioReady = inputAudioReady
        if wasVoiceTransmissionEnabled || wasInputAudioReady || isAnyMicrophoneEngineRunning {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "reinitializeAudioDevicesLocked")
        }
        voiceTransmissionEnabled = false
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil

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
        if voiceTransmissionEnabled {
            return L10n.text("connectedServer.audio.status.microphoneActive")
        }
        if inputAudioReady {
            return L10n.text("connectedServer.audio.status.inputReady")
        }
        if outputAudioReady {
            return L10n.text("connectedServer.audio.status.outputReady")
        }
        return L10n.text("connectedServer.audio.status.unavailable")
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
        return cachedSoundDevices
    }

    func availableAudioDevicesLocked(forceRefresh: Bool) -> AudioDeviceCatalog {
        if forceRefresh == false, let cachedAudioDeviceCatalog {
            return cachedAudioDeviceCatalog
        }

        let activeDevices = loadSoundDevicesLocked(forceRefresh: forceRefresh)
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
        guard TT_InitSoundOutputDevice(instance, outputDeviceID) != 0 else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        outputAudioReady = true
        applyOutputGainLocked(instance: instance, gainDB: preferencesStore.preferences.outputGainDB)
    }

    func stopAdvancedMicrophoneInputLocked(instance: UnsafeMutableRawPointer, reason: String) {
        // Disable muxed audio block events (AEC reference).
        TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, UInt32(STREAMTYPE_VOICE.rawValue), 0)
        advancedMicrophoneEngine.stop()
        _ = TT_InsertAudioBlock(instance, nil)
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil
    }

    func ensureTeamTalkVirtualInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard teamTalkVirtualInputReady == false else {
            return
        }

        guard TT_InitSoundInputDevice(instance, TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) != 0 else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.inputStartFailed"))
        }

        teamTalkVirtualInputReady = true
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

        chunk.data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var audioBlock = AudioBlock()
            audioBlock.nStreamID = chunk.streamID
            audioBlock.nSampleRate = chunk.sampleRate
            audioBlock.nChannels = chunk.channels
            audioBlock.lpRawAudio = UnsafeMutableRawPointer(mutating: baseAddress)
            audioBlock.nSamples = chunk.sampleCount
            audioBlock.uSampleIndex = 0
            _ = TT_InsertAudioBlock(instance, &audioBlock)
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

    nonisolated static func formatGainDB(_ value: Double) -> String {
        let rounded = AppPreferences.clampGainDB(value)
        if rounded > 0 {
            return String(format: "+%.0f dB", rounded)
        }
        return String(format: "%.0f dB", rounded)
    }

}
