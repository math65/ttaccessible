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
    private let renderAccumulatorMaxSamples: Int

    // Pre-allocated buffers for real-time thread (processCapture).
    private var captureAccumulator: [Int16]
    private var captureWriteIndex = 0
    private var captureOutput: [Int16]
    private var captureOutputCount = 0
    private var frameBuffer: [Int16]

    // Resampling buffer for rate conversion.
    private var resampleBuffer: [Int16] = []

    // Diagnostics (non-RT safe counters, only written from their respective threads).
    private var referenceFramesFed: Int = 0
    private var captureFramesProcessed: Int = 0
    private var lastDiagnosticTime: CFAbsoluteTime = 0

    init?(configuration: Configuration) {
        self.config = configuration
        guard let ref = webrtc_aec_create(Int32(configuration.sampleRate), Int32(configuration.channels)) else {
            return nil
        }
        self.aecRef = ref
        self.renderAccumulatorMaxSamples = configuration.sampleRate * configuration.channels * 2
        let frameSamples = configuration.frameSamplesPerChannel * configuration.channels
        captureAccumulator = [Int16](repeating: 0, count: frameSamples * 8)
        captureOutput = [Int16](repeating: 0, count: frameSamples * 8)
        frameBuffer = [Int16](repeating: 0, count: frameSamples)
    }

    deinit {
        webrtc_aec_destroy(aecRef)
    }

    // MARK: - Reference Signal (called from TeamTalk queue)

    /// Feed decoded far-end audio (what is played through speakers).
    /// Accepts any number of interleaved Int16 samples; internally chunks into 10ms frames.
    /// If `sampleRate` differs from the configured rate, linear interpolation is used to resample.
    func feedReference(_ samples: UnsafePointer<Int16>, count: Int, channels: Int, sampleRate: Int = 0) {
        let frameSamples = config.frameSamplesPerChannel * config.channels

        // If channel count matches, use directly; otherwise skip (rare mismatch case).
        guard channels == config.channels else { return }

        let effectiveRate = sampleRate > 0 ? sampleRate : config.sampleRate

        if effectiveRate != config.sampleRate {
            // Resample using linear interpolation.
            let totalInputSamples = count * channels
            let ratio = Double(config.sampleRate) / Double(effectiveRate)
            let outputFrames = Int(Double(count) * ratio)
            let outputSamples = outputFrames * channels
            if resampleBuffer.count < outputSamples {
                resampleBuffer = [Int16](repeating: 0, count: outputSamples)
            }
            for frame in 0..<outputFrames {
                let srcPos = Double(frame) / ratio
                let srcIndex = Int(srcPos)
                let frac = srcPos - Double(srcIndex)
                for ch in 0..<channels {
                    let idx0 = srcIndex * channels + ch
                    let idx1 = min(idx0 + channels, totalInputSamples - 1)
                    let s0 = Double(samples[idx0])
                    let s1 = Double(samples[min(idx1, totalInputSamples - 1)])
                    resampleBuffer[frame * channels + ch] = Int16(clamping: Int(s0 + frac * (s1 - s0)))
                }
            }
            // Append resampled data to accumulator.
            renderAccumulator.append(contentsOf: resampleBuffer.prefix(outputSamples))
        } else {
            let totalSamples = count * channels
            // Append to accumulator.
            renderAccumulator.append(contentsOf: UnsafeBufferPointer(start: samples, count: totalSamples))
        }

        // Cap renderAccumulator to max size to prevent unbounded growth.
        if renderAccumulator.count > renderAccumulatorMaxSamples {
            renderAccumulator.removeFirst(renderAccumulator.count - renderAccumulatorMaxSamples)
        }

        // Process complete 10ms frames.
        while renderAccumulator.count >= frameSamples {
            renderAccumulator.withUnsafeBufferPointer { buffer in
                webrtc_aec_feed_render(aecRef, buffer.baseAddress!, Int32(config.frameSamplesPerChannel))
            }
            referenceFramesFed += 1
            renderAccumulator.removeFirst(frameSamples)
        }

        logDiagnosticsIfNeeded(refRate: effectiveRate, refChannels: channels)
    }

    private func logDiagnosticsIfNeeded(refRate: Int, refChannels: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDiagnosticTime >= 5.0 else { return }
        lastDiagnosticTime = now
        AudioLogger.log(
            "AEC diag: config=%dHz/%dch, ref=%dHz/%dch, refFrames=%d, capFrames=%d",
            config.sampleRate, config.channels,
            refRate, refChannels,
            referenceFramesFed, captureFramesProcessed
        )
    }

    // MARK: - Capture Processing (called from real-time audio thread)

    /// Process microphone capture audio through AEC3.
    /// Input: interleaved Int16 PCM. Output: echo-cancelled interleaved Int16 PCM.
    /// Returns the processed samples. The returned array may be shorter than input
    /// if the input doesn't complete a 10ms frame boundary.
    func processCapture(_ samples: UnsafePointer<Int16>, count: Int) -> [Int16] {
        let frameSamples = config.frameSamplesPerChannel * config.channels

        // Drop input if it would exceed pre-allocated capacity (avoid RT allocation).
        let neededCapacity = captureWriteIndex + count
        if neededCapacity > captureAccumulator.count {
            return []
        }

        // Copy input into accumulator (no allocation — writes into pre-allocated space).
        for i in 0..<count {
            captureAccumulator[captureWriteIndex + i] = samples[i]
        }
        captureWriteIndex += count

        captureOutputCount = 0

        while captureWriteIndex >= frameSamples {
            // Copy one frame into pre-allocated frameBuffer.
            for i in 0..<frameSamples {
                frameBuffer[i] = captureAccumulator[i]
            }

            // Process the frame in-place via WebRTC AEC3.
            frameBuffer.withUnsafeMutableBufferPointer { buffer in
                webrtc_aec_process_capture(aecRef, buffer.baseAddress!, Int32(config.frameSamplesPerChannel))
            }

            captureFramesProcessed += 1

            // Drop if output would exceed pre-allocated capacity.
            let neededOutput = captureOutputCount + frameSamples
            if neededOutput > captureOutput.count {
                break
            }
            for i in 0..<frameSamples {
                captureOutput[captureOutputCount + i] = frameBuffer[i]
            }
            captureOutputCount += frameSamples

            // Shift remaining data forward.
            let remaining = captureWriteIndex - frameSamples
            if remaining > 0 {
                captureAccumulator.withUnsafeMutableBufferPointer { buf in
                    _ = memmove(buf.baseAddress!, buf.baseAddress! + frameSamples, remaining * MemoryLayout<Int16>.stride)
                }
            }
            captureWriteIndex = remaining
        }

        return Array(captureOutput.prefix(captureOutputCount))
    }

    // MARK: - Reset

    func reset() {
        renderAccumulator.removeAll(keepingCapacity: true)
        captureWriteIndex = 0
        captureOutputCount = 0
    }
}
