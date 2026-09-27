//
//  StreamMixerTests.swift
//  ttaccessibleTests
//
//  Streaming devices and applications together mixes captures that each run on their own
//  clock. StreamMixer holds a cushion per source and follows each clock by nudging its
//  rate, instead of dropping or padding audio. These pin that: a source at the mix's own
//  rate passes through bit for bit, sources add and clip rather than wrap, a source
//  running fast or slow is followed without a single dropout, bursts are ridden out, a big
//  burst is cut back once, and a stalled source goes silent and is picked up again. The
//  drift and burst tests feed a ramp, so a frame lost, repeated or badly interpolated
//  shows as a step in it. A limiter keeps a loud sum under full scale.
//

import XCTest
@testable import ttaccessible

final class StreamMixerTests: XCTestCase {

    /// A capture that grows by hand, one beat at a time.
    private final class FakeInput: StreamMixerInput {
        private(set) var samples: [Int16] = []
        var liveEdge: UInt64 { UInt64(samples.count / StreamMixer.channels) }

        func append(frames: Int, _ value: (Int) -> Int16) {
            let start = Int(liveEdge)
            for frame in start ..< start + frames {
                let sample = value(frame)
                samples.append(sample)
                samples.append(sample)
            }
        }

        func read(from cursor: UInt64, maxFrames: Int) -> ([Int16], Int, UInt64) {
            let edge = liveEdge
            guard edge > cursor, maxFrames > 0 else { return ([], 0, cursor) }
            let frames = min(maxFrames, Int(edge - cursor))
            let start = Int(cursor) * StreamMixer.channels
            return (Array(samples[start ..< start + frames * StreamMixer.channels]),
                    frames, cursor + UInt64(frames))
        }
    }

    private let beat = 480  // 10 ms at 48 kHz

    /// Two per frame, wrapping below full scale: resampled at 0.5 % off, each step of the
    /// output stays 2 ± 1 after rounding, while a lost frame makes a step of 4 and a repeated
    /// one a step of 0.
    private static let rampSlope = 2
    private static let rampPeriod = 16_000
    private static func ramp(_ frame: Int) -> Int16 { Int16((frame % rampPeriod) * rampSlope) }

    /// Fails on any step of `samples` outside 2 ± 1, ignoring the few frames around each wrap
    /// of the ramp (the cubic rings across that deliberate jump).
    private func assertUnbrokenRamp(_ samples: ArraySlice<Int16>, file: StaticString = #filePath, line: UInt = #line) {
        let top = Self.rampPeriod * Self.rampSlope
        var steps = 0
        for (previous, next) in zip(samples, samples.dropFirst()) {
            guard previous > 50, previous < top - 50, next > 50, next < top - 50 else { continue }
            let step = Int(next) - Int(previous)
            XCTAssertTrue((1 ... 3).contains(step), "step of \(step) at \(previous)", file: file, line: line)
            steps += 1
            if (1 ... 3).contains(step) == false { return }
        }
        XCTAssertGreaterThan(steps, samples.count / 2, "the ramp was playing", file: file, line: line)
    }

    /// Runs `beats` mixes, calling `feed` before each; returns every mixed frame's left sample.
    private func run(_ mixer: StreamMixer, beats: Int, feed: (Int) -> Void) -> [Int16] {
        var left: [Int16] = []
        var block: [Int16] = []
        for index in 0 ..< beats {
            feed(index)
            mixer.mix(frames: beat, into: &block)
            for frame in 0 ..< beat {
                left.append(block[frame * StreamMixer.channels])
            }
        }
        return left
    }

    func testASourceAtTheMixRatePassesThroughBitForBit() {
        let input = FakeInput()
        let mixer = StreamMixer(inputs: [input])
        let out = run(mixer, beats: 50) { _ in input.append(frames: self.beat) { Int16($0 % 30_000) } }
        // Once the cushion is built, each frame is the next input frame: a ramp stays a ramp.
        let playing = Array(out.drop(while: { $0 == 0 }))
        XCTAssertGreaterThan(playing.count, 30 * beat)
        let breaks = zip(playing, playing.dropFirst()).filter { Int($1) != Int($0) + 1 }.count
        XCTAssertEqual(breaks, 0)
        XCTAssertEqual(mixer.stats(ofSource: 0).ratio, 1)
    }

    func testSourcesAddUp() {
        let a = FakeInput(), b = FakeInput()
        let mixer = StreamMixer(inputs: [a, b])
        let out = run(mixer, beats: 20) { _ in
            a.append(frames: self.beat) { _ in 1_000 }
            b.append(frames: self.beat) { _ in 2_000 }
        }
        XCTAssertEqual(out.last, 3_000)
    }

