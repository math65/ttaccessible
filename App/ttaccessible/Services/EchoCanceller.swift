//
//  EchoCanceller.swift
//  ttaccessible
//

import Foundation

/// Echo canceller backed by WebRTC AEC3 via C wrapper.
///
/// Thread safety model:
/// - `feedReference()` is called from the TeamTalk serial queue.
/// - `processCapture()` is called from the real-time audio thread.
/// - WebRTC AudioProcessing handles internal synchronization between
///   ProcessReverseStream and ProcessStream.
///
/// Audio must be fed in 10ms frames of interleaved Int16 PCM.
final class EchoCanceller {

    struct Configuration {
        let sampleRate: Int
        let channels: Int

        /// Number of samples per channel in a 10ms frame.
        var frameSamplesPerChannel: Int { sampleRate / 100 }
    }

    private let config: Configuration
    private let aecRef: WebRTCAECRef

    // Accumulation buffers for chunking arbitrary-sized input into 10ms frames.
    private var renderAccumulator: [Int16] = []
    private var captureAccumulator: [Int16] = []
    private var captureOutput: [Int16] = []

    init?(configuration: Configuration) {
        self.config = configuration
        guard let ref = webrtc_aec_create(Int32(configuration.sampleRate), Int32(configuration.channels)) else {
            return nil
        }
        self.aecRef = ref
    }

    deinit {
        webrtc_aec_destroy(aecRef)
    }

    // MARK: - Reference Signal (called from TeamTalk queue)

    /// Feed decoded far-end audio (what is played through speakers).
    /// Accepts any number of interleaved Int16 samples; internally chunks into 10ms frames.
    func feedReference(_ samples: UnsafePointer<Int16>, count: Int, channels: Int) {
        let frameSamples = config.frameSamplesPerChannel * config.channels
        let totalSamples = count * channels

        // If channel count matches, use directly; otherwise skip (rare mismatch case).
        guard channels == config.channels else { return }

        // Append to accumulator.
        renderAccumulator.append(contentsOf: UnsafeBufferPointer(start: samples, count: totalSamples))

        // Process complete 10ms frames.
        while renderAccumulator.count >= frameSamples {
            renderAccumulator.withUnsafeBufferPointer { buffer in
                webrtc_aec_feed_render(aecRef, buffer.baseAddress!, Int32(config.frameSamplesPerChannel))
            }
            renderAccumulator.removeFirst(frameSamples)
        }
    }

    // MARK: - Capture Processing (called from real-time audio thread)

    /// Process microphone capture audio through AEC3.
    /// Input: interleaved Int16 PCM. Output: echo-cancelled interleaved Int16 PCM.
    /// Returns the processed samples. The returned array may be shorter than input
    /// if the input doesn't complete a 10ms frame boundary.
    func processCapture(_ samples: UnsafePointer<Int16>, count: Int) -> [Int16] {
        let frameSamples = config.frameSamplesPerChannel * config.channels

        captureAccumulator.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        captureOutput.removeAll(keepingCapacity: true)

        while captureAccumulator.count >= frameSamples {
            // Process one 10ms frame in-place.
            var frame = Array(captureAccumulator.prefix(frameSamples))
            frame.withUnsafeMutableBufferPointer { buffer in
                webrtc_aec_process_capture(aecRef, buffer.baseAddress!, Int32(config.frameSamplesPerChannel))
            }
            captureOutput.append(contentsOf: frame)
            captureAccumulator.removeFirst(frameSamples)
        }

        return captureOutput
    }

    // MARK: - Reset

    func reset() {
        renderAccumulator.removeAll(keepingCapacity: true)
        captureAccumulator.removeAll(keepingCapacity: true)
        captureOutput.removeAll(keepingCapacity: true)
    }
}
