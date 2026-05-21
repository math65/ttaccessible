//
//  AudioPCMResampler.swift
//  ttaccessible
//

import Foundation

/// Linear-interpolation resampler for interleaved Int16 PCM.
enum AudioPCMResampler {
    struct Result {
        let samples: [Int16]
        let frameCount: Int
    }

    static func resampleInterleaved(
        _ samples: [Int16],
        frameCount: Int,
        channels: Int,
        inputRate: Double,
        outputRate: Double
    ) -> Result {
        guard frameCount > 0, channels > 0, inputRate > 0, outputRate > 0 else {
            return Result(samples: samples, frameCount: frameCount)
        }

        if abs(inputRate - outputRate) < 0.5 {
            return Result(samples: samples, frameCount: frameCount)
        }

        let ratio = outputRate / inputRate
        let outputFrames = max(1, Int((Double(frameCount) * ratio).rounded()))
        let outputSampleCount = outputFrames * channels
        var output = [Int16](repeating: 0, count: outputSampleCount)

        for outFrame in 0..<outputFrames {
            let srcPosition = Double(outFrame) / ratio
            let srcIndex = Int(srcPosition)
            let fraction = srcPosition - Double(srcIndex)
            let nextIndex = min(srcIndex + 1, frameCount - 1)

            for channel in 0..<channels {
                let idx0 = srcIndex * channels + channel
                let idx1 = nextIndex * channels + channel
                let sample0 = Double(samples[idx0])
                let sample1 = Double(samples[idx1])
                let value = sample0 + fraction * (sample1 - sample0)
                output[outFrame * channels + channel] = Int16(clamping: Int(value.rounded()))
            }
        }

        return Result(samples: output, frameCount: outputFrames)
    }
}

#if DEBUG
enum AudioPCMResamplerSelfTest {
    @discardableResult
    static func runAll() -> Bool {
        let inputFrames = 441
        let channels = 1
        var input = [Int16](repeating: 0, count: inputFrames * channels)
        for frame in 0..<inputFrames {
            let t = Double(frame) / 44_100.0
            input[frame] = Int16((sin(2 * .pi * 440 * t) * 16_000).rounded())
        }

        let result = AudioPCMResampler.resampleInterleaved(
            input,
            frameCount: inputFrames,
            channels: channels,
            inputRate: 44_100,
            outputRate: 48_000
        )

        let expectedFrames = max(1, Int((Double(inputFrames) * (48_000.0 / 44_100.0)).rounded()))
        guard result.frameCount == expectedFrames,
              result.samples.count == expectedFrames * channels else {
            AudioLogger.log("AudioPCMResamplerSelfTest: frame count mismatch got=%d expected=%d", result.frameCount, expectedFrames)
            return false
        }

        let peak = result.samples.map { abs(Int32($0)) }.max() ?? 0
        guard peak > 1_000 else {
            AudioLogger.log("AudioPCMResamplerSelfTest: resampled signal too quiet peak=%d", peak)
            return false
        }

        AudioLogger.log("AudioPCMResamplerSelfTest: passed frames=%d peak=%d", result.frameCount, peak)
        return true
    }
}
#endif