    func testAFullScaleSumClipsInsteadOfWrapping() {
        let a = FakeInput(), b = FakeInput()
        let mixer = StreamMixer(inputs: [a, b])
        let out = run(mixer, beats: 20) { _ in
            a.append(frames: self.beat) { _ in 30_000 }
            b.append(frames: self.beat) { _ in 30_000 }
        }
        XCTAssertEqual(out.last, 32_767)
    }

    func testTheLimiterKeepsALoudSumUnderFullScale() {
        let a = FakeInput(), b = FakeInput()
        let mixer = StreamMixer(inputs: [a, b], limiter: PeakLimiter(channels: StreamMixer.channels,
                                                                      sampleRate: StreamMixer.sampleRate))
        // Two sines near full scale: a voice over music mastered hot.
        let out = run(mixer, beats: 200) { _ in
            a.append(frames: self.beat) { Int16(30_000 * sin(Double($0) * 2 * .pi * 440 / 48_000)) }
            b.append(frames: self.beat) { Int16(30_000 * sin(Double($0) * 2 * .pi * 660 / 48_000)) }
        }
        let loudest = out.map { abs(Int($0)) }.max() ?? 0
        XCTAssertLessThanOrEqual(loudest, Int(PeakLimiter.ceiling.rounded(.up)))
        XCTAssertGreaterThan(loudest, 30_000, "limited, not merely turned down")
    }

    func testASourceRunningFastIsFollowedWithoutADropout() {
        let input = FakeInput()
        let mixer = StreamMixer(inputs: [input])
        // One extra frame per beat: about 2 000 ppm fast, far worse than any real device.
        let out = run(mixer, beats: 3_000) { _ in input.append(frames: self.beat + 1, Self.ramp) }
        let stats = mixer.stats(ofSource: 0)
        XCTAssertEqual(stats.underruns, 0)
        XCTAssertEqual(stats.skips, 0)
        XCTAssertGreaterThan(stats.ratio, 1.001)
        XCTAssertLessThan(stats.fill, Double(StreamMixer.overrunFrames))
        assertUnbrokenRamp(out.suffix(2_000 * beat))
    }

    func testASourceRunningSlowIsFollowedWithoutADropout() {
        let input = FakeInput()
        let mixer = StreamMixer(inputs: [input])
        let out = run(mixer, beats: 3_000) { _ in input.append(frames: self.beat - 1, Self.ramp) }
        let stats = mixer.stats(ofSource: 0)
        XCTAssertEqual(stats.underruns, 0)
        XCTAssertEqual(stats.skips, 0)
        XCTAssertLessThan(stats.ratio, 0.999)
        assertUnbrokenRamp(out.suffix(2_000 * beat))
    }

    func testBurstsAreRiddenOut() {
        let input = FakeInput()
        let mixer = StreamMixer(inputs: [input])
        // 30 ms at a time, every third beat — how a bursty backend delivers.
        let out = run(mixer, beats: 600) { index in
            if index % 3 == 0 { input.append(frames: 3 * self.beat, Self.ramp) }
        }
        XCTAssertEqual(mixer.stats(ofSource: 0).underruns, 0)
        assertUnbrokenRamp(out.suffix(500 * beat))
    }

    func testABigBurstIsCutBackToTheCushionOnce() {
        let input = FakeInput()
        let mixer = StreamMixer(inputs: [input])
        let out = run(mixer, beats: 200) { index in
            input.append(frames: self.beat + (index == 50 ? 20_000 : 0), Self.ramp)
        }
        let stats = mixer.stats(ofSource: 0)
        XCTAssertEqual(stats.skips, 1)
        XCTAssertEqual(stats.underruns, 0)
        assertUnbrokenRamp(out.suffix(100 * beat))
    }

    func testAStalledSourceGoesSilentAndComesBack() {
        let input = FakeInput()
        let mixer = StreamMixer(inputs: [input])
        let out = run(mixer, beats: 100) { index in
            if (40 ..< 60).contains(index) == false {
                input.append(frames: self.beat) { _ in 1_000 }
            }
        }
        XCTAssertEqual(mixer.stats(ofSource: 0).underruns, 1)
        XCTAssertTrue(out[(50 * beat) ..< (60 * beat)].allSatisfy { $0 == 0 }, "silent while stalled")
        XCTAssertTrue(out.suffix(20 * beat).allSatisfy { $0 == 1_000 }, "playing again")
    }
}
