//
//  OutputChannelCrossfadeTests.swift
//  ttaccessibleTests
//
//  The render-thread crossfade that replaces an instant plane remap. Pure C
//  arithmetic over plain buffers — no CoreAudio, no device, no AppKit.
//

import XCTest
@testable import ttaccessible

final class OutputChannelCrossfadeTests: XCTestCase {

    private let devChannels = 8
    private let frameCount = 128

    /// A constant full-scale stereo signal: any discontinuity in the output is
    /// then the remap's doing and nothing else.
    private func makePull() -> UnsafeMutablePointer<Int16> {
        let pull = UnsafeMutablePointer<Int16>.allocate(capacity: frameCount * 2)
        for i in 0..<(frameCount * 2) { pull[i] = 16384 }
        return pull
    }

    private func withPlanes(_ body: (UnsafeMutablePointer<UnsafeMutablePointer<Float>?>) -> Void) {
        var buffers: [UnsafeMutablePointer<Float>] = []
        let table = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: devChannels)
        for ch in 0..<devChannels {
            let plane = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
            plane.initialize(repeating: 0, count: frameCount)
            buffers.append(plane)
            table[ch] = plane
        }
        body(table)
        buffers.forEach { $0.deallocate() }
        table.deallocate()
    }

    /// Steady state: gain smoothing off (coeff 0) so the only thing shaping the
    /// output is the envelope under test.
    private func renderSteady(_ planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>,
                              pull: UnsafeMutablePointer<Int16>,
                              left: Int32, right: Int32) {
        _ = ttac_render_planes(planes, Int32(devChannels), pull,
                               Int32(frameCount), Int32(frameCount),
                               1, 1, 0, left, right)
    }

    /// One callback of a remap crossfade, exactly as the render callback does it.
    private func renderCrossfade(_ planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>,
                                 pull: UnsafeMutablePointer<Int16>,
                                 from: (Int32, Int32), to: (Int32, Int32),
                                 start: Float, end: Float) {
        ttac_clear_planes(planes, Int32(devChannels), Int32(frameCount))
        _ = ttac_mix_into_planes(planes, Int32(devChannels), pull,
                                 Int32(frameCount), Int32(frameCount),
                                 1, 1, 0, from.0, from.1, 1 - start, 1 - end)
        _ = ttac_mix_into_planes(planes, Int32(devChannels), pull,
                                 Int32(frameCount), Int32(frameCount),
                                 1, 1, 0, to.0, to.1, start, end)
    }

    /// The point of the ramp: the outgoing pair leaves from exactly where it
    /// was, the incoming pair arrives at exactly full level, and neither jumps.
    func testCrossfadeHasNoStepAtEitherEnd() {
        let pull = makePull()
        defer { pull.deallocate() }

        withPlanes { planes in
            renderSteady(planes, pull: pull, left: 0, right: 1)
            let steady = planes[0]![frameCount - 1]
            XCTAssertGreaterThan(steady, 0)

            renderCrossfade(planes, pull: pull, from: (0, 1), to: (4, 5), start: 0, end: 1)

            // Outputs 1/2 continue from the level they were at, and reach silence.
            XCTAssertEqual(planes[0]![0], steady, accuracy: steady * 0.02,
                           "the old pair stepped down instead of ramping")
            XCTAssertEqual(planes[0]![frameCount - 1], 0, accuracy: steady * 0.02)

            // Outputs 5/6 start from silence rather than snapping to full.
            XCTAssertEqual(planes[4]![0], 0, accuracy: steady * 0.02,
                           "the new pair stepped up instead of ramping")
            XCTAssertEqual(planes[4]![frameCount - 1], steady, accuracy: steady * 0.02)
        }
    }

    /// Frame to frame, nothing moves by more than one ramp step — that is what
    /// "no click" means. An instant swap would show a full-scale jump here.
    func testNoPlaneJumpsWithinTheCrossfade() {
        let pull = makePull()
        defer { pull.deallocate() }

        withPlanes { planes in
            renderSteady(planes, pull: pull, left: 0, right: 1)
            let steady = planes[0]![frameCount - 1]
            renderCrossfade(planes, pull: pull, from: (0, 1), to: (4, 5), start: 0, end: 1)

            let maxStep = steady / Float(frameCount) * 2
            for ch in [0, 1, 4, 5] {
                for frame in 1..<frameCount {
                    let delta = abs(planes[ch]![frame] - planes[ch]![frame - 1])
                    XCTAssertLessThanOrEqual(delta, maxStep,
                                             "plane \(ch) jumped \(delta) at frame \(frame)")
                }
            }
        }
    }

    /// Both pairs carry the same mix, so what the room hears is unchanged
    /// through the fade — it moves across the outputs without dipping.
    func testTotalLevelIsConstantThroughTheCrossfade() {
        let pull = makePull()
        defer { pull.deallocate() }

        withPlanes { planes in
            renderSteady(planes, pull: pull, left: 0, right: 1)
            let steady = planes[0]![frameCount - 1]
            renderCrossfade(planes, pull: pull, from: (0, 1), to: (4, 5), start: 0, end: 1)

            for frame in 0..<frameCount {
                XCTAssertEqual(planes[0]![frame] + planes[4]![frame], steady,
                               accuracy: steady * 0.02,
                               "level dipped at frame \(frame)")
            }
        }
    }

    /// A fade longer than one buffer arrives in segments; the segments must join
    /// without a step where one callback ends and the next begins.
    func testFadeSpanningTwoCallbacksJoinsCleanly() {
        let pull = makePull()
        defer { pull.deallocate() }

        withPlanes { planes in
            renderSteady(planes, pull: pull, left: 0, right: 1)
            let steady = planes[0]![frameCount - 1]

            renderCrossfade(planes, pull: pull, from: (0, 1), to: (4, 5), start: 0, end: 0.5)
            let firstHalfEndsOld = planes[0]![frameCount - 1]
            let firstHalfEndsNew = planes[4]![frameCount - 1]
            XCTAssertEqual(firstHalfEndsOld, steady * 0.5, accuracy: steady * 0.02)

            renderCrossfade(planes, pull: pull, from: (0, 1), to: (4, 5), start: 0.5, end: 1)
            XCTAssertEqual(planes[0]![0], firstHalfEndsOld, accuracy: steady * 0.02,
                           "the old pair stepped between callbacks")
            XCTAssertEqual(planes[4]![0], firstHalfEndsNew, accuracy: steady * 0.02,
                           "the new pair stepped between callbacks")
            XCTAssertEqual(planes[0]![frameCount - 1], 0, accuracy: steady * 0.02)
            XCTAssertEqual(planes[4]![frameCount - 1], steady, accuracy: steady * 0.02)
        }
    }

    /// Planes outside the fade stay silent throughout — nothing is left ringing
    /// on an output the mix has moved off.
    func testUninvolvedPlanesStaySilent() {
        let pull = makePull()
        defer { pull.deallocate() }

        withPlanes { planes in
            renderCrossfade(planes, pull: pull, from: (0, 1), to: (4, 5), start: 0.3, end: 0.7)
            for ch in [2, 3, 6, 7] {
                for frame in 0..<frameCount {
                    XCTAssertEqual(planes[ch]![frame], 0, accuracy: 0.0001,
                                   "plane \(ch) was written at frame \(frame)")
                }
            }
        }
    }

    /// A mono selection sums L/R onto one plane, and crossfades the same way.
    func testCrossfadeToMonoSelection() {
        let pull = makePull()
        defer { pull.deallocate() }

        withPlanes { planes in
            renderSteady(planes, pull: pull, left: 0, right: 1)
            let steady = planes[0]![frameCount - 1]

            renderCrossfade(planes, pull: pull, from: (0, 1), to: (6, -1), start: 0, end: 1)
            XCTAssertEqual(planes[6]![0], 0, accuracy: steady * 0.02)
            XCTAssertEqual(planes[6]![frameCount - 1], steady, accuracy: steady * 0.02)
            XCTAssertEqual(planes[7]![frameCount - 1], 0, accuracy: 0.0001,
                           "a mono selection must not write the next plane")
        }
    }
}
