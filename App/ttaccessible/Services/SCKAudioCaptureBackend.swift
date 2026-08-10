//
//  SCKAudioCaptureBackend.swift
//  ttaccessible
//
//  Captures an application's audio output via ScreenCaptureKit (macOS
//  13.0–14.1, where the Core Audio process-tap API doesn't exist yet) and
//  feeds it into the device-stream ring. Audio-only: the stream is configured
//  for per-app audio with a minimal video surface. Requires the Screen
//  Recording permission (usage string already shipped for the app).
//

import CoreMedia
import Foundation
import ScreenCaptureKit

@available(macOS 13.0, *)
final class SCKAudioCaptureBackend: NSObject, DeviceStreamCaptureBackend, SCStreamOutput, SCStreamDelegate {

    private let selection: DeviceStreamCaptureSpec.ProcessSelection
    private let ring: AudioDeviceStreamSource.PCMRing
    private let sampleQueue = DispatchQueue(label: "com.ttaccessible.sck-stream-capture")

    private var stream: SCStream?
    private var isMuted = false

    // Pre-allocated conversion scratch (Float32 → Int16 stereo → 48 kHz).
    private var stereoScratch = [Int16]()
    private var resampleScratch = [Int16]()
    private static let maxFramesPerSlice = 16_384

    init(selection: DeviceStreamCaptureSpec.ProcessSelection, ring: AudioDeviceStreamSource.PCMRing) {
        self.selection = selection
        self.ring = ring
    }

    deinit {
        stop()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    /// Applications SCK can capture audio from right now (dialog candidates).
    /// Synchronous bridge; call off the main thread.
    static func capturableApplications() -> [(bundleID: String, name: String)] {
        let semaphore = DispatchSemaphore(value: 0)
        var results: [(bundleID: String, name: String)] = []
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, _ in
            if let content {
                results = content.applications
                    .filter { $0.bundleIdentifier.isEmpty == false && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .map { (bundleID: $0.bundleIdentifier, name: $0.applicationName) }
                    .filter { $0.name.isEmpty == false }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func start() throws {
        guard stream == nil else { return }

        stereoScratch = [Int16](repeating: 0, count: Self.maxFramesPerSlice * 2)
        resampleScratch = [Int16](repeating: 0, count: (Self.maxFramesPerSlice * 2) * AudioDeviceStreamSource.outputChannels)

        let semaphore = DispatchSemaphore(value: 0)
        var sharedContent: SCShareableContent?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            if let error {
                AudioLogger.log("sck stream: shareable content failed — %@", error.localizedDescription)
            }
            sharedContent = content
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)

        guard let content = sharedContent, let display = content.displays.first else {
            AudioLogger.log("sck stream: no shareable content/display (Screen Recording permission?)")
            throw AudioDeviceStreamSourceError.captureStartFailed
        }
        for app in content.applications where app.bundleIdentifier.isEmpty == false {
            AudioLogger.log("sck stream: capturable app pid=%d bundle=%@", Int(app.processID), app.bundleIdentifier)
        }

        let filter: SCContentFilter
        if selection.capturesEntireSystem {
            // The whole display, minus ourselves — `excludesCurrentProcessAudio`
            // below is what keeps the channel from looping back in.
            AudioLogger.log("sck stream: capturing all system audio for %@", selection.displayName)
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        } else {
            let matchedApps = content.applications.filter { app in
                selection.bundleIDPrefixes.contains { app.bundleIdentifier.hasPrefix($0) }
            }
            guard matchedApps.isEmpty == false else {
                AudioLogger.log("sck stream: no capturable app matched %@", selection.bundleIDPrefixes.joined(separator: ","))
                throw AudioDeviceStreamSourceError.deviceUnavailable
            }
            AudioLogger.log("sck stream: capturing %d app(s) for %@", matchedApps.count, selection.displayName)
            filter = SCContentFilter(display: display, including: matchedApps, exceptingWindows: [])
        }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = AudioDeviceStreamSource.outputSampleRate
        configuration.channelCount = AudioDeviceStreamSource.outputChannels
        // Audio-only use: shrink the (mandatory) video side to nothing.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        } catch {
            AudioLogger.log("sck stream: addStreamOutput failed — %@", error.localizedDescription)
            throw AudioDeviceStreamSourceError.captureStartFailed
        }

        var startError: Error?
        let startSemaphore = DispatchSemaphore(value: 0)
        stream.startCapture { error in
            startError = error
            startSemaphore.signal()
        }
        _ = startSemaphore.wait(timeout: .now() + 5)
        if let startError {
            AudioLogger.log("sck stream: startCapture failed — %@", startError.localizedDescription)
            throw AudioDeviceStreamSourceError.captureStartFailed
        }

        self.stream = stream
        AudioLogger.log("sck stream: started for %@", selection.displayName)
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        let semaphore = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 2)
        AudioLogger.log("sck stream: stopped for %@", selection.displayName)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Don't tear down the ring/server — the loopback pads silence, so the
        // broadcast survives; the log explains the silent stream.
        AudioLogger.log("sck stream: stopped with error — %@", error.localizedDescription)
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }
        let sourceRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : Double(AudioDeviceStreamSource.outputSampleRate)

        try? sampleBuffer.withAudioBufferList { bufferList, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList.unsafePointer))
            guard buffers.count > 0 else { return }

            let frames: Int
            if buffers.count >= 2 || Int(buffers[0].mNumberChannels) == 1 {
                // Non-interleaved: one Float32 buffer per channel.
                frames = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                guard frames > 0, frames * 2 <= stereoScratch.count,
                      let leftData = buffers[0].mData else { return }
                let left = leftData.assumingMemoryBound(to: Float.self)
                let right = buffers.count >= 2
                    ? buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? left
                    : left
                for frame in 0..<frames {
                    let l = max(-1.0, min(1.0, left[frame]))
                    let r = max(-1.0, min(1.0, right[frame]))
                    stereoScratch[frame * 2] = Int16(l * 32767)
                    stereoScratch[frame * 2 + 1] = Int16(r * 32767)
                }
            } else {
                // Interleaved single buffer.
                let channels = max(Int(buffers[0].mNumberChannels), 1)
                let totalSamples = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                frames = totalSamples / channels
                guard frames > 0, frames * 2 <= stereoScratch.count,
                      let data = buffers[0].mData else { return }
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
                        let l = max(-1.0, min(1.0, floatPtr[frame * channels]))
                        let r = max(-1.0, min(1.0, floatPtr[frame * channels + 1]))
                        stereoScratch[frame * 2] = Int16(l * 32767)
                        stereoScratch[frame * 2 + 1] = Int16(r * 32767)
                    }
                }
            }

            let outputFrames: Int
            if abs(sourceRate - Double(AudioDeviceStreamSource.outputSampleRate)) < 0.5 {
                outputFrames = frames
                if isMuted {
                    for index in 0..<(outputFrames * 2) { stereoScratch[index] = 0 }
                }
                stereoScratch.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    ring.write(base, frames: outputFrames)
                }
                return
            }

            outputFrames = stereoScratch.withUnsafeBufferPointer { source -> Int in
                resampleScratch.withUnsafeMutableBufferPointer { dest -> Int in
                    guard let sourceBase = source.baseAddress, let destBase = dest.baseAddress else { return 0 }
                    return AudioPCMResampler.resampleInterleaved(
                        input: sourceBase,
                        frameCount: frames,
                        channels: 2,
                        inputRate: sourceRate,
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
}
