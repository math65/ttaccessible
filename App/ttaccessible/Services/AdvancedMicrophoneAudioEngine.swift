//
//  AdvancedMicrophoneAudioEngine.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct AdvancedMicrophoneAudioTargetFormat: Equatable {
    let sampleRate: Double
    let channels: Int
    let txIntervalMSec: Int32
}

struct AdvancedMicrophoneAudioConfiguration: Equatable {
    let device: InputAudioDeviceInfo
    let preset: InputChannelPreset
    var inputGainDB: Double
    let echoCancellationEnabled: Bool
    let dynamicProcessorEnabled: Bool
    let dynamicProcessorMode: DynamicProcessorMode
    let gateThresholdDB: Double
    let gateAttackMilliseconds: Double
    let gateHoldMilliseconds: Double
    let gateReleaseMilliseconds: Double
    let expanderThresholdDB: Double
    let expanderRatio: Double
    let expanderAttackMilliseconds: Double
    let expanderReleaseMilliseconds: Double
    let limiterEnabled: Bool
    let limiterMode: LimiterControlMode
    let limiterPreset: LimiterPreset
    let limiterThresholdDB: Double
    let limiterReleaseMilliseconds: Double
    let targetFormat: AdvancedMicrophoneAudioTargetFormat
}

struct AdvancedMicrophoneAudioChunk {
    let streamID: Int32
    let sampleRate: Int32
    let channels: Int32
    let sampleCount: Int32
    let data: Data
}

enum AdvancedMicrophoneAudioEngineError: LocalizedError {
    case deviceUnavailable
    case voiceProcessingUnavailable
    case playbackRoutingUnavailable
    case playbackEngineStartFailed
    case queueCreationFailed
    case queueStartFailed
    case queueBufferAllocationFailed
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return L10n.text("preferences.audio.advanced.error.deviceUnavailable")
        case .voiceProcessingUnavailable:
            return L10n.text("preferences.audio.advanced.error.voiceProcessingUnavailable")
        case .playbackRoutingUnavailable:
            return L10n.text("connectedServer.audio.error.playbackInterceptionUnavailable")
        case .playbackEngineStartFailed:
            return L10n.text("connectedServer.audio.error.playbackInterceptionUnavailable")
        case .queueCreationFailed:
            return L10n.text("preferences.audio.advanced.error.queueCreationFailed")
        case .queueStartFailed:
            return L10n.text("preferences.audio.advanced.error.queueStartFailed")
        case .queueBufferAllocationFailed:
            return L10n.text("preferences.audio.advanced.error.queueBufferAllocationFailed")
        case .engineStartFailed:
            return L10n.text("preferences.audio.advanced.error.queueStartFailed")
        }
    }
}

final class AdvancedMicrophoneAudioEngine {
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
        let configuration: AdvancedMicrophoneAudioConfiguration
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
    private let onAudioChunk: (AdvancedMicrophoneAudioChunk) -> Void
    private let diagnosticsLogger = AudioDiagnosticsLogger.shared
    private let diagnosticsScope: String

    private var engine: AVAudioEngine?
    private var currentConfiguration: AdvancedMicrophoneAudioConfiguration?
    private var gateState = GateState()
    private var expanderState = ExpanderState()
    private var limiterState = LimiterState()
    private var nextStreamID: Int32 = 1
    private var activeStreamID: Int32 = 0

    // Pre-allocated buffers reused across audio callbacks to avoid heap allocations on the real-time thread.
    private var interleavedBuffer = [Float]()
    private var selectedBuffer = [Float]()
    private var adaptedBuffer = [Float]()
    private var int16Buffer = [Int16]()
    private var callbackCount = 0
    private var lastLoggedBufferSignature = ""

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

