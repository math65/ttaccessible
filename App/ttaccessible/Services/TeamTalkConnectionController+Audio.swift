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

    func describe(_ preset: InputChannelPreset) -> String {
        switch preset {
        case .auto:
            return "auto"
        case .mono(let channel):
            return "mono:\(channel)"
        case .stereoPair(let first, let second):
            return "stereo:\(first)/\(second)"
        case .monoMix(let first, let second):
            return "monoMix:\(first)+\(second)"
        }
    }

    func describeLimiter(_ preferences: AdvancedInputAudioPreferences) -> String {
        guard preferences.limiterEnabled else {
            return "off"
        }

        switch preferences.limiterMode {
        case .preset:
            return "preset:\(preferences.limiterPreset.rawValue)"
        case .manual:
            return "manual:\(preferences.effectiveLimiterThresholdDB)dB/\(Int(preferences.effectiveLimiterReleaseMilliseconds.rounded()))ms"
        }
    }

    func describeDynamicProcessor(_ preferences: AdvancedInputAudioPreferences) -> String {
        guard preferences.dynamicProcessorEnabled else {
            return "off"
        }
        switch preferences.dynamicProcessorMode {
        case .gate:
            return "gate:\(Int(preferences.gate.thresholdDB.rounded()))dB/\(Int(preferences.gate.attackMilliseconds.rounded()))ms/\(Int(preferences.gate.holdMilliseconds.rounded()))ms/\(Int(preferences.gate.releaseMilliseconds.rounded()))ms"
        case .expander:
            return "expander:\(Int(preferences.expander.thresholdDB.rounded()))dB/\(preferences.expander.ratio):1/\(Int(preferences.expander.attackMilliseconds.rounded()))ms/\(Int(preferences.expander.releaseMilliseconds.rounded()))ms"
        }
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
                let advanced = self.currentAdvancedInputAudioPreferencesLocked(preferences: preferences)
                self.logAudio(
                    "Audio re-apply requested. input=\(preferences.preferredInputDevice.displayName ?? "system") output=\(preferences.preferredOutputDevice.displayName ?? "system") advanced=\(advanced.isEnabled) preset=\(self.describe(advanced.preset)) dynamic=\(self.describeDynamicProcessor(advanced)) limiter=\(self.describeLimiter(advanced))"
                )
                try self.reinitializeAudioDevicesLocked(instance: instance, preferences: preferences)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.logAudio("Audio re-apply failed: \(error.localizedDescription)")
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
            self.appleVoiceChatEngine.updateInputGainDB(clamped)
            self.logAudio("Input gain applied. value=\(Self.formatGainDB(clamped))")
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
            self.appleVoiceChatEngine.updateOutputGainDB(clamped)
            self.logAudio("Output gain applied. value=\(Self.formatGainDB(clamped))")
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
                self.logAudio("Microphone activation requested. channel=\(TT_GetMyChannelID(instance)) engineRunning=\(self.isAnyMicrophoneEngineRunning) inputReady=\(self.inputAudioReady) virtualReady=\(self.teamTalkVirtualInputReady)")
                try self.ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
                self.voiceTransmissionEnabled = true
                SoundPlayer.shared.play(.voxMeEnable)
                self.logAudio("Microphone enabled. engineRunning=\(self.isAnyMicrophoneEngineRunning) virtualReady=\(self.teamTalkVirtualInputReady)")
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.logAudio("Microphone activation failed: \(error.localizedDescription)")
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
            self.logAudio("Microphone disabled.")
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
                limiterThresholdDB: effectivePreferences.effectiveLimiterThresholdDB,
                limiterReleaseMilliseconds: effectivePreferences.effectiveLimiterReleaseMilliseconds,
                targetFormat: targetFormat
            )
            logAudio(
                "Starting Apple capture. device=\(deviceInfo.name) channels=\(deviceInfo.inputChannels) sampleRate=\(deviceInfo.nominalSampleRate) aec=\(effectivePreferences.echoCancellationEnabled) preset=\(describe(effectivePreferences.preset)) dynamic=\(describeDynamicProcessor(effectivePreferences)) limiter=\(describeLimiter(effectivePreferences)) targetRate=\(targetFormat.sampleRate) targetChannels=\(targetFormat.channels) txInterval=\(targetFormat.txIntervalMSec)"
            )
            try ensureTeamTalkVirtualInputReadyLocked(instance: instance)
            if effectivePreferences.echoCancellationEnabled {
                let outputUID = try selectedOutputDeviceUIDLocked()
                let voiceChatConfig = AppleVoiceChatAudioConfiguration(
                    microphone: configuration,
                    outputDeviceUID: outputUID,
                    outputGainDB: preferencesStore.preferences.outputGainDB
                )
                if outputAudioReady {
                    _ = TT_CloseSoundOutputDevice(instance)
                    outputAudioReady = false
                    logAudio("TeamTalk output closed for AEC handover.")
                }
                let result = try appleVoiceChatEngine.start(configuration: voiceChatConfig)
                var audioFmt = AudioFormat()
                audioFmt.nAudioFmt = AFF_WAVE_FORMAT
                audioFmt.nSampleRate = result.playbackFormat.sampleRate
                audioFmt.nChannels = result.playbackFormat.channels
                withUnsafePointer(to: audioFmt) { fmtPtr in
                    _ = TT_EnableAudioBlockEventEx(instance, TT_MUXED_USERID, STREAMTYPE_VOICE.rawValue, fmtPtr, 1)
                }
                logAudio(
                    "AppleVoiceChat engine started. streamID=\(result.streamID) playbackRate=\(result.playbackFormat.sampleRate) playbackChannels=\(result.playbackFormat.channels)"
                )
            } else {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
                _ = try advancedMicrophoneEngine.start(configuration: configuration)
                logAudio("Microphone capture started.")
            }
            advancedMicrophoneTargetFormat = targetFormat
            inputAudioReady = true
            insertedAudioChunkCount = 0
            failedAudioChunkInsertCount = 0
            lastLoggedAudioInputQueueBucket = nil
        } catch {
            if teamTalkVirtualInputReady {
                _ = TT_CloseSoundInputDevice(instance)
                teamTalkVirtualInputReady = false
                logAudio("TeamTalk virtual input closed after Apple capture start failure.")
            }
            inputAudioReady = false
            advancedMicrophoneTargetFormat = nil
            do {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
            } catch {
                logAudio("Failed to restore TeamTalk output after microphone error: \(error.localizedDescription)")
            }
            logAudio("Microphone start failed: \(error.localizedDescription)")
            throw error
        }
    }

    func reinitializeAudioDevicesLocked(
        instance: UnsafeMutableRawPointer,
        preferences: AppPreferences
    ) throws {
        logAudio("Audio reinitialization. wasVoice=\(voiceTransmissionEnabled) wasInput=\(inputAudioReady) wasOutput=\(outputAudioReady)")
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
            logAudio("TeamTalk output init failed. deviceID=\(outputDeviceID)")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        outputAudioReady = true
        applyOutputGainLocked(instance: instance, gainDB: preferencesStore.preferences.outputGainDB)
        logAudio("TeamTalk direct output initialized. deviceID=\(outputDeviceID)")
    }

    func stopAdvancedMicrophoneInputLocked(instance: UnsafeMutableRawPointer, reason: String) {
        logAudio("Stopping Apple capture. reason=\(reason) virtualReady=\(teamTalkVirtualInputReady) inserted=\(insertedAudioChunkCount) failed=\(failedAudioChunkInsertCount)")
        if appleVoiceChatEngine.isRunning {
            logAudio("Microphone teardown: disabling muxed audio block events...")
            _ = TT_EnableAudioBlockEvent(instance, TT_MUXED_USERID, STREAMTYPE_VOICE.rawValue, 0)
            logAudio("Microphone teardown: stopping AppleVoiceChat engine...")
            appleVoiceChatEngine.stop()
            logAudio("Microphone teardown: AppleVoiceChat engine stopped.")
        } else {
            logAudio("Microphone teardown: stopping Apple engine...")
            advancedMicrophoneEngine.stop()
            logAudio("Microphone teardown: Apple engine stopped.")
        }
        let didEndRawInput = TT_InsertAudioBlock(instance, nil) != 0
        logAudio("Microphone teardown: TT_InsertAudioBlock(nil)=\(didEndRawInput)")
        inputAudioReady = false
        advancedMicrophoneTargetFormat = nil
        logAudio("Microphone teardown: local state reset.")
        if outputAudioReady == false {
            do {
                try ensureDirectOutputAudioReadyLocked(instance: instance)
                logAudio("TeamTalk direct output restored after AEC stop.")
            } catch {
                logAudio("Failed to restore TeamTalk output after AEC stop: \(error.localizedDescription)")
            }
        }
    }

    func ensureTeamTalkVirtualInputReadyLocked(instance: UnsafeMutableRawPointer) throws {
        guard teamTalkVirtualInputReady == false else {
            return
        }

        guard TT_InitSoundInputDevice(instance, TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) != 0 else {
            logAudio("TeamTalk virtual input init failed.")
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.inputStartFailed"))
        }

        teamTalkVirtualInputReady = true
        logAudio("TeamTalk virtual input initialized.")
    }

    func effectiveMicrophoneProcessingPreferencesLocked(
        for deviceInfo: InputAudioDeviceInfo
    ) -> AdvancedInputAudioPreferences {
        var effectivePreferences = preferencesStore.advancedInputAudio(for: deviceInfo.uid)
        if effectivePreferences.isEnabled == false {
            effectivePreferences.preset = .auto
            effectivePreferences.dynamicProcessorEnabled = false
            effectivePreferences.limiterEnabled = false
        }

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

    func handleUserAudioBlockEventLocked(
        _ message: TTMessage,
        instance: UnsafeMutableRawPointer
    ) {
        guard appleVoiceChatEngine.isRunning else {
            return
        }
        let userID = message.nSource
        guard let block = TT_AcquireUserAudioBlock(instance, STREAMTYPE_VOICE.rawValue, userID) else {
            return
        }
        defer { _ = TT_ReleaseUserAudioBlock(instance, block) }
        let sampleCount = block.pointee.nSamples
        let sampleRate = block.pointee.nSampleRate
        let channels = block.pointee.nChannels
        let streamID = block.pointee.nStreamID
        guard sampleCount > 0, channels > 0, let rawAudio = block.pointee.lpRawAudio else {
            return
        }
        let byteCount = Int(sampleCount) * Int(channels) * 2
        let data = Data(bytes: rawAudio, count: byteCount)
        let chunk = TeamTalkPlaybackAudioChunk(
            sourceID: streamID,
            streamTypes: STREAMTYPE_VOICE.rawValue,
            sampleRate: sampleRate,
            channels: channels,
            sampleCount: sampleCount,
            data: data
        )
        appleVoiceChatEngine.enqueuePlaybackChunk(chunk)
    }

    func insertAdvancedMicrophoneAudioChunkLocked(_ chunk: AdvancedMicrophoneAudioChunk) {
        guard voiceTransmissionEnabled,
              let instance,
              TT_GetMyChannelID(instance) > 0 else {
            logAudio(
                "Chunk skipped before injection. voice=\(voiceTransmissionEnabled) inChannel=\(instance.map { TT_GetMyChannelID($0) > 0 } ?? false) stream=\(chunk.streamID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount)"
            )
            return
        }

        let stats = chunkLevelStats(chunk.data)
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
            if TT_InsertAudioBlock(instance, &audioBlock) != 0 {
                insertedAudioChunkCount += 1
                if insertedAudioChunkCount <= 12 || insertedAudioChunkCount % 50 == 0 {
                    logAudio(
                        "Audio block injected. count=\(insertedAudioChunkCount) stream=\(chunk.streamID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount) peak=\(formatDecibels(stats.peak)) rms=\(formatDecibels(stats.rms)) bytes=\(chunk.data.count)"
                    )
                }
            } else {
                failedAudioChunkInsertCount += 1
                logAudio(
                    "TT_InsertAudioBlock failed. failed=\(failedAudioChunkInsertCount) stream=\(chunk.streamID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount) peak=\(formatDecibels(stats.peak)) rms=\(formatDecibels(stats.rms)) bytes=\(chunk.data.count)"
                )
            }
        }
    }

    func chunkLevelStats(_ data: Data) -> (peak: Float, rms: Float) {
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard let baseAddress = samples.baseAddress, samples.count > 0 else {
                return (0, 0)
            }

            var peak: Float = 0
            var sumSquares: Double = 0
            let scale = Float(Int16.max)
            for index in 0..<samples.count {
                let normalized = Float(baseAddress[index]) / scale
                let magnitude = abs(normalized)
                peak = max(peak, magnitude)
                sumSquares += Double(normalized * normalized)
            }
            let rms = Float((sumSquares / Double(samples.count)).squareRoot())
            return (peak, rms)
        }
    }

    func formatDecibels(_ value: Float) -> String {
        guard value > 0 else {
            return "-inf dBFS"
        }
        return String(format: "%.1f dBFS", 20 * log10(Double(value)))
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

        logAudio("Microphone target format changed. old=\(String(describing: advancedMicrophoneTargetFormat)) new=\(currentTargetFormat)")
        do {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "refreshAdvancedMicrophoneTargetIfNeededLocked")
            try ensureAdvancedMicrophoneInputReadyLocked(instance: instance)
        } catch {
            stopAdvancedMicrophoneInputLocked(instance: instance, reason: "refreshAdvancedMicrophoneTargetIfNeededLocked rollback")
            voiceTransmissionEnabled = false
            logAudio("Microphone target format refresh failed: \(error.localizedDescription)")
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

    func selectedOutputDeviceUIDLocked() throws -> String {
        let preference = preferencesStore.preferences.preferredOutputDevice
        // If the user picked a specific device, its persistentID is already the CoreAudio UID
        // (for non-legacy devices, makeAudioDeviceOption sets persistentID = szDeviceID = CoreAudio UID).
        if let prefID = preference.persistentID,
           prefID.isEmpty == false,
           !prefID.hasPrefix("legacy:") {
            let availableDevices = availableAudioDevicesLocked(forceRefresh: false).outputDevices
            if availableDevices.contains(where: { $0.persistentID == prefID }) {
                return prefID
            }
        }
        // Fall back to the system default output device via CoreAudio directly.
        return try systemDefaultOutputDeviceUID()
    }

    func systemDefaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioDeviceUnknown else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { ptr in
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, ptr)
        }
        guard status == noErr, let uid = cfUID else {
            throw TeamTalkConnectionError.internalError(L10n.text("connectedServer.audio.error.outputStartFailed"))
        }
        return uid as String
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
        guard TT_SetSoundOutputVolume(instance, volume) != 0 else {
            logAudio("Output gain application failed. value=\(Self.formatGainDB(gainDB)) volume=\(volume)")
            return
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

    nonisolated static func formatGainDB(_ value: Double) -> String {
        let rounded = AppPreferences.clampGainDB(value)
        if rounded > 0 {
            return String(format: "+%.0f dB", rounded)
        }
        return String(format: "%.0f dB", rounded)
    }
}
