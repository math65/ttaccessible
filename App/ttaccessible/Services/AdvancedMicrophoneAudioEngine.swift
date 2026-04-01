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
    let targetFormat: AdvancedMicrophoneAudioTargetFormat
    var echoCancellationEnabled: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.device == rhs.device &&
        lhs.preset == rhs.preset &&
        lhs.inputGainDB == rhs.inputGainDB &&
        lhs.targetFormat == rhs.targetFormat &&
        lhs.echoCancellationEnabled == rhs.echoCancellationEnabled
    }
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

    private struct StateSnapshot {
        let configuration: AdvancedMicrophoneAudioConfiguration
        let streamID: Int32
    }

    private let stateLock = NSLock()
    private let onAudioChunk: (AdvancedMicrophoneAudioChunk) -> Void

    private var engine: AVAudioEngine?
    private var currentConfiguration: AdvancedMicrophoneAudioConfiguration?
    private var nextStreamID: Int32 = 1
    private var activeStreamID: Int32 = 0

    /// Mixer node used as the stable tap point.
    private var mixerNode: AVAudioMixerNode?

    // Pre-allocated buffers reused across audio callbacks to avoid heap allocations on the real-time thread.
    private var interleavedBuffer = [Float]()
    private var selectedBuffer = [Float]()
    private var adaptedBuffer = [Float]()
    private var int16Buffer = [Int16]()

    /// Echo canceller instance, created when AEC is enabled.
    var echoCanceller: EchoCanceller?
    init(
        onAudioChunk: @escaping (AdvancedMicrophoneAudioChunk) -> Void
    ) {
        self.onAudioChunk = onAudioChunk
    }

    var isRunning: Bool {
        withStateLock {
            engine != nil
        }
    }

    var effectiveSampleRate: Double? {
        withStateLock {
            currentConfiguration?.targetFormat.sampleRate
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
        // Set the input device via the underlying Audio Unit.
        if let deviceID = Self.audioDeviceID(forUID: configuration.device.uid) {
            let defaultDeviceID = Self.systemDefaultInputDeviceID()
            if deviceID != defaultDeviceID {
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
            }
        } else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Request all input channels from the device (multi-stream USB interfaces).
        let deviceInputChannels = UInt32(configuration.device.inputChannels)
        if deviceInputChannels > 1, let au = inputNode.audioUnit {
            var asbd = AudioStreamBasicDescription()
            var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let getStatus = AudioUnitGetProperty(
                au,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &asbd,
                &asbdSize
            )
            if getStatus == noErr, asbd.mChannelsPerFrame < deviceInputChannels {
                asbd.mChannelsPerFrame = deviceInputChannels
                AudioUnitSetProperty(
                    au,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Output,
                    1,
                    &asbd,
                    asbdSize
                )
            }
        }

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let inputChannelCount = Int(hardwareFormat.channelCount)
        guard inputChannelCount > 0 else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : (configuration.targetFormat.sampleRate > 0 ? configuration.targetFormat.sampleRate : 48_000)
        let tapIntervalMSec = min(Int(configuration.targetFormat.txIntervalMSec), 40)
        let bufferFrameCount = AVAudioFrameCount(max((sampleRate * Double(tapIntervalMSec)) / 1000.0, 256))

        // Override target sample rate to match hardware if needed.
        let effectiveTargetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: sampleRate,
            channels: configuration.targetFormat.channels,
            txIntervalMSec: configuration.targetFormat.txIntervalMSec
        )

        // Build the audio graph: inputNode → mixerNode → sinkNode
        // The tap is installed on the mixer node to receive audio.

        let mixer = AVAudioMixerNode()
        newEngine.attach(mixer)

        let sinkNode = AVAudioSinkNode { _, _, _ -> OSStatus in
            return noErr
        }
        newEngine.attach(sinkNode)

        let connectionFormat = hardwareFormat
        newEngine.connect(inputNode, to: mixer, format: connectionFormat)
        newEngine.connect(mixer, to: sinkNode, format: connectionFormat)

        // Store stream ID and configuration.
        let streamID = withStateLock {
            let stored = AdvancedMicrophoneAudioConfiguration(
                device: InputAudioDeviceInfo(
                    uid: configuration.device.uid,
                    name: configuration.device.name,
                    inputChannels: inputChannelCount,
                    nominalSampleRate: sampleRate
                ),
                preset: configuration.preset,
                inputGainDB: configuration.inputGainDB,
                targetFormat: effectiveTargetFormat,
                echoCancellationEnabled: configuration.echoCancellationEnabled
            )
            currentConfiguration = stored
            engine = newEngine
            mixerNode = mixer
            activeStreamID = nextStreamID
            nextStreamID = nextStreamID == Int32.max ? 1 : nextStreamID + 1
            return activeStreamID
        }

        // Create WebRTC AEC3 echo canceller if enabled.
        if configuration.echoCancellationEnabled {
            let aecConfig = EchoCanceller.Configuration(
                sampleRate: Int(sampleRate),
                channels: max(configuration.targetFormat.channels, 1)
            )
            echoCanceller = EchoCanceller(configuration: aecConfig)
        } else {
            echoCanceller = nil
        }

        // Install tap on the mixer node.
        mixer.installTap(onBus: 0, bufferSize: bufferFrameCount, format: connectionFormat) { [weak self] buffer, _ in
            self?.handleAVAudioBuffer(buffer, channelCount: Int(connectionFormat.channelCount))
        }

        // Start engine.
        do {
            try newEngine.start()
        } catch {
            mixer.removeTap(onBus: 0)
            _ = clearState(for: newEngine)
            throw AdvancedMicrophoneAudioEngineError.engineStartFailed
        }

        return streamID
    }

    private func stopLocked() {
        let stoppedEngine = clearState(for: nil)
        echoCanceller = nil

        if let stoppedEngine {
            // Remove tap from mixer node.
            if let mixer = mixerNode {
                mixer.removeTap(onBus: 0)
            }
            stoppedEngine.stop()
        }
    }

    // MARK: - Audio Processing

    private func handleAVAudioBuffer(_ buffer: AVAudioPCMBuffer, channelCount: Int) {
        let inputChannelCount = channelCount
        guard inputChannelCount > 0 else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let availableChannels = min(inputChannelCount, Int(buffer.format.channelCount))
        guard availableChannels > 0 else { return }

        // Snapshot config — single lock acquisition.
        guard let snapshot: StateSnapshot = withStateLock({
            guard engine != nil,
                  let configuration = currentConfiguration,
                  activeStreamID > 0 else {
                return nil
            }
            return StateSnapshot(configuration: configuration, streamID: activeStreamID)
        }) else {
            return
        }

        let configuration = snapshot.configuration

        // Interleave into pre-allocated buffer.
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
            return
        }

        let selection = resolvedSelection(for: configuration.preset, availableChannels: availableChannels)

        // Select channels.
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

        // Apply input gain (simple multiply, no DSP state needed).
        applyInputGainInPlace(to: &selectedBuffer, count: selectedCount, gainDB: configuration.inputGainDB)

        // Adapt channel count.
        let targetChannels = max(configuration.targetFormat.channels, 1)
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

        guard adaptedCount > 0 else { return }

        let sourceForConversion = (selection.outputChannels == targetChannels) ? selectedBuffer : adaptedBuffer

        // Convert to Int16.
        if int16Buffer.count < adaptedCount {
            int16Buffer = [Int16](repeating: 0, count: adaptedCount)
        }
        for i in 0..<adaptedCount {
            int16Buffer[i] = floatToPCM16(sourceForConversion[i])
        }

        // Apply WebRTC AEC3 on Int16 PCM data.
        let payload: Data
        if let aec = echoCanceller {
            let processed = int16Buffer.withUnsafeBufferPointer { buf in
                aec.processCapture(buf.baseAddress!, count: adaptedCount)
            }
            if processed.isEmpty {
                // AEC hasn't accumulated a full 10ms frame yet; skip this chunk.
                return
            }
            payload = processed.withUnsafeBufferPointer { buf in
                Data(bytes: buf.baseAddress!, count: processed.count * MemoryLayout<Int16>.size)
            }
        } else {
            payload = int16Buffer.withUnsafeBufferPointer { buf in
                Data(bytes: buf.baseAddress!, count: adaptedCount * MemoryLayout<Int16>.size)
            }
        }

        let chunk = AdvancedMicrophoneAudioChunk(
            streamID: snapshot.streamID,
            sampleRate: Int32(configuration.targetFormat.sampleRate.rounded()),
            channels: Int32(targetChannels),
            sampleCount: Int32(adaptedCount / targetChannels),
            data: payload
        )

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
            mixerNode = nil
            activeStreamID = 0
            return currentEngine
        }
    }

    // MARK: - Device Resolution

    private static func systemDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
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

    // MARK: - Gain

    private func applyInputGainInPlace(to samples: inout [Float], count: Int, gainDB: Double) {
        guard count > 0, gainDB != 0 else { return }
        let gain = Float(pow(10, gainDB / 20))
        for index in 0..<count {
            samples[index] *= gain
        }
    }

    // MARK: - Helpers

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
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
                guard let source = audioBuffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return false }
                let sampleCount = frameCount * availableChannels
                for index in 0..<sampleCount { output[index] = source[index] }
                return true
            }
            guard let channels = buffer.floatChannelData else { return false }
            for frame in 0..<frameCount {
                for channel in 0..<availableChannels {
                    output[(frame * availableChannels) + channel] = channels[channel][frame]
                }
            }
            return true

        case .pcmFormatInt16:
            let scale = Float(Int16.max)
            if format.isInterleaved {
                guard let source = audioBuffers.first?.mData?.assumingMemoryBound(to: Int16.self) else { return false }
                let sampleCount = frameCount * availableChannels
                for index in 0..<sampleCount { output[index] = Float(source[index]) / scale }
                return true
            }
            guard let channels = buffer.int16ChannelData else { return false }
            for frame in 0..<frameCount {
                for channel in 0..<availableChannels {
                    output[(frame * availableChannels) + channel] = Float(channels[channel][frame]) / scale
                }
            }
            return true

        case .pcmFormatInt32:
            let scale = Float(Int32.max)
            if format.isInterleaved {
                guard let source = audioBuffers.first?.mData?.assumingMemoryBound(to: Int32.self) else { return false }
                let sampleCount = frameCount * availableChannels
                for index in 0..<sampleCount { output[index] = Float(source[index]) / scale }
                return true
            }
            guard let channels = buffer.int32ChannelData else { return false }
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
            if availableChannels >= 2 { return .stereoPair(firstIndex: 0, secondIndex: 1) }
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
        if clamped >= 1 { return Int16.max }
        if clamped <= -1 { return Int16.min }
        return Int16((clamped * 32767).rounded())
    }
}
