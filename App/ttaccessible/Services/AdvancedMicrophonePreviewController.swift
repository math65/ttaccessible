//
//  AdvancedMicrophonePreviewController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 18/03/2026.
//

import AVFAudio
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

    func start(configuration: AdvancedMicrophoneAudioConfiguration) throws {
        stop()

        // Start capture first so the engine resolves the actual hardware sample rate.
        _ = try captureEngine.start(configuration: configuration)

        let actualSampleRate = captureEngine.effectiveSampleRate ?? configuration.targetFormat.sampleRate
        let channelCount = AVAudioChannelCount(max(configuration.targetFormat.channels, 1))
        guard let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: actualSampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            captureEngine.stop()
            throw AdvancedMicrophoneAudioEngineError.queueCreationFailed
        }

        self.playbackFormat = playbackFormat
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        playbackEngine.prepare()

        do {
            try playbackEngine.start()
        } catch {
            captureEngine.stop()
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
