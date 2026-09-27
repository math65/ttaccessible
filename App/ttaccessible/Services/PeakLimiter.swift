//
//  PeakLimiter.swift
//  ttaccessible
//
//  Keeps a sum of streamed sources under full scale. Several sources mixed at unity — a
//  voice over music mastered near 0 dBFS — add up past what Int16 can hold, and a hard
//  clip there is audible distortion. Below the ceiling this changes nothing but a fixed
//  2 ms delay; a peak that would cross it is met by a gain that has already eased down
//  across that look-ahead, and that eases back up afterwards. Only combined streams run
//  through it (StreamMixer in MixingCaptureBackend): a single source is never summed.
//

import Foundation

final class PeakLimiter {

    /// −0.1 dBFS: the loudest sample the limiter lets out.
    static let ceiling: Float = 32_767 * 0.9886
    /// How far ahead a peak is seen, and so the delay the limiter adds: 2 ms at 48 kHz.
    static let lookaheadFrames = 96
    /// How long the gain takes to come most of the way back after a peak.
    static let releaseSeconds = 0.05

    private let channels: Int
    private let releaseCoefficient: Float
    /// The last `lookaheadFrames` input frames, interleaved, waiting to be played.
    private var delayLine: [Float]
    /// The gain each of the last `lookaheadFrames + 1` frames needs to stay under the ceiling.
    private var requiredGains: [Float]
    /// The last `lookaheadFrames` envelope values, averaged into the applied gain.
    private var envelopes: [Float]
    private var envelopeSum: Double
    private var envelope: Float = 1
    private var delayIndex = 0
    private var requiredIndex = 0

    /// Frames played with the gain below unity, and the deepest gain, since the last read of
    /// `takeDiagnostics()` — what shows in audio.log whether the limiter is working.
    private var framesReduced = 0
    private var deepestGain: Float = 1

    init(channels: Int, sampleRate: Double) {
        self.channels = channels
        releaseCoefficient = Float(1 - exp(-1 / (Self.releaseSeconds * sampleRate)))
        delayLine = [Float](repeating: 0, count: Self.lookaheadFrames * channels)
        requiredGains = [Float](repeating: 1, count: Self.lookaheadFrames + 1)
        envelopes = [Float](repeating: 1, count: Self.lookaheadFrames)
        envelopeSum = Double(Self.lookaheadFrames)
    }

    static func lookaheadSeconds(sampleRate: Double) -> Double {
        Double(lookaheadFrames) / sampleRate
    }

    /// Limits `frames` interleaved frames of `samples` in place, delayed by `lookaheadFrames`.
    ///
    /// Why it never passes the ceiling: the gain applied to a frame is the average of the
    /// envelope over the look-ahead that follows it, and every one of those envelope values
    /// is at most the smallest gain required over a window that contains that frame.
    func process(_ samples: inout [Float], frames: Int) {
        let lookahead = Self.lookaheadFrames
        samples.withUnsafeMutableBufferPointer { buffer in
            for frame in 0 ..< frames {
                let base = frame * channels

                var peak: Float = 0
                for channel in 0 ..< channels {
                    peak = max(peak, abs(buffer[base + channel]))
                }
                requiredGains[requiredIndex] = peak > Self.ceiling ? Self.ceiling / peak : 1
                requiredIndex = (requiredIndex + 1) % requiredGains.count
                var windowMinimum: Float = 1
                for gain in requiredGains where gain < windowMinimum {
                    windowMinimum = gain
                }

                // Down at once to what the window needs, back up gently.
                envelope = min(windowMinimum, envelope + (1 - envelope) * releaseCoefficient)
                envelopeSum += Double(envelope - envelopes[delayIndex])
                envelopes[delayIndex] = envelope
                let gain = min(1, Float(envelopeSum / Double(lookahead)))

                let delayed = delayIndex * channels
                for channel in 0 ..< channels {
                    let incoming = buffer[base + channel]
                    buffer[base + channel] = delayLine[delayed + channel] * gain
                    delayLine[delayed + channel] = incoming
                }

                delayIndex += 1
                if delayIndex == lookahead {
                    delayIndex = 0
                    // Keeps the running sum from drifting over hours of streaming.
                    envelopeSum = envelopes.reduce(0) { $0 + Double($1) }
                }

                if gain < 1 {
                    framesReduced += 1
                    deepestGain = min(deepestGain, gain)
                }
            }
        }
    }

    /// Frames reduced and the deepest gain since the last call, then resets both.
    func takeDiagnostics() -> (framesReduced: Int, deepestGain: Float) {
        defer {
            framesReduced = 0
            deepestGain = 1
        }
        return (framesReduced, deepestGain)
    }
}
