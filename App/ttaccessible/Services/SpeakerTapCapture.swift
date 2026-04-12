//
//  SpeakerTapCapture.swift
//  ttaccessible
//
//  Captures the actual speaker output (all processes) via Core Audio Tap API (macOS 14.2+).
//  Used as the AEC reference signal so echo cancellation works against VoiceOver,
//  system sounds, and all audio — not just TeamTalk decoded audio.
//

import AudioToolbox
import CoreAudio
import Foundation

@available(macOS 14.2, *)
final class SpeakerTapCapture {

    struct Configuration {
        let sampleRate: Int
        let channels: Int
    }

    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false

    private let onAudioData: (UnsafePointer<Int16>, Int, Int, Int) -> Void  // (samples, frameCount, channels, sampleRate)

    // Pre-allocated conversion buffer (Float32 → Int16).
    private var int16Buffer = [Int16]()
    private var capturedSampleRate: Double = 0
    private var capturedChannels: Int = 0

    /// - Parameter onAudioData: Called with (pointer to Int16 samples, frame count, channels, sampleRate).
    ///   Called from the Core Audio IO thread — must be real-time safe.
    init(onAudioData: @escaping (UnsafePointer<Int16>, Int, Int, Int) -> Void) {
        self.onAudioData = onAudioData
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard !isRunning else { return true }

        AudioLogger.log("SpeakerTapCapture: starting")

        // 1. Create a tap on all output audio.
        let description = CATapDescription()
        description.name = "ttaccessible-aec-tap"
        description.processes = []
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.isMixdown = true
        description.isMono = false
        description.isExclusive = true
        description.deviceUID = nil  // system default output
        description.stream = 0

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else {
            AudioLogger.log("SpeakerTapCapture: AudioHardwareCreateProcessTap failed status=%d", status)
            return false
        }
        tapID = newTapID

        // Read tap format.
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var tapFormat = AudioStreamBasicDescription()
        AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &tapFormat)

        capturedSampleRate = tapFormat.mSampleRate > 0 ? tapFormat.mSampleRate : 48000
        capturedChannels = max(Int(tapFormat.mChannelsPerFrame), 1)
        AudioLogger.log("SpeakerTapCapture: tap format rate=%.0f channels=%d", capturedSampleRate, capturedChannels)

        // 2. Create a private aggregate device.
        let uid = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ttaccessible-aec-aggregate",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
            kAudioAggregateDeviceMasterSubDeviceKey: 0,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false
        ]

        var newDeviceID: AudioObjectID = 0
        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newDeviceID)
        guard status == noErr else {
            AudioLogger.log("SpeakerTapCapture: AudioHardwareCreateAggregateDevice failed status=%d", status)
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
            return false
        }
        aggregateDeviceID = newDeviceID

        // 3. Add tap to aggregate device.
        var tapUIDAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUIDSize = UInt32(MemoryLayout<CFString>.size)
        var tapUID: CFString = "" as CFString
        withUnsafeMutablePointer(to: &tapUID) { ptr in
            AudioObjectGetPropertyData(tapID, &tapUIDAddress, 0, nil, &tapUIDSize, ptr)
        }

        var tapListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let tapArray = [tapUID] as CFArray
        var tapArraySize = UInt32(MemoryLayout<CFArray>.size)
        status = withUnsafePointer(to: tapArray) { ptr in
            AudioObjectSetPropertyData(aggregateDeviceID, &tapListAddress, 0, nil, tapArraySize, ptr)
        }
        guard status == noErr else {
            AudioLogger.log("SpeakerTapCapture: failed to add tap to aggregate device status=%d", status)
            cleanup()
            return false
        }

        // Wait for the aggregate device to become ready after adding the tap.
        Thread.sleep(forTimeInterval: 0.1)

        // Read the actual input format from the aggregate device.
        var inputFormatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var inputFormat = AudioStreamBasicDescription()
        let fmtStatus = AudioObjectGetPropertyData(aggregateDeviceID, &inputFormatAddress, 0, nil, &inputFormatSize, &inputFormat)
        if fmtStatus == noErr {
            capturedSampleRate = inputFormat.mSampleRate > 0 ? inputFormat.mSampleRate : capturedSampleRate
            capturedChannels = max(Int(inputFormat.mChannelsPerFrame), 1)
            AudioLogger.log("SpeakerTapCapture: aggregate input format rate=%.0f channels=%d bitsPerChannel=%d",
                            capturedSampleRate, capturedChannels, inputFormat.mBitsPerChannel)
        } else {
            AudioLogger.log("SpeakerTapCapture: could not read aggregate input format status=%d", fmtStatus)
        }

        // 4. Set up IO proc on the aggregate device.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        status = AudioDeviceCreateIOProcID(
            aggregateDeviceID,
            speakerTapIOProc,
            selfPtr,
            &ioProcID
        )
        guard status == noErr else {
            AudioLogger.log("SpeakerTapCapture: AudioDeviceCreateIOProcID failed status=%d", status)
            cleanup()
            return false
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            AudioLogger.log("SpeakerTapCapture: AudioDeviceStart failed status=%d", status)
            if let proc = ioProcID {
                AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
                ioProcID = nil
            }
            cleanup()
            return false
        }

        isRunning = true
        AudioLogger.log("SpeakerTapCapture: started successfully")
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        AudioLogger.log("SpeakerTapCapture: stopping")

        if let proc = ioProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
            ioProcID = nil
        }
        cleanup()
    }

    private func cleanup() {
        if aggregateDeviceID != 0 && aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // Called from the Core Audio IO thread.
    func handleIOProc(_ inputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let firstBuffer = bufferList.first,
              let data = firstBuffer.mData,
              firstBuffer.mDataByteSize > 0 else {
            return
        }

        let channels = max(Int(firstBuffer.mNumberChannels), capturedChannels)
        let bytesPerSample = MemoryLayout<Float>.size
        let totalSamples = Int(firstBuffer.mDataByteSize) / bytesPerSample
        let frameCount = channels > 0 ? totalSamples / channels : 0
        guard frameCount > 0 else { return }

        // Convert Float32 to Int16.
        if int16Buffer.count < totalSamples {
            int16Buffer = [Int16](repeating: 0, count: totalSamples)
        }

        let floatPtr = data.assumingMemoryBound(to: Float.self)
        for i in 0..<totalSamples {
            let clamped = max(-1.0, min(1.0, floatPtr[i]))
            int16Buffer[i] = Int16(clamped * 32767)
        }

        int16Buffer.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            onAudioData(base, frameCount, channels, Int(capturedSampleRate))
        }
    }
}

// C callback for AudioDeviceIOProc.
@available(macOS 14.2, *)
private func speakerTapIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let capture = Unmanaged<SpeakerTapCapture>.fromOpaque(clientData).takeUnretainedValue()
    capture.handleIOProc(inInputData)
    return noErr
}
