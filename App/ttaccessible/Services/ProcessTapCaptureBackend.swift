//
//  ProcessTapCaptureBackend.swift
//  ttaccessible
//
//  Captures the audio OUTPUT of a specific set of processes (an application,
//  or VoiceOver) via the Core Audio process-tap API (macOS 14.2+) and feeds it
//  into the device-stream ring. Same API family as SpeakerTapCapture (the AEC
//  reference tap), but scoped to chosen processes, and by default unmuted so
//  the user keeps hearing the audio locally (optionally muted-while-tapped).
//
//  A tap binds to concrete HAL process objects, so the backend watches the
//  HAL's process list and rebuilds the tap when the matched set changes —
//  the target app can be silent, quit, relaunch, or spawn audio helpers
//  mid-stream and capture (re)attaches by itself; the loopback server pads
//  silence over the gaps, so the broadcast never dies.
//

import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

@available(macOS 14.2, *)
final class ProcessTapCaptureBackend: DeviceStreamCaptureBackend {

    struct AudioProcessInfo {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String
    }

    private let selection: DeviceStreamCaptureSpec.ProcessSelection
    private let ring: AudioDeviceStreamSource.PCMRing
    private let muteLocalOutput: Bool
    /// Serializes all lifecycle (start/stop/rebuild); the HAL process-list
    /// listener fires here too.
    private let controlQueue = DispatchQueue(label: "com.ttaccessible.process-tap-control")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    /// Object IDs the current tap was built for (empty = waiting for the
    /// target to appear in the HAL).
    private var tappedObjectIDs: Set<AudioObjectID> = []
    private var started = false
    private var processListListenerInstalled = false
    private var rebuildPending = false
    private var isMuted = false

    private var capturedSampleRate: Double = 48_000
    private var capturedChannels: Int = 2
    // Pre-allocated conversion scratch (Float32 → Int16 stereo → 48 kHz),
    // sized generously up front so the IO thread never allocates.
    private var stereoScratch = [Int16]()
    private var resampleScratch = [Int16]()
    private static let maxFramesPerSlice = 16_384

    private lazy var processListListener: (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { [weak self] _, _ in
        self?.scheduleRebuildCheck()
    }

    init(
        selection: DeviceStreamCaptureSpec.ProcessSelection,
        ring: AudioDeviceStreamSource.PCMRing,
        muteLocalOutput: Bool = false
    ) {
        self.selection = selection
        self.ring = ring
        self.muteLocalOutput = muteLocalOutput
    }

    deinit {
        stop()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    // MARK: - Process enumeration (also used by the source-picker dialog)

    /// All processes currently registered with the HAL, with pid + bundle ID.
    static func audioProcesses() -> [AudioProcessInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return [] }
        var objectIDs = [AudioObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objectIDs) == noErr else {
            return []
        }

        return objectIDs.compactMap { objectID in
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = -1
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid > 0 else {
                return nil
            }
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleID: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            _ = withUnsafeMutablePointer(to: &bundleID) { ptr in
                AudioObjectGetPropertyData(objectID, &bundleAddress, 0, nil, &bundleSize, ptr)
            }
            return AudioProcessInfo(objectID: objectID, pid: pid, bundleID: bundleID as String)
        }
    }

    /// Every regular (Dock-visible) running application — all selectable: an
    /// app that hasn't touched audio yet simply captures silence until it
    /// does (the backend attaches the moment its audio process registers).
    static func runningAudioApplications() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier,
                      let name = app.localizedName, name.isEmpty == false else { return nil }
                return (bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Maps a helper process to the app the user perceives as playing its
    /// audio. Finder/QuickLook is the canonical case: Finder never plays audio
    /// itself — previews render in QuickLookUIService/WebKit.GPU helpers whose
    /// bundle IDs share nothing with com.apple.finder, but whose RESPONSIBLE
    /// process is Finder (the same attribution TCC uses). Private-but-stable
    /// libsystem call, resolved via dlsym so a future removal degrades to
    /// prefix-only matching instead of failing at launch.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),  // RTLD_DEFAULT
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private func matchedProcesses() -> [AudioProcessInfo] {
        let prefixes = selection.bundleIDPrefixes
        // Running apps the selection denotes — helpers attribute to these
        // via responsible-pid.
        let targetPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { app in
                    guard let bundleID = app.bundleIdentifier else { return false }
                    return prefixes.contains { bundleID.hasPrefix($0) }
                }
                .map(\.processIdentifier)
        )
        return Self.audioProcesses().filter { process in
            if prefixes.contains(where: { process.bundleID.hasPrefix($0) }) { return true }
            if targetPIDs.contains(process.pid) { return true }
            guard targetPIDs.isEmpty == false, let responsiblePID = Self.responsiblePID else { return false }
            let responsible = responsiblePID(process.pid)
            return responsible > 0 && targetPIDs.contains(responsible)
        }
    }

    // MARK: - Lifecycle

    func start() throws {
        try controlQueue.sync {
            guard started == false else { return }
            started = true

            // Allocated ONCE for the backend's lifetime (never on rebuild):
            // a mid-stream rebuild must not swap buffers under the old IO
            // thread's final callback. Sized for the slowest plausible tap
            // rate (8 kHz) so resampling can never outgrow them.
            stereoScratch = [Int16](repeating: 0, count: Self.maxFramesPerSlice * 2)
            let worstCaseOutputFrames = Self.maxFramesPerSlice * (AudioDeviceStreamSource.outputSampleRate / 8_000) + 8
            resampleScratch = [Int16](repeating: 0, count: worstCaseOutputFrames * AudioDeviceStreamSource.outputChannels)

            let matched = matchedProcesses()
            // Diagnostic dump: which HAL processes exist, who they're
            // responsible to, and which matched — how the VoiceOver process
            // set and helper attribution get verified/refined live.
            for process in Self.audioProcesses() {
                let responsible = Self.responsiblePID?(process.pid) ?? -1
                let responsibleBundle = responsible > 0
                    ? NSRunningApplication(processIdentifier: responsible)?.bundleIdentifier ?? "?"
                    : "?"
                AudioLogger.log("process tap: HAL process pid=%d bundle=%@ responsible=%d(%@)",
                                Int(process.pid), process.bundleID, Int(responsible), responsibleBundle)
            }
            if matched.isEmpty {
                // Not an error: the target just hasn't registered audio yet
                // (app not playing, VoiceOver off). The stream carries silence
                // and the listener below attaches the moment it appears.
                AudioLogger.log("process tap: no HAL process matches %@ yet — waiting for it to appear",
                                selection.bundleIDPrefixes.joined(separator: ","))
            } else {
                try buildCaptureLocked(matched: matched)
            }
            installProcessListListenerLocked()
        }
    }

    func stop() {
        controlQueue.sync {
            guard started else { return }
            started = false
            removeProcessListListenerLocked()
            teardownCaptureLocked()
            AudioLogger.log("process tap: stopped for %@", selection.displayName)
        }
    }

    // MARK: - Rebuild on HAL process-list changes

    private func installProcessListListenerLocked() {
        guard processListListenerInstalled == false else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, processListListener
        )
        processListListenerInstalled = status == noErr
        if status != noErr {
            AudioLogger.log("process tap: process-list listener failed status=%d — no auto-reattach", status)
        }
    }

