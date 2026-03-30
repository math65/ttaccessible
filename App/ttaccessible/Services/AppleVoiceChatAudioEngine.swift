//
//  AppleVoiceChatAudioEngine.swift
//  ttaccessible
//
//  Created by Codex on 20/03/2026.
//

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct TeamTalkPlaybackAudioFormat: Equatable {
    let sampleRate: Int32
    let channels: Int32
}

struct TeamTalkPlaybackAudioChunk {
    let sourceID: Int32
    let streamTypes: StreamTypes
    let sampleRate: Int32
    let channels: Int32
    let sampleCount: Int32
    let data: Data
}

struct AppleVoiceChatAudioConfiguration: Equatable {
    let microphone: AdvancedMicrophoneAudioConfiguration
    let outputDeviceUID: String
    let outputGainDB: Double
}

struct AppleVoiceChatAudioStartResult {
    let streamID: Int32
    let playbackFormat: TeamTalkPlaybackAudioFormat
}

final class AppleVoiceChatAudioEngine {
    private struct GateState {
        var gain: Float = 1
        var holdFramesRemaining: Int = 0
    }

    private struct ExpanderState {
        var gain: Float = 1
    }

    private struct LimiterState {
        var gain: Float = 1
    }

    private struct StateSnapshot {
        let configuration: AppleVoiceChatAudioConfiguration
        let streamID: Int32
        var gateState: GateState
        var expanderState: ExpanderState
        var limiterState: LimiterState
    }

    private enum ResolvedSelection {
        case mono(channelIndex: Int)
        case stereoPair(firstIndex: Int, secondIndex: Int)
        case monoMix(firstIndex: Int, secondIndex: Int)

        var outputChannels: Int {
            switch self {
            case .mono, .monoMix:
                return 1
            case .stereoPair:
                return 2
            }
        }
    }

    private let stateLock = NSLock()
    private let playbackLock = NSLock()
    private let diagnosticsLogger = AudioDiagnosticsLogger.shared
    private let diagnosticsScope: String
    private let onAudioChunk: (AdvancedMicrophoneAudioChunk) -> Void

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playbackAudioFormat: AVAudioFormat?
    private var currentConfiguration: AppleVoiceChatAudioConfiguration?
    private var gateState = GateState()
    private var expanderState = ExpanderState()
    private var limiterState = LimiterState()
    private var nextStreamID: Int32 = 1
    private var activeStreamID: Int32 = 0
    private var outputGainDB: Double = 0

    private var interleavedBuffer = [Float]()
    private var selectedBuffer = [Float]()
    private var adaptedBuffer = [Float]()
    private var int16Buffer = [Int16]()
    private var callbackCount = 0
    private var lastLoggedBufferSignature = ""
    private var playbackChunkCount = 0
    private var scheduledBufferCount = 0

    init(
        diagnosticsScope: String,
        onAudioChunk: @escaping (AdvancedMicrophoneAudioChunk) -> Void
    ) {
        self.diagnosticsScope = diagnosticsScope
        self.onAudioChunk = onAudioChunk
    }

    var isRunning: Bool {
        withStateLock {
            engine != nil
        }
    }

    func start(configuration: AppleVoiceChatAudioConfiguration) throws -> AppleVoiceChatAudioStartResult {
        try startLocked(configuration: configuration)
    }

    func stop() {
        stopLocked()
    }

    func updateInputGainDB(_ value: Double) {
        withStateLock {
            guard var configuration = currentConfiguration else {
                return
            }
            configuration = AppleVoiceChatAudioConfiguration(
                microphone: AdvancedMicrophoneAudioConfiguration(
                    device: configuration.microphone.device,
                    preset: configuration.microphone.preset,
                    inputGainDB: value,
                    echoCancellationEnabled: configuration.microphone.echoCancellationEnabled,
                    dynamicProcessorEnabled: configuration.microphone.dynamicProcessorEnabled,
                    dynamicProcessorMode: configuration.microphone.dynamicProcessorMode,
                    gateThresholdDB: configuration.microphone.gateThresholdDB,
                    gateAttackMilliseconds: configuration.microphone.gateAttackMilliseconds,
                    gateHoldMilliseconds: configuration.microphone.gateHoldMilliseconds,
                    gateReleaseMilliseconds: configuration.microphone.gateReleaseMilliseconds,
                    expanderThresholdDB: configuration.microphone.expanderThresholdDB,
                    expanderRatio: configuration.microphone.expanderRatio,
                    expanderAttackMilliseconds: configuration.microphone.expanderAttackMilliseconds,
                    expanderReleaseMilliseconds: configuration.microphone.expanderReleaseMilliseconds,
                    limiterEnabled: configuration.microphone.limiterEnabled,
                    limiterMode: configuration.microphone.limiterMode,
                    limiterPreset: configuration.microphone.limiterPreset,
                    limiterThresholdDB: configuration.microphone.limiterThresholdDB,
                    limiterReleaseMilliseconds: configuration.microphone.limiterReleaseMilliseconds,
                    targetFormat: configuration.microphone.targetFormat
                ),
                outputDeviceUID: configuration.outputDeviceUID,
                outputGainDB: configuration.outputGainDB
            )
            currentConfiguration = configuration
        }
    }

