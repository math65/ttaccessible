//
//  AdvancedMicrophoneAudioEngine.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
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
    let samples: [Int16]
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

    // Standalone AUHAL for non-default devices.
    private var standaloneAUHAL: AudioUnit?
    private var auhalChannelCount: Int = 0
    private var auhalSampleRate: Double = 0
    private var auhalBufferFrameCount: UInt32 = 0

    // Pre-allocated render buffers for AUHAL callback.
    private var auhalRenderBufferPtr: UnsafeMutablePointer<AudioBufferList>?
    private var auhalRenderDataPtrs: [UnsafeMutablePointer<Float>] = []

    // Accumulation buffer for AUHAL (to batch ~40ms worth of frames).
    private var auhalAccumBuffer: [Float] = []
    private var auhalAccumWriteIndex: Int = 0
    private var auhalAccumTargetFrames: Int = 0

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
            engine != nil || standaloneAUHAL != nil
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

        guard let deviceID = Self.audioDeviceID(forUID: configuration.device.uid) else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        let defaultDeviceID = Self.systemDefaultInputDeviceID()
        let isSystemDefault = (deviceID == defaultDeviceID)

        if isSystemDefault {
            return try startWithAVAudioEngine(configuration: configuration, deviceID: deviceID)
        } else {
            return try startWithStandaloneAUHAL(configuration: configuration, deviceID: deviceID)
        }
    }

    // MARK: - AVAudioEngine Path (system default device)

    private func startWithAVAudioEngine(configuration: AdvancedMicrophoneAudioConfiguration, deviceID: AudioDeviceID) throws -> Int32 {
        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode

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

    // MARK: - Standalone AUHAL Path (non-default devices)

    private func startWithStandaloneAUHAL(configuration: AdvancedMicrophoneAudioConfiguration, deviceID: AudioDeviceID) throws -> Int32 {
        // Create AUHAL AudioComponent.
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        var audioUnit: AudioUnit?
        guard AudioComponentInstanceNew(component, &audioUnit) == noErr, let au = audioUnit else {
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Enable input IO on element 1.
        var enableIO: UInt32 = 1
        var status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Disable output IO on element 0.
        var disableIO: UInt32 = 0
        status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &disableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Set the device.
        var devID = deviceID
        status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Read native format from input scope element 1.
        var nativeASBD = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &nativeASBD,
            &asbdSize
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        let channelCount = max(Int(nativeASBD.mChannelsPerFrame), Int(configuration.device.inputChannels))
        let sampleRate = nativeASBD.mSampleRate > 0 ? nativeASBD.mSampleRate : (configuration.targetFormat.sampleRate > 0 ? configuration.targetFormat.sampleRate : 48_000)

        // Set Float32 non-interleaved output format on output scope element 1.
        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        status = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &outputASBD,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(au)
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Set max frames per slice.
        var maxFrames: UInt32 = 4096
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxFrames,
            UInt32(MemoryLayout<UInt32>.size)
        )

        // Pre-allocate render buffers.
        let renderBufferSize = Int(maxFrames)
        let ablSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size * (channelCount - 1)
        let ablPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        let rawPtr = UnsafeMutableRawPointer(ablPtr)
        memset(rawPtr, 0, ablSize)
        ablPtr.pointee.mNumberBuffers = UInt32(channelCount)
        var dataPtrs: [UnsafeMutablePointer<Float>] = []
        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        for i in 0..<channelCount {
            let dataPtr = UnsafeMutablePointer<Float>.allocate(capacity: renderBufferSize)
            dataPtr.initialize(repeating: 0, count: renderBufferSize)
            dataPtrs.append(dataPtr)
            buffers[i].mNumberChannels = 1
            buffers[i].mDataByteSize = UInt32(renderBufferSize * MemoryLayout<Float>.size)
            buffers[i].mData = UnsafeMutableRawPointer(dataPtr)
        }

        // Compute accumulation target (~40ms worth of frames).
        let tapIntervalMSec = min(Int(configuration.targetFormat.txIntervalMSec), 40)
        let accumTargetFrames = max(Int((sampleRate * Double(tapIntervalMSec)) / 1000.0), 256)
        let accumBufferSize = accumTargetFrames * channelCount * 2

        let effectiveTargetFormat = AdvancedMicrophoneAudioTargetFormat(
            sampleRate: sampleRate,
            channels: configuration.targetFormat.channels,
            txIntervalMSec: configuration.targetFormat.txIntervalMSec
        )

        // Store state before setting callback.
        let streamID = withStateLock {
            let stored = AdvancedMicrophoneAudioConfiguration(
                device: InputAudioDeviceInfo(
                    uid: configuration.device.uid,
                    name: configuration.device.name,
                    inputChannels: channelCount,
                    nominalSampleRate: sampleRate
                ),
                preset: configuration.preset,
                inputGainDB: configuration.inputGainDB,
                targetFormat: effectiveTargetFormat,
                echoCancellationEnabled: configuration.echoCancellationEnabled
            )
            currentConfiguration = stored
            standaloneAUHAL = au
            auhalChannelCount = channelCount
            auhalSampleRate = sampleRate
            auhalBufferFrameCount = maxFrames
            auhalRenderBufferPtr = ablPtr
            auhalRenderDataPtrs = dataPtrs
            auhalAccumBuffer = [Float](repeating: 0, count: accumBufferSize)
            auhalAccumWriteIndex = 0
            auhalAccumTargetFrames = accumTargetFrames
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

        // Set input callback.
        var callbackStruct = AURenderCallbackStruct(
            inputProc: auhalInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            freeAUHALRenderBuffers()
            AudioComponentInstanceDispose(au)
            withStateLock {
                standaloneAUHAL = nil
                currentConfiguration = nil
                activeStreamID = 0
            }
            throw AdvancedMicrophoneAudioEngineError.deviceUnavailable
        }

        // Initialize and start.
        status = AudioUnitInitialize(au)
        guard status == noErr else {
            freeAUHALRenderBuffers()
            AudioComponentInstanceDispose(au)
            withStateLock {
                standaloneAUHAL = nil
                currentConfiguration = nil
                activeStreamID = 0
            }
            throw AdvancedMicrophoneAudioEngineError.engineStartFailed
        }

        status = AudioOutputUnitStart(au)
        guard status == noErr else {
            AudioUnitUninitialize(au)
            freeAUHALRenderBuffers()
            AudioComponentInstanceDispose(au)
            withStateLock {
                standaloneAUHAL = nil
                currentConfiguration = nil
                activeStreamID = 0
            }
            throw AdvancedMicrophoneAudioEngineError.engineStartFailed
        }

        return streamID
    }

    private func stopLocked() {
        echoCanceller = nil

        // Stop AVAudioEngine path.
        let stoppedEngine = clearState(for: nil)
        if let stoppedEngine {
            if let mixer = mixerNode {
                mixer.removeTap(onBus: 0)
            }
            stoppedEngine.stop()
        }

        // Stop standalone AUHAL path.
        let stoppedAUHAL: AudioUnit? = withStateLock {
            let au = standaloneAUHAL
            standaloneAUHAL = nil
            if au == nil {
                currentConfiguration = nil
                activeStreamID = 0
            }
            return au
        }

        if let au = stoppedAUHAL {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            freeAUHALRenderBuffers()
            withStateLock {
                currentConfiguration = nil
                activeStreamID = 0
            }
        }
    }

    // MARK: - AUHAL Render Buffers

    private func freeAUHALRenderBuffers() {
        for ptr in auhalRenderDataPtrs {
            ptr.deallocate()
        }
        auhalRenderDataPtrs.removeAll()
        auhalRenderBufferPtr?.deallocate()
        auhalRenderBufferPtr = nil
    }

    // MARK: - AUHAL Input Callback Processing

    func handleAUHALInput(
        _ audioUnit: AudioUnit,
        _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
        _ inBusNumber: UInt32,
        _ inNumberFrames: UInt32
    ) {
        guard let ablPtr = auhalRenderBufferPtr else { return }
        let channelCount = auhalChannelCount
        guard channelCount > 0 else { return }

        // Reset buffer sizes for this render call.
        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        for i in 0..<channelCount {
            buffers[i].mDataByteSize = UInt32(Int(inNumberFrames) * MemoryLayout<Float>.size)
        }

        let renderStatus = AudioUnitRender(audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ablPtr)
        guard renderStatus == noErr else { return }

        let frameCount = Int(inNumberFrames)

        // Interleave into accumulation buffer.
        let neededAccum = auhalAccumWriteIndex + frameCount * channelCount
        if neededAccum > auhalAccumBuffer.count {
            // Should not happen with proper pre-allocation; if it does, process what we have.
            if auhalAccumWriteIndex > 0 {
                processAccumulatedAUHALFrames(channelCount: channelCount)
            }
            auhalAccumWriteIndex = 0
        }

        // Write interleaved frames to accumulation buffer.
        for frame in 0..<frameCount {
            for ch in 0..<channelCount {
                let srcPtr = auhalRenderDataPtrs[ch]
                auhalAccumBuffer[auhalAccumWriteIndex] = srcPtr[frame]
                auhalAccumWriteIndex += 1
            }
        }

        // Check if we've accumulated enough frames.
        let accumulatedFrames = auhalAccumWriteIndex / channelCount
        if accumulatedFrames >= auhalAccumTargetFrames {
            processAccumulatedAUHALFrames(channelCount: channelCount)
            auhalAccumWriteIndex = 0
        }
    }

    private func processAccumulatedAUHALFrames(channelCount: Int) {
        let totalSamples = auhalAccumWriteIndex
        guard totalSamples > 0, channelCount > 0 else { return }
        let frameCount = totalSamples / channelCount

        // Use the interleavedBuffer for processing.
        if interleavedBuffer.count < totalSamples {
            interleavedBuffer = [Float](repeating: 0, count: totalSamples)
        }
        for i in 0..<totalSamples {
            interleavedBuffer[i] = auhalAccumBuffer[i]
        }

        processInterleavedAudio(interleavedData: &interleavedBuffer, frameCount: frameCount, availableChannels: channelCount)
    }

    // MARK: - AVAudioEngine Audio Processing

    private func handleAVAudioBuffer(_ buffer: AVAudioPCMBuffer, channelCount: Int) {
        let inputChannelCount = channelCount
        guard inputChannelCount > 0 else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let availableChannels = min(inputChannelCount, Int(buffer.format.channelCount))
        guard availableChannels > 0 else { return }

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

        processInterleavedAudio(interleavedData: &interleavedBuffer, frameCount: frameCount, availableChannels: availableChannels)
    }

    // MARK: - Shared Audio Processing

    private func processInterleavedAudio(interleavedData: inout [Float], frameCount: Int, availableChannels: Int) {
        // Snapshot config — single lock acquisition.
        guard let snapshot: StateSnapshot = withStateLock({
            guard engine != nil || standaloneAUHAL != nil,
                  let configuration = currentConfiguration,
                  activeStreamID > 0 else {
                return nil
            }
            return StateSnapshot(configuration: configuration, streamID: activeStreamID)
        }) else {
            return
        }

        let configuration = snapshot.configuration

        let selection = resolvedSelection(for: configuration.preset, availableChannels: availableChannels, physicalChannels: configuration.device.inputChannels)

        // Select channels.
        let selectedCount = frameCount * selection.outputChannels
        if selectedBuffer.count < selectedCount {
            selectedBuffer = [Float](repeating: 0, count: selectedCount)
        }
        selectChannelsInPlace(
            from: &interleavedData,
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
        let samples: [Int16]
        if let aec = echoCanceller {
            let processed = int16Buffer.withUnsafeBufferPointer { buf in
                guard let baseAddress = buf.baseAddress else { return [Int16]() }
                return aec.processCapture(baseAddress, count: adaptedCount)
            }
            if processed.isEmpty {
                // AEC hasn't accumulated a full 10ms frame yet; skip this chunk.
                return
            }
            samples = processed
        } else {
            samples = Array(int16Buffer.prefix(adaptedCount))
        }

        let chunk = AdvancedMicrophoneAudioChunk(
            streamID: snapshot.streamID,
            sampleRate: Int32(configuration.targetFormat.sampleRate.rounded()),
            channels: Int32(targetChannels),
            sampleCount: Int32(adaptedCount / targetChannels),
            samples: samples
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
            if standaloneAUHAL == nil {
                currentConfiguration = nil
                activeStreamID = 0
            }
            mixerNode = nil
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

    private func resolvedSelection(for preset: InputChannelPreset, availableChannels: Int, physicalChannels: Int) -> ResolvedSelection {
        switch preset {
        case .auto:
            if physicalChannels >= 2 { return .stereoPair(firstIndex: 0, secondIndex: 1) }
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

// MARK: - AUHAL C Callback

private func auhalInputCallback(
    _ inRefCon: UnsafeMutableRawPointer,
    _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
    _ inBusNumber: UInt32,
    _ inNumberFrames: UInt32,
    _ ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<AdvancedMicrophoneAudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    engine.handleAUHALInput(
        // We need the AudioUnit to call AudioUnitRender. Get it from the engine.
        engine.standaloneAUHALForCallback!,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames
    )
    return noErr
}

// Extension to expose AUHAL for callback (avoids lock in hot path).
extension AdvancedMicrophoneAudioEngine {
    var standaloneAUHALForCallback: AudioUnit? {
        standaloneAUHAL
    }
}