    func start(configuration: AdvancedMicrophoneAudioConfiguration) throws -> Int32 {
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
            configuration.inputGainDB = value
            currentConfiguration = configuration
        }
    }

    // MARK: - Start / Stop

    private func startLocked(configuration: AdvancedMicrophoneAudioConfiguration) throws -> Int32 {
        stopLocked()

        guard configuration.device.inputChannels > 0 else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode
        callbackCount = 0
        lastLoggedBufferSignature = ""

        // Set the input device via the underlying Audio Unit.
        if let deviceID = Self.audioDeviceID(forUID: configuration.device.uid) {
            var devID = deviceID
            let status = AudioUnitSetProperty(
                inputNode.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
            }
        } else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Enable or disable voice processing (AEC).
        if #available(macOS 13.0, *) {
            do {
                try inputNode.setVoiceProcessingEnabled(configuration.echoCancellationEnabled)
                if configuration.echoCancellationEnabled {
                    applyMinimumOtherAudioDucking(to: inputNode)
                }
            } catch {
                if configuration.echoCancellationEnabled {
                    throw AdvancedMicrophoneAudioEngineError.voiceProcessingUnavailable
                }
                throw AdvancedMicrophoneAudioEngineError.engineStartFailed
            }
        } else {
            if configuration.echoCancellationEnabled {
                throw AdvancedMicrophoneAudioEngineError.voiceProcessingUnavailable
            }
        }

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let inputChannelCount = Int(hardwareFormat.channelCount)
        guard inputChannelCount > 0 else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }
        logDiagnostics(
            "Start. device=\(configuration.device.name) uid=\(configuration.device.uid) hwRate=\(hardwareFormat.sampleRate) hwChannels=\(inputChannelCount) commonFormat=\(describe(hardwareFormat.commonFormat)) interleaved=\(hardwareFormat.isInterleaved) aec=\(configuration.echoCancellationEnabled) preset=\(describe(configuration.preset)) targetRate=\(configuration.targetFormat.sampleRate) targetChannels=\(configuration.targetFormat.channels) tx=\(configuration.targetFormat.txIntervalMSec)"
        )

        let intervalMSec = max(configuration.targetFormat.txIntervalMSec, 20)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : (configuration.targetFormat.sampleRate > 0 ? configuration.targetFormat.sampleRate : 48_000)
        let bufferFrameCount = AVAudioFrameCount(max((sampleRate * Double(intervalMSec)) / 1000.0, 256))

        gateState = GateState()
        expanderState = ExpanderState()
        limiterState = LimiterState()

        // Capture the effective configuration with the actual device channel count and sample rate.
        let effectiveConfiguration = configuration
        // Override target sample rate to match hardware if needed.
        let effectiveTargetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: sampleRate,
            channels: configuration.targetFormat.channels,
            txIntervalMSec: configuration.targetFormat.txIntervalMSec
        )

        let streamID = withStateLock {
            // Store configuration with actual sample rate from hardware.
            var stored = effectiveConfiguration
            stored = AdvancedMicrophoneAudioConfiguration(
                device: InputAudioDeviceInfo(
                    uid: configuration.device.uid,
                    name: configuration.device.name,
                    inputChannels: inputChannelCount,
                    nominalSampleRate: sampleRate
                ),
                preset: configuration.preset,
                inputGainDB: configuration.inputGainDB,
                echoCancellationEnabled: configuration.echoCancellationEnabled,
                dynamicProcessorEnabled: configuration.dynamicProcessorEnabled,
                dynamicProcessorMode: configuration.dynamicProcessorMode,
                gateThresholdDB: configuration.gateThresholdDB,
                gateAttackMilliseconds: configuration.gateAttackMilliseconds,
                gateHoldMilliseconds: configuration.gateHoldMilliseconds,
                gateReleaseMilliseconds: configuration.gateReleaseMilliseconds,
                expanderThresholdDB: configuration.expanderThresholdDB,
                expanderRatio: configuration.expanderRatio,
                expanderAttackMilliseconds: configuration.expanderAttackMilliseconds,
                expanderReleaseMilliseconds: configuration.expanderReleaseMilliseconds,
                limiterEnabled: configuration.limiterEnabled,
                limiterMode: configuration.limiterMode,
                limiterPreset: configuration.limiterPreset,
                limiterThresholdDB: configuration.limiterThresholdDB,
                limiterReleaseMilliseconds: configuration.limiterReleaseMilliseconds,
                targetFormat: effectiveTargetFormat
            )
            currentConfiguration = stored
            engine = newEngine
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
        } catch {
            inputNode.removeTap(onBus: 0)
            _ = clearState(for: newEngine)
            throw AdvancedMicrophoneAudioEngineError.engineStartFailed
        }

        return streamID
    }

    private func stopLocked() {
        let stoppedEngine = clearState(for: nil)

        if let stoppedEngine {
            stoppedEngine.inputNode.removeTap(onBus: 0)
            stoppedEngine.stop()
            logDiagnostics("Stop.")
        }
    }

    // MARK: - Audio Processing

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

        // Single lock acquisition: snapshot config + DSP state, then release.
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

        // Interleave into pre-allocated buffer (no heap allocation).
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
            logDiagnostics("Drop buffer. unsupportedFormat commonFormat=\(describe(buffer.format.commonFormat)) interleaved=\(buffer.format.isInterleaved) channels=\(availableChannels) frames=\(frameCount)")
            return
        }

        callbackCount += 1
        let selection = resolvedSelection(for: configuration.preset, availableChannels: availableChannels)
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

        // Select channels into pre-allocated buffer.
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

        applyInputGainInPlace(to: &selectedBuffer, count: selectedCount, gainDB: configuration.inputGainDB)

        if configuration.dynamicProcessorEnabled {
            switch configuration.dynamicProcessorMode {
            case .gate:
                applyGate(
                    to: &selectedBuffer,
                    count: selectedCount,
                    channels: selection.outputChannels,
                    sampleRate: configuration.targetFormat.sampleRate,
                    thresholdDB: configuration.gateThresholdDB,
                    attackMilliseconds: configuration.gateAttackMilliseconds,
                    holdMilliseconds: configuration.gateHoldMilliseconds,
                    releaseMilliseconds: configuration.gateReleaseMilliseconds,
                    state: &localGateState
                )
            case .expander:
                applyExpander(
                    to: &selectedBuffer,
                    count: selectedCount,
                    channels: selection.outputChannels,
                    sampleRate: configuration.targetFormat.sampleRate,
                    thresholdDB: configuration.expanderThresholdDB,
                    ratio: configuration.expanderRatio,
                    attackMilliseconds: configuration.expanderAttackMilliseconds,
                    releaseMilliseconds: configuration.expanderReleaseMilliseconds,
                    state: &localExpanderState
                )
            }
        }

        if configuration.limiterEnabled {
            applyLimiter(
                to: &selectedBuffer,
                count: selectedCount,
                channels: selection.outputChannels,
                sampleRate: configuration.targetFormat.sampleRate,
                mode: configuration.limiterMode,
                preset: configuration.limiterPreset,
                thresholdDB: configuration.limiterThresholdDB,
                releaseMilliseconds: configuration.limiterReleaseMilliseconds,
                state: &localLimiterState
            )
        }

        // Adapt channel count in-place.
        let targetChannels = max(configuration.targetFormat.channels, 1)
        let adaptedCount: Int
        if selection.outputChannels == targetChannels {
            // No adaptation needed — use selectedBuffer directly.
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

        if shouldLogCallbackStats(callbackCount) {
            logDiagnostics(
                "Buffer #\(callbackCount) inputPeak=\(formatDecibels(inputStats.peak)) inputRMS=\(formatDecibels(inputStats.rms)) outputPeak=\(formatDecibels(outputStats.peak)) outputRMS=\(formatDecibels(outputStats.rms)) selectedChannels=\(selection.outputChannels) targetChannels=\(targetChannels) samples=\(adaptedCount / targetChannels)"
            )
        }

        // Convert to Int16 into pre-allocated buffer.
        if int16Buffer.count < adaptedCount {
            int16Buffer = [Int16](repeating: 0, count: adaptedCount)
        }
        for i in 0..<adaptedCount {
            int16Buffer[i] = floatToPCM16(sourceForConversion[i])
        }

        let payload = int16Buffer.withUnsafeBufferPointer { buf in
            Data(bytes: buf.baseAddress!, count: adaptedCount * MemoryLayout<Int16>.size)
        }

        let chunk = AdvancedMicrophoneAudioChunk(
            streamID: snapshot.streamID,
            sampleRate: Int32(configuration.targetFormat.sampleRate.rounded()),
            channels: Int32(targetChannels),
            sampleCount: Int32(adaptedCount / targetChannels),
            data: payload
        )

        // Write back DSP state in a single lock acquisition.
        withStateLock {
            gateState = localGateState
            expanderState = localExpanderState
            limiterState = localLimiterState
        }

        onAudioChunk(chunk)
    }

    // MARK: - State Management

    private func clearState(for engineToMatch: AVAudioEngine?) -> AVAudioEngine? {
        withStateLock {
            let currentEngine = engine
            if let engineToMatch, currentEngine !== engineToMatch {
                return nil
            }

            engine = nil
            currentConfiguration = nil
            gateState = GateState()
            expanderState = ExpanderState()
            limiterState = LimiterState()
            activeStreamID = 0
            return currentEngine
        }
    }

    // MARK: - Device Resolution

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

    // MARK: - DSP (unchanged)

    private func applyInputGainInPlace(to samples: inout [Float], count: Int, gainDB: Double) {
        guard count > 0, gainDB != 0 else {
            return
        }

        let gain = Float(pow(10, gainDB / 20))
        for index in 0..<count {
            samples[index] *= gain
        }
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
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

    private func logDiagnostics(_ message: String) {
        diagnosticsLogger.log(diagnosticsScope, message)
    }

    private func shouldLogCallbackStats(_ count: Int) -> Bool {
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

    private func formatDecibels(_ value: Float) -> String {
        guard value > 0 else {
            return "-inf dBFS"
        }
        let decibels = 20 * log10(Double(value))
        return String(format: "%.1f dBFS", decibels)
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
