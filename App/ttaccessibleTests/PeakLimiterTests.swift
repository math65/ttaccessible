//
//  PeakLimiterTests.swift
//  ttaccessibleTests
//
//  The limiter on combined streams: below the ceiling it is a plain 2 ms delay, bit for
//  bit; a sum that would cross full scale never does; and after a peak the gain comes back.
//

import XCTest
@testable import ttaccessible

final class PeakLimiterTests: XCTestCase {

    private let channels = 2
    private let rate = 48_000.0

    /// Runs `frames` frames of `value` (same on both channels) through the limiter in 480-frame
    /// blocks; returns the left channel.
    private func limit(_ limiter: PeakLimiter, frames: Int, _ value: (Int) -> Float) -> [Float] {
        var left: [Float] = []
        var start = 0
        while start < frames {
            let count = min(480, frames - start)
            var block = [Float](repeating: 0, count: count * channels)
            for frame in 0 ..< count {
                let sample = value(start + frame)
                block[frame * channels] = sample
                block[frame * channels + 1] = sample
            }
            limiter.process(&block, frames: count)
            for frame in 0 ..< count { left.append(block[frame * channels]) }
            start += count
        }
        return left
    }

    func testBelowTheCeilingItIsOnlyADelay() {
        let limiter = PeakLimiter(channels: channels, sampleRate: rate)
        let input: (Int) -> Float = { Float(20_000 * sin(Double($0) * 0.01)) }
        let out = limit(limiter, frames: 4_800, input)
        let delay = PeakLimiter.lookaheadFrames
        XCTAssertTrue(out.prefix(delay).allSatisfy { $0 == 0 })
        for frame in delay ..< out.count {
            XCTAssertEqual(out[frame], input(frame - delay), "frame \(frame)")
        }
    }

    func testASumPastFullScaleNeverCrossesTheCeiling() {
        let limiter = PeakLimiter(channels: channels, sampleRate: rate)
        // Silence, then a sudden full-scale-and-a-half square wave: the hardest attack.
        let out = limit(limiter, frames: 9_600) { $0 < 1_000 ? 0 : ($0 / 50 % 2 == 0 ? 49_000 : -49_000) }
        let loudest = out.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(loudest, PeakLimiter.ceiling * 1.0001)
        XCTAssertGreaterThan(loudest, PeakLimiter.ceiling * 0.99)
    }

    func testTheGainComesBackAfterAPeak() {
        let limiter = PeakLimiter(channels: channels, sampleRate: rate)
        // One loud burst, then a quiet steady tone for half a second.
        let out = limit(limiter, frames: 48_000) { $0 < 480 ? 60_000 : 10_000 }
        XCTAssertLessThan(out[600], 9_000, "still reduced just after the burst")
        XCTAssertEqual(out.last ?? 0, 10_000, accuracy: 10, "back to unity")
        XCTAssertGreaterThan(limiter.takeDiagnostics().framesReduced, 0)
        XCTAssertEqual(limiter.takeDiagnostics().framesReduced, 0, "reset once read")
    }
}
