//
//  DeviceInputCaptureBackend.swift
//  ttaccessible
//

import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Captures a CoreAudio input device via a standalone AUHAL (mirrors
/// AdvancedMicrophoneAudioEngine's non-default-device path) and feeds
/// 48 kHz stereo Int16 into the device-stream ring. This is the original
/// "Stream Audio Device" capture, extracted so process-tap / SCK backends can
/// share the ring + loopback server.
final class DeviceInputCaptureBackend: DeviceStreamCaptureBackend {

    private let device: InputAudioDeviceInfo
    /// Which of the device's channels to broadcast (mirrors the microphone's
    /// InputChannelPreset). Resolved into concrete indices once the AUHAL
    /// reports the real channel count — see `resolveChannelSelection`.
    private let channelPreset: InputChannelPreset
    private let ring: AudioDeviceStreamSource.PCMRing

    // Capture state (mutated on start/stop only; callback reads via unmanaged self).
    private var audioUnit: AudioUnit?
    private var captureBufferList: UnsafeMutableRawPointer?
    private var captureBufferCapacity: Int = 0
    private var captureSampleRate: Double = 48_000
    private var captureChannels: Int = 2
    /// Resolved source channel indices for the broadcast stereo pair (equal for a
    /// single-channel selection), plus whether the two are summed to mono.
    /// Written on start only; read by the RT callback.
    private var captureLeftIndex: Int = 0
    private var captureRightIndex: Int = 1
    private var captureSumsToMono = false
    /// Pre-allocated stereo scratch reused by the RT input callback (sized to the
    /// AUHAL's max frames), so `handleInput` doesn't heap-allocate per callback.
    private var captureStereoScratch = [Int16]()
    /// Pre-allocated resample target reused by the RT input callback (sized to the
    /// worst-case 48 kHz output frame count), so resampling doesn't allocate either.
    private var captureResampleScratch = [Int16]()
    /// When true the capture callback writes silence instead of the live audio —
    /// used to "pause" a device stream without pausing the SDK (which desyncs a
    /// live loopback). Plain Bool: a one-buffer-late transition is inaudible.
    private var isMuted = false

    init(
        device: InputAudioDeviceInfo,
        channelPreset: InputChannelPreset = .auto,
        ring: AudioDeviceStreamSource.PCMRing
    ) {
        self.device = device
        self.channelPreset = channelPreset
        self.ring = ring
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    func start() throws {
        guard let deviceID = InputAudioDeviceResolver.audioDeviceID(forUID: device.uid) else {
            throw AudioDeviceStreamSourceError.deviceUnavailable
        }
        try startCapture(deviceID: deviceID)
    }

    func stop() {
        stopCapture()
    }

    private func startCapture(deviceID: AudioDeviceID) throws {
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw AudioDeviceStreamSourceError.captureStartFailed
        }
        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let au = unit else {
            throw AudioDeviceStreamSourceError.captureStartFailed
        }

        func fail() -> AudioDeviceStreamSourceError {
            AudioComponentInstanceDispose(au)
            return .captureStartFailed
        }

        var enableIO: UInt32 = 1
        guard AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                                   &enableIO, UInt32(MemoryLayout<UInt32>.size)) == noErr else { throw fail() }
        var disableIO: UInt32 = 0
        guard AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                                   &disableIO, UInt32(MemoryLayout<UInt32>.size)) == noErr else { throw fail() }
        var devID = deviceID
        guard AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &devID, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else { throw fail() }

        var nativeASBD = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitGetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                                   &nativeASBD, &asbdSize) == noErr else { throw fail() }

        let channelCount = max(Int(nativeASBD.mChannelsPerFrame), 1)
        let sampleRate = nativeASBD.mSampleRate > 0 ? nativeASBD.mSampleRate : 48_000

        // Int16 interleaved at the device's native rate (AUHAL converts format,
        // never rate — resampling to 48 kHz happens in the input callback).
        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Int16>.size * channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Int16>.size * channelCount),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Int16>.size * 8),
            mReserved: 0
        )
        guard AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                   &outputASBD, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr else { throw fail() }

        var maxFrames: UInt32 = 4096
        AudioUnitSetProperty(au, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                             &maxFrames, UInt32(MemoryLayout<UInt32>.size))

        // Preallocate the render target (single interleaved buffer).
        let byteCapacity = Int(maxFrames) * channelCount * MemoryLayout<Int16>.size
        let ablSize = MemoryLayout<AudioBufferList>.size
        let ablRawPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        ablRawPtr.initializeMemory(as: UInt8.self, repeating: 0, count: ablSize)
        let dataPtr = UnsafeMutableRawPointer.allocate(byteCount: byteCapacity, alignment: MemoryLayout<Int16>.alignment)
        let ablPtr = ablRawPtr.assumingMemoryBound(to: AudioBufferList.self)
        ablPtr.pointee.mNumberBuffers = 1
        ablPtr.pointee.mBuffers.mNumberChannels = UInt32(channelCount)
        ablPtr.pointee.mBuffers.mDataByteSize = UInt32(byteCapacity)
        ablPtr.pointee.mBuffers.mData = dataPtr

        captureBufferList = ablRawPtr
        captureBufferCapacity = byteCapacity
        captureSampleRate = sampleRate
        captureChannels = channelCount
        resolveChannelSelection(channelCount: channelCount)
        captureStereoScratch = [Int16](repeating: 0, count: Int(maxFrames) * 2)
        // Worst case the device runs below 48 kHz, so resampling grows the frame
        // count; size the scratch for that ceiling (+ margin) once, up front.
        let worstCaseOutputFrames = Int(
            (Double(maxFrames) * Double(AudioDeviceStreamSource.outputSampleRate) / max(sampleRate, 1)).rounded(.up)
        ) + 8
        captureResampleScratch = [Int16](repeating: 0, count: worstCaseOutputFrames * AudioDeviceStreamSource.outputChannels)

        var callbackStruct = AURenderCallbackStruct(
            inputProc: deviceStreamInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        guard AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                   &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr else {
            freeCaptureBuffers()
            throw fail()
        }
        guard AudioUnitInitialize(au) == noErr else {
            freeCaptureBuffers()
            throw fail()
        }
        guard AudioOutputUnitStart(au) == noErr else {
            AudioUnitUninitialize(au)
            freeCaptureBuffers()
            throw fail()
        }
        audioUnit = au
        AudioLogger.log("device stream: capture started device=%@ rate=%d ch=%d broadcasting=%d/%d%@",
                        device.name, Int(sampleRate.rounded()), channelCount,
                        captureLeftIndex + 1, captureRightIndex + 1,
                        captureSumsToMono ? " summed" : "")
    }

    /// Map the user's channel preset onto concrete source indices for this
    /// device's actual channel count. Out-of-range selections (device swapped
    /// for one with fewer inputs) clamp instead of reading past the buffer.
    private func resolveChannelSelection(channelCount: Int) {
        let lastIndex = max(channelCount - 1, 0)
        func clamp(_ channel: Int) -> Int { min(max(channel - 1, 0), lastIndex) }

        switch channelPreset {
        case .auto:
            captureLeftIndex = 0
            captureRightIndex = channelCount >= 2 ? 1 : 0
            captureSumsToMono = false
        case .mono(let channel):
            // Single channel: the same source sample feeds both sides, so the
            // broadcast is centered rather than hard-panned to one side.
            let index = clamp(channel)
            captureLeftIndex = index
            captureRightIndex = index
            captureSumsToMono = false
        case .stereoPair(let first, let second):
            captureLeftIndex = clamp(first)
            captureRightIndex = clamp(second)
            captureSumsToMono = false
        case .monoMix(let first, let second):
            captureLeftIndex = clamp(first)
            captureRightIndex = clamp(second)
            captureSumsToMono = true
        }
    }

    private func stopCapture() {
        guard let au = audioUnit else { return }
        audioUnit = nil
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        freeCaptureBuffers()
    }

    private func freeCaptureBuffers() {
        if let ablRawPtr = captureBufferList {
            let ablPtr = ablRawPtr.assumingMemoryBound(to: AudioBufferList.self)
            ablPtr.pointee.mBuffers.mData?.deallocate()
            ablRawPtr.deallocate()
            captureBufferList = nil
        }
        captureBufferCapacity = 0
    }

    /// Called from the AUHAL input callback: render, map to stereo, resample to
    /// 48 kHz and push into the ring.
    fileprivate func handleInput(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inBusNumber: UInt32,
        inNumberFrames: UInt32
    ) {
        guard let au = audioUnit, let ablRawPtr = captureBufferList else { return }
        let frames = Int(inNumberFrames)
        let channels = captureChannels
        let neededBytes = frames * channels * MemoryLayout<Int16>.size
        guard neededBytes <= captureBufferCapacity else { return }

        let ablPtr = ablRawPtr.assumingMemoryBound(to: AudioBufferList.self)
        ablPtr.pointee.mBuffers.mDataByteSize = UInt32(neededBytes)
        guard AudioUnitRender(au, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ablPtr) == noErr,
              let rawData = ablPtr.pointee.mBuffers.mData else {
            return
        }
        let input = rawData.assumingMemoryBound(to: Int16.self)

        // Map the selected channels to stereo in the pre-allocated scratch (no
        // RT-thread allocation). The indices were resolved (and clamped) at start
        // from the user's channel preset, so a 32-channel desk can broadcast 5/6
        // — or channel 11 alone, centered — instead of always outputs 1/2.
        guard frames * 2 <= captureStereoScratch.count else { return }
        let leftIndex = captureLeftIndex
        let rightIndex = captureRightIndex
        if channels == 1 {
            for frame in 0..<frames {
                let sample = input[frame]
                captureStereoScratch[frame * 2] = sample
                captureStereoScratch[frame * 2 + 1] = sample
            }
        } else if captureSumsToMono {
            for frame in 0..<frames {
                let base = frame * channels
                let sum = (Int32(input[base + leftIndex]) + Int32(input[base + rightIndex])) / 2
                let sample = Int16(clamping: sum)
                captureStereoScratch[frame * 2] = sample
                captureStereoScratch[frame * 2 + 1] = sample
            }
        } else {
            for frame in 0..<frames {
                let base = frame * channels
                captureStereoScratch[frame * 2] = input[base + leftIndex]
                captureStereoScratch[frame * 2 + 1] = input[base + rightIndex]
            }
        }

        // Resample to 48 kHz into the pre-allocated scratch (no RT-thread alloc).
        let outputFrames = captureStereoScratch.withUnsafeBufferPointer { source -> Int in
            captureResampleScratch.withUnsafeMutableBufferPointer { dest -> Int in
                guard let sourceBase = source.baseAddress, let destBase = dest.baseAddress else { return 0 }
                return AudioPCMResampler.resampleInterleaved(
                    input: sourceBase,
                    frameCount: frames,
                    channels: 2,
                    inputRate: captureSampleRate,
                    outputRate: Double(AudioDeviceStreamSource.outputSampleRate),
                    output: destBase,
                    outputCapacityFrames: dest.count / 2
                )
            }
        }
        guard outputFrames > 0 else { return }

        // "Pause" a live device stream by writing silence instead of the capture:
        // the loopback keeps feeding the SDK real-time frames (no discontinuity),
        // the channel just hears silence until resumed.
        if isMuted {
            for index in 0..<(outputFrames * 2) { captureResampleScratch[index] = 0 }
        }
        captureResampleScratch.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            ring.write(base, frames: outputFrames)
        }
    }
}

private func deviceStreamInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let backend = Unmanaged<DeviceInputCaptureBackend>.fromOpaque(inRefCon).takeUnretainedValue()
    backend.handleInput(
        ioActionFlags: ioActionFlags,
        inTimeStamp: inTimeStamp,
        inBusNumber: inBusNumber,
        inNumberFrames: inNumberFrames
    )
    return noErr
}