    func updateOutputGainDB(_ value: Double) {
        withStateLock {
            outputGainDB = value
            guard let configuration = currentConfiguration else {
                return
            }
            currentConfiguration = AppleVoiceChatAudioConfiguration(
                microphone: configuration.microphone,
                outputDeviceUID: configuration.outputDeviceUID,
                outputGainDB: value
            )
        }
    }

    @discardableResult
    func enqueuePlaybackChunk(_ chunk: TeamTalkPlaybackAudioChunk) -> Bool {
        guard let playbackAudioFormat,
              Int32(playbackAudioFormat.channelCount) == chunk.channels,
              Int32(playbackAudioFormat.sampleRate.rounded()) == chunk.sampleRate,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: playbackAudioFormat,
                frameCapacity: AVAudioFrameCount(chunk.sampleCount)
              ) else {
            logDiagnostics(
                "Drop playback chunk. formatMismatch source=\(chunk.sourceID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount)"
            )
            return false
        }

        playbackLock.lock()
        let shouldDrop = scheduledBufferCount >= 24
        if shouldDrop == false {
            scheduledBufferCount += 1
        }
        playbackLock.unlock()

        guard shouldDrop == false else {
            logDiagnostics(
                "Drop playback chunk. queueFull source=\(chunk.sourceID) scheduled=\(scheduledBufferCount)"
            )
            return false
        }

        buffer.frameLength = AVAudioFrameCount(chunk.sampleCount)
        let channelCount = Int(chunk.channels)
        let frameCount = Int(chunk.sampleCount)
        let gainDB = withStateLock { outputGainDB }
        let gain = Float(pow(10.0, gainDB / 20.0))
        playbackChunkCount += 1

