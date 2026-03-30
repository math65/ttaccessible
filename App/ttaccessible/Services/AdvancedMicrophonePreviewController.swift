//
//  AdvancedMicrophonePreviewController.swift
//  ttaccessible
//
//  Created by Codex on 18/03/2026.
//

import AVFAudio
import Foundation

@MainActor
final class AdvancedMicrophonePreviewController {
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let lock = NSLock()
    private let diagnosticsLogger = AudioDiagnosticsLogger.shared
    private lazy var captureEngine = AdvancedMicrophoneAudioEngine(diagnosticsScope: "audio-preview-capture") { [weak self] chunk in
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
        diagnosticsLogger.log(
            "audio-preview",
            "Start. playbackRate=\(playbackFormat.sampleRate) playbackChannels=\(playbackFormat.channelCount) targetRate=\(configuration.targetFormat.sampleRate) targetChannels=\(configuration.targetFormat.channels)"
        )
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        playbackEngine.prepare()
        try playbackEngine.start()
        playerNode.play()
        _ = try captureEngine.start(configuration: configuration)
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
        diagnosticsLogger.log("audio-preview", "Stop.")
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
            diagnosticsLogger.log(
                "audio-preview",
                "Drop chunk. scheduled=\(scheduledBufferCount) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount)"
            )
            return
        }

        buffer.frameLength = AVAudioFrameCount(chunk.sampleCount)
        let channelCount = Int(chunk.channels)
        let frameCount = Int(chunk.sampleCount)
        enqueuedChunkCount += 1

        chunk.data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: Int16.self)
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

        if enqueuedChunkCount <= 12 || enqueuedChunkCount % 50 == 0 {
            diagnosticsLogger.log(
                "audio-preview",
                "Chunk #\(enqueuedChunkCount) queued. scheduled=\(scheduledBufferCount) rate=\(chunk.sampleRate) channels=\(chunk.channels) samples=\(chunk.sampleCount)"
            )
        }
    }
}