    private func removeProcessListListenerLocked() {
        guard processListListenerInstalled else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, controlQueue, processListListener
        )
        processListListenerInstalled = false
    }

    /// Debounced (0.3 s): app launches register several processes in a burst.
    private func scheduleRebuildCheck() {
        // Runs on controlQueue (the listener's dispatch queue).
        guard started, rebuildPending == false else { return }
        rebuildPending = true
        controlQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.rebuildIfMatchedSetChanged()
        }
    }

    private func rebuildIfMatchedSetChanged() {
        rebuildPending = false
        guard started else { return }
        let matched = matchedProcesses()
        let matchedIDs = Set(matched.map(\.objectID))
        guard matchedIDs != tappedObjectIDs else { return }

        AudioLogger.log("process tap: matched process set changed (%d → %d) — rebuilding capture",
                        tappedObjectIDs.count, matchedIDs.count)
        teardownCaptureLocked()
        guard matched.isEmpty == false else {
            AudioLogger.log("process tap: target gone — waiting for it to reappear")
            return
        }
        do {
            try buildCaptureLocked(matched: matched)
        } catch {
            AudioLogger.log("process tap: rebuild failed — waiting for next process-list change")
        }
    }

    // MARK: - Tap + aggregate construction

    private func buildCaptureLocked(matched: [AudioProcessInfo]) throws {
        AudioLogger.log("process tap: capturing %d process(es) for %@: %@",
                        matched.count, selection.displayName,
                        matched.map { "\($0.bundleID)(\($0.pid))" }.joined(separator: " "))

        // 1. Tap: stereo mixdown of exactly the matched processes; private so
        // it isn't user-visible. Muting the source's local output while tapped
        // is the user's per-stream choice.
        let description = CATapDescription(stereoMixdownOfProcesses: matched.map { $0.objectID })
        description.name = "ttaccessible-stream-tap"
        description.isPrivate = true
        description.muteBehavior = muteLocalOutput ? .mutedWhenTapped : .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else {
            AudioLogger.log("process tap: AudioHardwareCreateProcessTap failed status=%d", status)
            throw AudioDeviceStreamSourceError.captureStartFailed
        }
        tapID = newTapID

        // 2. Private aggregate device hosting the tap (same shape as the AEC tap).
        let uid = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ttaccessible-stream-aggregate",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
            kAudioAggregateDeviceMasterSubDeviceKey: 0,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false
        ]
        var newDeviceID: AudioObjectID = 0
        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newDeviceID)
        guard status == noErr else {
            AudioLogger.log("process tap: AudioHardwareCreateAggregateDevice failed status=%d", status)
            cleanupCoreAudioObjectsLocked()
            throw AudioDeviceStreamSourceError.captureStartFailed
        }
        aggregateDeviceID = newDeviceID

        var tapUIDAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUIDSize = UInt32(MemoryLayout<CFString>.size)
        var tapUID: CFString = "" as CFString
        withUnsafeMutablePointer(to: &tapUID) { ptr in
            _ = AudioObjectGetPropertyData(tapID, &tapUIDAddress, 0, nil, &tapUIDSize, ptr)
        }
        var tapListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let tapArray = [tapUID] as CFArray
        let tapArraySize = UInt32(MemoryLayout<CFArray>.size)
        status = withUnsafePointer(to: tapArray) { ptr in
            AudioObjectSetPropertyData(aggregateDeviceID, &tapListAddress, 0, nil, tapArraySize, ptr)
        }
        guard status == noErr else {
            AudioLogger.log("process tap: failed to add tap to aggregate device status=%d", status)
            cleanupCoreAudioObjectsLocked()
            throw AudioDeviceStreamSourceError.captureStartFailed
        }

        // Give the aggregate a beat to become ready after adding the tap.
        Thread.sleep(forTimeInterval: 0.1)

        var inputFormatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var inputFormat = AudioStreamBasicDescription()
        if AudioObjectGetPropertyData(aggregateDeviceID, &inputFormatAddress, 0, nil, &inputFormatSize, &inputFormat) == noErr {
            capturedSampleRate = inputFormat.mSampleRate > 0 ? inputFormat.mSampleRate : 48_000
            capturedChannels = max(Int(inputFormat.mChannelsPerFrame), 1)
        }
        AudioLogger.log("process tap: capture format rate=%.0f channels=%d", capturedSampleRate, capturedChannels)

        // 3. IO proc on the aggregate device.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        status = AudioDeviceCreateIOProcID(aggregateDeviceID, processStreamTapIOProc, selfPtr, &ioProcID)
        guard status == noErr else {
            AudioLogger.log("process tap: AudioDeviceCreateIOProcID failed status=%d", status)
            cleanupCoreAudioObjectsLocked()
            throw AudioDeviceStreamSourceError.captureStartFailed
        }
        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            AudioLogger.log("process tap: AudioDeviceStart failed status=%d", status)
            teardownCaptureLocked()
            throw AudioDeviceStreamSourceError.captureStartFailed
        }

        tappedObjectIDs = Set(matched.map(\.objectID))
        AudioLogger.log("process tap: started for %@%@", selection.displayName,
                        muteLocalOutput ? " (source muted locally)" : "")
    }

    private func teardownCaptureLocked() {
        if let proc = ioProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
            ioProcID = nil
        }
        cleanupCoreAudioObjectsLocked()
        tappedObjectIDs = []
    }

    private func cleanupCoreAudioObjectsLocked() {
        if aggregateDeviceID != 0 && aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // Called from the Core Audio IO thread: Float32 (interleaved single buffer)
    // → Int16 stereo → 48 kHz → ring. Mirrors DeviceInputCaptureBackend's
    // conversion; all scratch pre-allocated.
    fileprivate func handleIOProc(_ inputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let firstBuffer = bufferList.first,
              let data = firstBuffer.mData,
              firstBuffer.mDataByteSize > 0 else {
            return
        }

        let channels = max(Int(firstBuffer.mNumberChannels), 1)
        let totalSamples = Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size
        let frames = channels > 0 ? totalSamples / channels : 0
        guard frames > 0, frames * 2 <= stereoScratch.count else { return }

        let floatPtr = data.assumingMemoryBound(to: Float.self)
        if channels == 1 {
            for frame in 0..<frames {
                let clamped = max(-1.0, min(1.0, floatPtr[frame]))
                let sample = Int16(clamped * 32767)
                stereoScratch[frame * 2] = sample
                stereoScratch[frame * 2 + 1] = sample
            }
        } else {
            for frame in 0..<frames {
                let left = max(-1.0, min(1.0, floatPtr[frame * channels]))
                let right = max(-1.0, min(1.0, floatPtr[frame * channels + 1]))
                stereoScratch[frame * 2] = Int16(left * 32767)
                stereoScratch[frame * 2 + 1] = Int16(right * 32767)
            }
        }

        let outputFrames = stereoScratch.withUnsafeBufferPointer { source -> Int in
            resampleScratch.withUnsafeMutableBufferPointer { dest -> Int in
                guard let sourceBase = source.baseAddress, let destBase = dest.baseAddress else { return 0 }
                return AudioPCMResampler.resampleInterleaved(
                    input: sourceBase,
                    frameCount: frames,
                    channels: 2,
                    inputRate: capturedSampleRate,
                    outputRate: Double(AudioDeviceStreamSource.outputSampleRate),
                    output: destBase,
                    outputCapacityFrames: dest.count / 2
                )
            }
        }
        guard outputFrames > 0 else { return }

        if isMuted {
            for index in 0..<(outputFrames * 2) { resampleScratch[index] = 0 }
        }
        resampleScratch.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            ring.write(base, frames: outputFrames)
        }
    }
}

@available(macOS 14.2, *)
private func processStreamTapIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = inClientData else { return noErr }
    let backend = Unmanaged<ProcessTapCaptureBackend>.fromOpaque(clientData).takeUnretainedValue()
    backend.handleIOProc(inInputData)
    return noErr
}
