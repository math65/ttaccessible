//
//  AdvancedMicrophonePreviewController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 18/03/2026.
//

import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation

@MainActor
final class AdvancedMicrophonePreviewController {
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let lock = NSLock()
    private lazy var captureEngine = AdvancedMicrophoneAudioEngine { [weak self] chunk in
        self?.enqueue(chunk: chunk)
    }

    private var playbackFormat: AVAudioFormat?
    private var scheduledBufferCount = 0
    private var enqueuedChunkCount = 0

    init() {
        playbackEngine.attach(playerNode)
    }

    var isRunning: Bool {
        captureEngine.isRunning
    }

    func start(configuration: AdvancedMicrophoneAudioConfiguration, outputDeviceID: AudioDeviceID?) throws {
        stop()

        // Set up playback first. On duplex devices (e.g. Komplete Audio 6) used as both
        // default output AND mic input, AVAudioEngine.start() can hang if we let the
        // capture AUHAL claim the device first. Chunks are delivered at the configured
        // target rate (the resampler in AdvancedMicrophoneAudioEngine resamples from the
        // hardware rate to encoderFormat.sampleRate), so the playback format can be
        // derived from the configuration directly — no need to query effectiveSampleRate.
        let channelCount = AVAudioChannelCount(max(configuration.targetFormat.channels, 1))
        guard let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: configuration.targetFormat.sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw AdvancedMicrophoneAudioEngineError.queueCreationFailed
        }

        self.playbackFormat = playbackFormat

        // Route preview monitoring to the user's selected output device instead of
        // the system default. Mirrors the explicit CurrentDevice binding the
        // capture AUHAL uses. If it can't be resolved/bound, fall back to the
        // engine's default output so monitoring still works.
        if let outputDeviceID, let outputAU = playbackEngine.outputNode.audioUnit {
            var deviceID = outputDeviceID
            let status = AudioUnitSetProperty(
                outputAU,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status == noErr {
                AudioLogger.log("preview: bound output to device %u", outputDeviceID)
            } else {
                AudioLogger.log("preview: failed to bind output device %u (OSStatus %d) — using default", outputDeviceID, Int(status))
            }
        }

        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        playbackEngine.prepare()

        do {
            try playbackEngine.start()
        } catch {
            self.playbackFormat = nil
            throw error
        }

        do {
            _ = try captureEngine.start(configuration: configuration)
        } catch {
            playerNode.stop()
            playbackEngine.stop()
            playbackEngine.reset()
            self.playbackFormat = nil
            throw error
        }

        playerNode.play()
    }

    func stop() {
        captureEngine.stop()
        playerNode.stop()
        playbackEngine.stop()
        playbackEngine.reset()
        lock.lock()
        scheduledBufferCount = 0
        lock.unlock()
        playbackFormat = nil
        enqueuedChunkCount = 0
    }

    private func enqueue(chunk: AdvancedMicrophoneAudioChunk) {
        guard let playbackFormat,
              Int(playbackFormat.channelCount) == Int(chunk.channels),
              playbackFormat.sampleRate == Double(chunk.sampleRate),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: playbackFormat,
                frameCapacity: AVAudioFrameCount(chunk.sampleCount)
              ) else {
            return
        }

        lock.lock()
        let shouldDrop = scheduledBufferCount >= 12
        if shouldDrop == false {
            scheduledBufferCount += 1
        }
        lock.unlock()

        guard shouldDrop == false else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(chunk.sampleCount)
        let channelCount = Int(chunk.channels)
        let frameCount = Int(chunk.sampleCount)
        enqueuedChunkCount += 1

        chunk.samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress,
                  let channelData = buffer.int16ChannelData else {
                return
            }

            if channelCount == 1 {
                channelData[0].update(from: baseAddress, count: frameCount)
                return
            }

            for frame in 0..<frameCount {
                let sourceFrame = frame * channelCount
                for channel in 0..<channelCount {
                    channelData[channel][frame] = baseAddress[sourceFrame + channel]
                }
            }
        }

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.scheduledBufferCount = max(self.scheduledBufferCount - 1, 0)
                self.lock.unlock()
            }
        }

    }
}