        chunk.data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: Int16.self)
            guard let baseAddress = source.baseAddress,
                  let channelData = buffer.int16ChannelData else {
                return
            }

            if channelCount == 1 {
                for frame in 0..<frameCount {
                    channelData[0][frame] = applyGain(baseAddress[frame], gain: gain)
                }
                return
            }

            for frame in 0..<frameCount {
                let sourceFrame = frame * channelCount
                for channel in 0..<channelCount {
                    channelData[channel][frame] = applyGain(baseAddress[sourceFrame + channel], gain: gain)
                }
            }
        }

        playerNode?.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self else { return }
            self.playbackLock.lock()
            self.scheduledBufferCount = max(self.scheduledBufferCount - 1, 0)
            self.playbackLock.unlock()
        }

        if playbackChunkCount <= 12 || playbackChunkCount % 50 == 0 {
            let stats = chunkLevelStats(chunk.data, gainDB: gainDB)
            logDiagnostics(
                "Playback chunk #\(playbackChunkCount) source=\(chunk.sourceID) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount) peak=\(formatDecibels(stats.peak)) rms=\(formatDecibels(stats.rms))"
            )
        }

        return true
    }

    private func startLocked(configuration: AppleVoiceChatAudioConfiguration) throws -> AppleVoiceChatAudioStartResult {
        stopLocked()

        guard configuration.microphone.device.inputChannels > 0 else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()
        let inputNode = newEngine.inputNode
        let outputNode = newEngine.outputNode
        callbackCount = 0
        playbackChunkCount = 0
        lastLoggedBufferSignature = ""
        scheduledBufferCount = 0

        logDiagnostics(
            "startLocked. inputUID=\(configuration.microphone.device.uid) outputUID=\(configuration.outputDeviceUID)"
        )

        let inputDeviceIDResolved = Self.audioDeviceID(forUID: configuration.microphone.device.uid)
        let outputDeviceIDResolved = Self.audioDeviceID(forUID: configuration.outputDeviceUID)
        logDiagnostics(
            "DeviceID resolution. inputDeviceID=\(String(describing: inputDeviceIDResolved)) outputDeviceID=\(String(describing: outputDeviceIDResolved))"
        )
        guard let inputDeviceID = inputDeviceIDResolved,
              let outputDeviceID = outputDeviceIDResolved else {
            logDiagnostics("FAIL: audioDeviceID resolution failed.")
            throw AdvancedMicrophoneAudioEngineError.playbackRoutingUnavailable
        }

        // Enable VoiceProcessingIO BEFORE setting devices. Accessing inputNode
        // creates a RemoteIO AudioUnit; setVoiceProcessingEnabled replaces it with
        // a VPIO AudioUnit. Device routing must happen on the VPIO unit.
        if #available(macOS 13.0, *) {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                applyMinimumOtherAudioDucking(to: inputNode)
                logDiagnostics("VoiceProcessingIO enabled.")
            } catch {
                logDiagnostics("FAIL: setVoiceProcessingEnabled threw: \(error)")
                throw AdvancedMicrophoneAudioEngineError.voiceProcessingUnavailable
            }
        } else {
            logDiagnostics("FAIL: macOS 13+ not available.")
            throw AdvancedMicrophoneAudioEngineError.voiceProcessingUnavailable
        }

        var mutableInputDeviceID = inputDeviceID
        let inputStatus = AudioUnitSetProperty(
            inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableInputDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        logDiagnostics("AudioUnitSetProperty inputDevice status=\(inputStatus)")
        guard inputStatus == noErr else {
            logDiagnostics("FAIL: AudioUnitSetProperty input device failed. status=\(inputStatus)")
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        var mutableOutputDeviceID = outputDeviceID
        let outputStatus = AudioUnitSetProperty(
            outputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableOutputDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        logDiagnostics("AudioUnitSetProperty outputDevice status=\(outputStatus)")
        guard outputStatus == noErr else {
            logDiagnostics("FAIL: AudioUnitSetProperty output device failed. status=\(outputStatus)")
            throw AdvancedMicrophoneAudioEngineError.playbackRoutingUnavailable
        }

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let outputRenderFormat = outputNode.inputFormat(forBus: 0)
        let inputChannelCount = Int(hardwareFormat.channelCount)
        logDiagnostics(
            "Formats. hwRate=\(hardwareFormat.sampleRate) hwChannels=\(inputChannelCount) outRate=\(outputRenderFormat.sampleRate) outChannels=\(outputRenderFormat.channelCount)"
        )
        guard inputChannelCount > 0 else {
            logDiagnostics("FAIL: inputChannelCount=0")
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Cap to stereo: TeamTalk voice is at most stereo, and AVAudioFormat with
        // pcmFormatInt16 non-interleaved fails for > 2 channels on multi-output hardware.
        // AVAudioEngine maps the stereo player node to the hardware output automatically.
        let effectivePlaybackFormat = TeamTalkPlaybackAudioFormat(
            sampleRate: Int32(outputRenderFormat.sampleRate.rounded()),
            channels: Int32(min(max(outputRenderFormat.channelCount, 1), 2))
        )
        guard let requestedPlaybackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(effectivePlaybackFormat.sampleRate),
            channels: AVAudioChannelCount(max(effectivePlaybackFormat.channels, 1)),
            interleaved: false
        ) else {
            logDiagnostics("FAIL: AVAudioFormat creation failed. rate=\(effectivePlaybackFormat.sampleRate) channels=\(effectivePlaybackFormat.channels)")
            throw AdvancedMicrophoneAudioEngineError.playbackRoutingUnavailable
        }

        logDiagnostics(
            "Start. inputDevice=\(configuration.microphone.device.name) outputUID=\(configuration.outputDeviceUID) hwRate=\(hardwareFormat.sampleRate) hwChannels=\(inputChannelCount) commonFormat=\(describe(hardwareFormat.commonFormat)) interleaved=\(hardwareFormat.isInterleaved) outputRate=\(outputRenderFormat.sampleRate) outputChannels=\(outputRenderFormat.channelCount) playbackRate=\(effectivePlaybackFormat.sampleRate) playbackChannels=\(effectivePlaybackFormat.channels)"
        )

        newEngine.attach(newPlayerNode)
        newEngine.connect(newPlayerNode, to: newEngine.mainMixerNode, format: requestedPlaybackFormat)

        let intervalMSec = max(configuration.microphone.targetFormat.txIntervalMSec, 20)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : (configuration.microphone.targetFormat.sampleRate > 0 ? configuration.microphone.targetFormat.sampleRate : 48_000)
        let bufferFrameCount = AVAudioFrameCount(max((sampleRate * Double(intervalMSec)) / 1000.0, 256))

        gateState = GateState()
        expanderState = ExpanderState()
        limiterState = LimiterState()

        let effectiveTargetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: sampleRate,
            channels: configuration.microphone.targetFormat.channels,
            txIntervalMSec: configuration.microphone.targetFormat.txIntervalMSec
        )

        let storedMicrophone = AdvancedMicrophoneAudioConfiguration(
            device: InputAudioDeviceInfo(
                uid: configuration.microphone.device.uid,
                name: configuration.microphone.device.name,
                inputChannels: inputChannelCount,
                nominalSampleRate: sampleRate
            ),
            preset: configuration.microphone.preset,
            inputGainDB: configuration.microphone.inputGainDB,
            echoCancellationEnabled: true,
            dynamicProcessorEnabled: configuration.microphone.dynamicProcessorEnabled,
            dynamicProcessorMode: configuration.microphone.dynamicProcessorMode,
            gateThresholdDB: configuration.microphone.gateThresholdDB,
            gateAttackMilliseconds: configuration.microphone.gateAttackMilliseconds,
            gateHoldMilliseconds: configuration.microphone.gateHoldMilliseconds,
            gateReleaseMilliseconds: configuration.microphone.gateReleaseMilliseconds,
            expanderThresholdDB: configuration.microphone.expanderThresholdDB,
            expanderRatio: configuration.microphone.expanderRatio,
            expanderAttackMilliseconds: configuration.microphone.expanderAttackMilliseconds,
            expanderReleaseMilliseconds: configuration.microphone.expanderReleaseMilliseconds,
            limiterEnabled: configuration.microphone.limiterEnabled,
            limiterMode: configuration.microphone.limiterMode,
            limiterPreset: configuration.microphone.limiterPreset,
            limiterThresholdDB: configuration.microphone.limiterThresholdDB,
            limiterReleaseMilliseconds: configuration.microphone.limiterReleaseMilliseconds,
            targetFormat: effectiveTargetFormat
        )

        let streamID = withStateLock {
            currentConfiguration = AppleVoiceChatAudioConfiguration(
                microphone: storedMicrophone,
                outputDeviceUID: configuration.outputDeviceUID,
                outputGainDB: configuration.outputGainDB
            )
            outputGainDB = configuration.outputGainDB
            engine = newEngine
            playerNode = newPlayerNode
            playbackAudioFormat = requestedPlaybackFormat
            activeStreamID = nextStreamID
            nextStreamID = nextStreamID == Int32.max ? 1 : nextStreamID + 1
            return activeStreamID
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferFrameCount, format: hardwareFormat) { [weak self] buffer, _ in
            self?.handleAVAudioBuffer(buffer, channelCount: inputChannelCount)
        }

        newEngine.prepare()
        do {
            try newEngine.start()
            newPlayerNode.play()
        } catch {
            logDiagnostics("FAIL: AVAudioEngine.start() threw: \(error)")
            inputNode.removeTap(onBus: 0)
            _ = clearState(for: newEngine)
            throw AdvancedMicrophoneAudioEngineError.playbackEngineStartFailed
        }

        return AppleVoiceChatAudioStartResult(
            streamID: streamID,
            playbackFormat: effectivePlaybackFormat
        )
    }

    private func stopLocked() {
        let stoppedEngine = clearState(for: nil)

        if let stoppedEngine {
            stoppedEngine.inputNode.removeTap(onBus: 0)
            playerNode?.stop()
            stoppedEngine.stop()
            playbackLock.lock()
            scheduledBufferCount = 0
            playbackLock.unlock()
            logDiagnostics("Stop.")
        }
    }

    private func handleAVAudioBuffer(_ buffer: AVAudioPCMBuffer, channelCount: Int) {
        let inputChannelCount = channelCount
        guard inputChannelCount > 0 else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return
        }

        let availableChannels = min(inputChannelCount, Int(buffer.format.channelCount))
        guard availableChannels > 0 else {
            return
        }

        guard let snapshot: StateSnapshot = withStateLock({
            guard engine != nil,
                  let configuration = currentConfiguration,
                  activeStreamID > 0 else {
                return nil
            }
            return StateSnapshot(
                configuration: configuration,
                streamID: activeStreamID,
                gateState: gateState,
                expanderState: expanderState,
                limiterState: limiterState
            )
        }) else {
            return
        }

        let configuration = snapshot.configuration
        var localGateState = snapshot.gateState
        var localExpanderState = snapshot.expanderState
        var localLimiterState = snapshot.limiterState

        let interleavedCount = frameCount * availableChannels
        if interleavedBuffer.count < interleavedCount {
            interleavedBuffer = [Float](repeating: 0, count: interleavedCount)
        }
        guard copySamplesToInterleavedBuffer(
            buffer,
            frameCount: frameCount,
            availableChannels: availableChannels,
            output: &interleavedBuffer
        ) else {
            logDiagnostics("Drop input buffer. unsupportedFormat format=\(describe(buffer.format.commonFormat))")
            return
        }

        callbackCount += 1
        let selection = resolvedSelection(for: configuration.microphone.preset, availableChannels: availableChannels)
        let bufferSignature = [
            "rate=\(buffer.format.sampleRate)",
            "channels=\(availableChannels)",
            "frames=\(frameCount)",
            "format=\(describe(buffer.format.commonFormat))",
            "interleaved=\(buffer.format.isInterleaved)",
            "selection=\(describe(selection))"
        ].joined(separator: " ")
        if bufferSignature != lastLoggedBufferSignature {
            lastLoggedBufferSignature = bufferSignature
            logDiagnostics("Capture format changed. \(bufferSignature)")
        }

        let inputStats = sampleStats(samples: interleavedBuffer, count: interleavedCount)
        let selectedCount = frameCount * selection.outputChannels
        if selectedBuffer.count < selectedCount {
            selectedBuffer = [Float](repeating: 0, count: selectedCount)
        }
        selectChannelsInPlace(
            from: &interleavedBuffer,
            to: &selectedBuffer,
            frameCount: frameCount,
            sourceChannels: availableChannels,
            selection: selection
        )

        applyInputGainInPlace(
            to: &selectedBuffer,
            count: selectedCount,
            gainDB: configuration.microphone.inputGainDB
        )

        if configuration.microphone.dynamicProcessorEnabled {
            switch configuration.microphone.dynamicProcessorMode {
            case .gate:
                applyGate(
                    to: &selectedBuffer,
                    count: selectedCount,
                    channels: selection.outputChannels,
                    sampleRate: configuration.microphone.targetFormat.sampleRate,
                    thresholdDB: configuration.microphone.gateThresholdDB,
                    attackMilliseconds: configuration.microphone.gateAttackMilliseconds,
                    holdMilliseconds: configuration.microphone.gateHoldMilliseconds,
                    releaseMilliseconds: configuration.microphone.gateReleaseMilliseconds,
                    state: &localGateState
                )
            case .expander:
                applyExpander(
                    to: &selectedBuffer,
                    count: selectedCount,
                    channels: selection.outputChannels,
                    sampleRate: configuration.microphone.targetFormat.sampleRate,
                    thresholdDB: configuration.microphone.expanderThresholdDB,
                    ratio: configuration.microphone.expanderRatio,
                    attackMilliseconds: configuration.microphone.expanderAttackMilliseconds,
                    releaseMilliseconds: configuration.microphone.expanderReleaseMilliseconds,
                    state: &localExpanderState
                )
            }
        }

        if configuration.microphone.limiterEnabled {
            applyLimiter(
                to: &selectedBuffer,
                count: selectedCount,
                channels: selection.outputChannels,
                sampleRate: configuration.microphone.targetFormat.sampleRate,
                mode: configuration.microphone.limiterMode,
                preset: configuration.microphone.limiterPreset,
                thresholdDB: configuration.microphone.limiterThresholdDB,
                releaseMilliseconds: configuration.microphone.limiterReleaseMilliseconds,
                state: &localLimiterState
            )
        }

        let targetChannels = max(configuration.microphone.targetFormat.channels, 1)
        let adaptedCount: Int
        if selection.outputChannels == targetChannels {
            adaptedCount = selectedCount
        } else {
            adaptedCount = frameCount * targetChannels
            if adaptedBuffer.count < adaptedCount {
                adaptedBuffer = [Float](repeating: 0, count: adaptedCount)
            }
            adaptChannelCountInPlace(
                from: &selectedBuffer,
                to: &adaptedBuffer,
                frameCount: frameCount,
                sourceChannels: selection.outputChannels,
                targetChannels: targetChannels
            )
        }

        guard adaptedCount > 0 else {
            return
        }

        let sourceForConversion = (selection.outputChannels == targetChannels) ? selectedBuffer : adaptedBuffer
        let outputStats = sampleStats(samples: sourceForConversion, count: adaptedCount)

        if shouldLogInputStats(callbackCount) {
            logDiagnostics(
                "Input buffer #\(callbackCount) inputPeak=\(formatDecibels(inputStats.peak)) inputRMS=\(formatDecibels(inputStats.rms)) outputPeak=\(formatDecibels(outputStats.peak)) outputRMS=\(formatDecibels(outputStats.rms)) selectedChannels=\(selection.outputChannels) targetChannels=\(targetChannels) samples=\(adaptedCount / targetChannels)"
            )
        }

        if int16Buffer.count < adaptedCount {
            int16Buffer = [Int16](repeating: 0, count: adaptedCount)
        }
        for index in 0..<adaptedCount {
            int16Buffer[index] = floatToPCM16(sourceForConversion[index])
        }

        let payload = int16Buffer.withUnsafeBufferPointer { bufferPointer in
            Data(bytes: bufferPointer.baseAddress!, count: adaptedCount * MemoryLayout<Int16>.size)
        }

        let chunk = AdvancedMicrophoneAudioChunk(
            streamID: snapshot.streamID,
            sampleRate: Int32(configuration.microphone.targetFormat.sampleRate.rounded()),
            channels: Int32(targetChannels),
            sampleCount: Int32(adaptedCount / targetChannels),
            data: payload
        )

        withStateLock {
            gateState = localGateState
            expanderState = localExpanderState
            limiterState = localLimiterState
        }

        onAudioChunk(chunk)
    }

    private func clearState(for engineToMatch: AVAudioEngine?) -> AVAudioEngine? {
        withStateLock {
            let currentEngine = engine
            if let engineToMatch, currentEngine !== engineToMatch {
                return nil
            }

            engine = nil
            playerNode = nil
            playbackAudioFormat = nil
            currentConfiguration = nil
            gateState = GateState()
            expanderState = ExpanderState()
            limiterState = LimiterState()
            activeStreamID = 0
            return currentEngine
        }
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: CFString = uid as CFString
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &dataSize,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private func applyInputGainInPlace(to samples: inout [Float], count: Int, gainDB: Double) {
        guard count > 0, gainDB != 0 else {
            return
        }

        let gain = Float(pow(10, gainDB / 20))
        for index in 0..<count {
            samples[index] *= gain
        }
    }

    private func applyMinimumOtherAudioDucking(to inputNode: AVAudioInputNode) {
        guard #available(macOS 14.0, *) else {
            return
        }

        inputNode.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: false,
            duckingLevel: .min
        )
        logDiagnostics("AEC ducking configured. advanced=false level=min")
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private func logDiagnostics(_ message: String) {
        diagnosticsLogger.log(diagnosticsScope, message)
    }

    private func shouldLogInputStats(_ count: Int) -> Bool {
        count <= 12 || count % 50 == 0
    }

    private func describe(_ preset: InputChannelPreset) -> String {
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

    private func describe(_ selection: ResolvedSelection) -> String {
        switch selection {
        case .mono(let channelIndex):
            return "mono[\(channelIndex)]"
        case .stereoPair(let firstIndex, let secondIndex):
            return "stereo[\(firstIndex),\(secondIndex)]"
        case .monoMix(let firstIndex, let secondIndex):
            return "monoMix[\(firstIndex),\(secondIndex)]"
        }
    }

    private func describe(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .pcmFormatFloat32:
            return "float32"
        case .pcmFormatFloat64:
            return "float64"
        case .pcmFormatInt16:
            return "int16"
        case .pcmFormatInt32:
            return "int32"
        case .otherFormat:
            return "other"
        @unknown default:
            return "unknown"
        }
    }

    private func sampleStats(samples: [Float], count: Int) -> (peak: Float, rms: Float) {
        guard count > 0 else {
            return (0, 0)
        }

        var peak: Float = 0
        var sumSquares: Double = 0
        for index in 0..<count {
            let sample = samples[index]
            let magnitude = abs(sample)
            peak = max(peak, magnitude)
            sumSquares += Double(sample * sample)
        }

        let rms = Float((sumSquares / Double(count)).squareRoot())
        return (peak, rms)
    }

    private func chunkLevelStats(_ data: Data, gainDB: Double) -> (peak: Float, rms: Float) {
        let gain = Float(pow(10.0, gainDB / 20.0))
        return data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard let baseAddress = samples.baseAddress, samples.count > 0 else {
                return (0, 0)
            }

            var peak: Float = 0
            var sumSquares: Double = 0
            let scale = Float(Int16.max)
            for index in 0..<samples.count {
                let normalized = max(-1, min(1, (Float(baseAddress[index]) / scale) * gain))
                let magnitude = abs(normalized)
                peak = max(peak, magnitude)
                sumSquares += Double(normalized * normalized)
            }
            let rms = Float((sumSquares / Double(samples.count)).squareRoot())
            return (peak, rms)
        }
    }

    private func formatDecibels(_ value: Float) -> String {
        guard value > 0 else {
            return "-inf dBFS"
        }
        return String(format: "%.1f dBFS", 20 * log10(Double(value)))
    }

    private func applyGain(_ sample: Int16, gain: Float) -> Int16 {
        let normalized = Float(sample) / Float(Int16.max)
        return floatToPCM16(normalized * gain)
    }

    private func copySamplesToInterleavedBuffer(
        _ buffer: AVAudioPCMBuffer,
        frameCount: Int,
        availableChannels: Int,
        output: inout [Float]
    ) -> Bool {
        let format = buffer.format
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)

        switch format.commonFormat {
        case .pcmFormatFloat32:
            if format.isInterleaved {
                guard let source = audioBuffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                    return false
                }
                let sampleCount = frameCount * availableChannels
                for index in 0..<sampleCount {
                    output[index] = source[index]
                }
                return true
            }

            guard let channels = buffer.floatChannelData else {
                return false
            }
            for frame in 0..<frameCount {
                for channel in 0..<availableChannels {
                    output[(frame * availableChannels) + channel] = channels[channel][frame]
                }
            }
            return true

        case .pcmFormatInt16:
            let scale = Float(Int16.max)
            if format.isInterleaved {
                guard let source = audioBuffers.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                    return false
                }
                let sampleCount = frameCount * availableChannels
                for index in 0..<sampleCount {
                    output[index] = Float(source[index]) / scale
                }
                return true
            }

            guard let channels = buffer.int16ChannelData else {
                return false
            }
            for frame in 0..<frameCount {
                for channel in 0..<availableChannels {
                    output[(frame * availableChannels) + channel] = Float(channels[channel][frame]) / scale
                }
            }
            return true

        case .pcmFormatInt32:
            let scale = Float(Int32.max)
            if format.isInterleaved {
                guard let source = audioBuffers.first?.mData?.assumingMemoryBound(to: Int32.self) else {
                    return false
                }
                let sampleCount = frameCount * availableChannels
                for index in 0..<sampleCount {
                    output[index] = Float(source[index]) / scale
                }
                return true
            }

            guard let channels = buffer.int32ChannelData else {
                return false
            }
            for frame in 0..<frameCount {
                for channel in 0..<availableChannels {
                    output[(frame * availableChannels) + channel] = Float(channels[channel][frame]) / scale
                }
            }
            return true

        default:
            return false
        }
    }

    private func resolvedSelection(for preset: InputChannelPreset, availableChannels: Int) -> ResolvedSelection {
        switch preset {
        case .auto:
            if availableChannels >= 2 {
                return .stereoPair(firstIndex: 0, secondIndex: 1)
            }
            return .mono(channelIndex: 0)
        case .mono(let channel):
            let index = min(max(channel - 1, 0), max(availableChannels - 1, 0))
            return .mono(channelIndex: index)
        case .stereoPair(let first, let second):
            let firstIndex = min(max(first - 1, 0), max(availableChannels - 1, 0))
            let secondIndex = min(max(second - 1, 0), max(availableChannels - 1, 0))
            return .stereoPair(firstIndex: firstIndex, secondIndex: secondIndex)
        case .monoMix(let first, let second):
            let firstIndex = min(max(first - 1, 0), max(availableChannels - 1, 0))
            let secondIndex = min(max(second - 1, 0), max(availableChannels - 1, 0))
            return .monoMix(firstIndex: firstIndex, secondIndex: secondIndex)
        }
    }

    private func selectChannelsInPlace(
        from source: inout [Float],
        to output: inout [Float],
        frameCount: Int,
        sourceChannels: Int,
        selection: ResolvedSelection
    ) {
        switch selection {
        case .mono(let channelIndex):
            for frame in 0..<frameCount {
                output[frame] = source[(frame * sourceChannels) + channelIndex]
            }
        case .stereoPair(let firstIndex, let secondIndex):
            for frame in 0..<frameCount {
                let sourceFrameIndex = frame * sourceChannels
                let outputIndex = frame * 2
                output[outputIndex] = source[sourceFrameIndex + firstIndex]
                output[outputIndex + 1] = source[sourceFrameIndex + secondIndex]
            }
        case .monoMix(let firstIndex, let secondIndex):
            for frame in 0..<frameCount {
                let sourceFrameIndex = frame * sourceChannels
                output[frame] = (source[sourceFrameIndex + firstIndex] + source[sourceFrameIndex + secondIndex]) * 0.5
            }
        }
    }

    private func applyLimiter(
        to samples: inout [Float],
        count: Int,
        channels: Int,
        sampleRate: Double,
        mode: LimiterControlMode,
        preset: LimiterPreset,
        thresholdDB: Double,
        releaseMilliseconds: Double,
        state: inout LimiterState
    ) {
        let (threshold, releaseStep) = limiterParameters(
            mode: mode,
            preset: preset,
            thresholdDB: thresholdDB,
            releaseMilliseconds: releaseMilliseconds,
            sampleRate: sampleRate
        )
        guard channels > 0 else {
            return
        }

        for frame in 0..<(count / channels) {
            let startIndex = frame * channels
            var peak: Float = 0
            for channel in 0..<channels {
                peak = max(peak, abs(samples[startIndex + channel]))
            }

            let targetGain: Float
            if peak > threshold, peak > 0 {
                targetGain = threshold / peak
            } else {
                targetGain = 1
            }

            if targetGain < state.gain {
                state.gain = targetGain
            } else {
                state.gain = min(1, state.gain + releaseStep)
            }

            for channel in 0..<channels {
                samples[startIndex + channel] *= state.gain
            }
        }
    }

    private func limiterParameters(
        mode: LimiterControlMode,
        preset: LimiterPreset,
        thresholdDB: Double,
        releaseMilliseconds: Double,
        sampleRate: Double
    ) -> (threshold: Float, releaseStep: Float) {
        let effectiveThresholdDB: Double
        let effectiveReleaseMilliseconds: Double

        switch mode {
        case .preset:
            effectiveThresholdDB = preset.thresholdDB
            effectiveReleaseMilliseconds = preset.releaseMilliseconds
        case .manual:
            effectiveThresholdDB = AdvancedInputAudioPreferences.clampThresholdDB(thresholdDB)
            effectiveReleaseMilliseconds = AdvancedInputAudioPreferences.clampReleaseMilliseconds(releaseMilliseconds)
        }

        let linearThreshold = Float(pow(10, effectiveThresholdDB / 20))
        let releaseFrames = max((effectiveReleaseMilliseconds / 1000) * sampleRate, 1)
        let releaseStep = Float(1 / releaseFrames)
        return (max(0.0001, linearThreshold), max(0.0001, releaseStep))
    }

    private func applyGate(
        to samples: inout [Float],
        count: Int,
        channels: Int,
        sampleRate: Double,
        thresholdDB: Double,
        attackMilliseconds: Double,
        holdMilliseconds: Double,
        releaseMilliseconds: Double,
        state: inout GateState
    ) {
        guard channels > 0 else {
            return
        }

        let threshold = max(0.00001, Float(pow(10, AdvancedInputAudioPreferences.clampNoiseGateThresholdDB(thresholdDB) / 20)))
        let attackFrames = max((AdvancedInputAudioPreferences.clampNoiseGateAttackMilliseconds(attackMilliseconds) / 1000) * sampleRate, 1)
        let holdFrames = max(Int(((AdvancedInputAudioPreferences.clampNoiseGateHoldMilliseconds(holdMilliseconds) / 1000) * sampleRate).rounded()), 0)
        let releaseFrames = max((AdvancedInputAudioPreferences.clampNoiseGateReleaseMilliseconds(releaseMilliseconds) / 1000) * sampleRate, 1)
        let attackStep = Float(1 / attackFrames)
        let releaseStep = Float(1 / releaseFrames)

        for frame in 0..<(count / channels) {
            let startIndex = frame * channels
            var peak: Float = 0
            for channel in 0..<channels {
                peak = max(peak, abs(samples[startIndex + channel]))
            }

            let shouldOpen = peak >= threshold
            if shouldOpen {
                state.holdFramesRemaining = holdFrames
                state.gain = min(1, state.gain + attackStep)
            } else if state.holdFramesRemaining > 0 {
                state.holdFramesRemaining -= 1
            } else {
                state.gain = max(0, state.gain - releaseStep)
            }

            for channel in 0..<channels {
                samples[startIndex + channel] *= state.gain
            }
        }
    }

    private func applyExpander(
        to samples: inout [Float],
        count: Int,
        channels: Int,
        sampleRate: Double,
        thresholdDB: Double,
        ratio: Double,
        attackMilliseconds: Double,
        releaseMilliseconds: Double,
        state: inout ExpanderState
    ) {
        guard channels > 0 else {
            return
        }

        let threshold = max(0.00001, Float(pow(10, AdvancedInputAudioPreferences.clampNoiseGateThresholdDB(thresholdDB) / 20)))
        let clampedRatio = Float(AdvancedInputAudioPreferences.clampExpanderRatio(ratio))
        let attackFrames = max((AdvancedInputAudioPreferences.clampNoiseGateAttackMilliseconds(attackMilliseconds) / 1000) * sampleRate, 1)
        let releaseFrames = max((AdvancedInputAudioPreferences.clampNoiseGateReleaseMilliseconds(releaseMilliseconds) / 1000) * sampleRate, 1)
        let attackStep = Float(1 / attackFrames)
        let releaseStep = Float(1 / releaseFrames)

        for frame in 0..<(count / channels) {
            let startIndex = frame * channels
            var peak: Float = 0
            for channel in 0..<channels {
                peak = max(peak, abs(samples[startIndex + channel]))
            }

            let targetGain: Float
            if peak <= 0 || peak >= threshold {
                targetGain = 1
            } else {
                let peakDB = 20 * log10(max(peak, 0.000_001))
                let deltaBelowThreshold = Float(thresholdDB) - peakDB
                let reducedDB = deltaBelowThreshold * (1 - (1 / clampedRatio))
                targetGain = Float(pow(10, Double(-reducedDB) / 20))
            }

            if targetGain > state.gain {
                state.gain = min(targetGain, state.gain + attackStep)
            } else {
                state.gain = max(targetGain, state.gain - releaseStep)
            }

            for channel in 0..<channels {
                samples[startIndex + channel] *= state.gain
            }
        }
    }

    private func adaptChannelCountInPlace(
        from source: inout [Float],
        to output: inout [Float],
        frameCount: Int,
        sourceChannels: Int,
        targetChannels: Int
    ) {
        if sourceChannels == 1, targetChannels == 2 {
            for frame in 0..<frameCount {
                let sample = source[frame]
                output[frame * 2] = sample
                output[(frame * 2) + 1] = sample
            }
        } else if sourceChannels == 2, targetChannels == 1 {
            for frame in 0..<frameCount {
                let index = frame * 2
                output[frame] = (source[index] + source[index + 1]) * 0.5
            }
        }
    }

    private func floatToPCM16(_ sample: Float) -> Int16 {
        let clamped = max(-1, min(1, sample))
        if clamped >= 1 {
            return Int16.max
        }
        if clamped <= -1 {
            return Int16.min
        }
        return Int16((clamped * 32767).rounded())
    }
}
