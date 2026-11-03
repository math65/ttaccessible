//
//  EchoCancellerRemixTests.swift
//  ttaccessibleTests
//
//  The AEC reference used to be dropped whenever its channel count differed from the AEC's
//  (the stereo speaker tap in a mono channel), leaving AEC3 with no far end at all. It is now
//  remixed: averaged down to mono, duplicated up from mono.
//

import XCTest
@testable import ttaccessible

final class EchoCancellerRemixTests: XCTestCase {

    private func remix(_ input: [Int16], from: Int, to: Int) -> [Int16] {
        let frames = input.count / from
        var output: [Int16] = []
        input.withUnsafeBufferPointer { buffer in
            EchoCanceller.remix(buffer.baseAddress!, frames: frames, from: from, to: to, into: &output)
        }
        return Array(output.prefix(frames * to))
    }

    func testStereoToMonoAveragesBothChannels() {
        let stereo: [Int16] = [100, 300, -200, -400, 1000, 0]
        XCTAssertEqual(remix(stereo, from: 2, to: 1), [200, -300, 500])
    }

    func testStereoToMonoDoesNotOverflowAtFullScale() {
        let stereo: [Int16] = [.max, .max, .min, .min]
        XCTAssertEqual(remix(stereo, from: 2, to: 1), [.max, .min])
    }

    func testMonoToStereoDuplicatesTheChannel() {
        let mono: [Int16] = [10, -20, 30]
        XCTAssertEqual(remix(mono, from: 1, to: 2), [10, 10, -20, -20, 30, 30])
    }

    func testMultichannelToStereoKeepsTheFirstPair() {
        let quad: [Int16] = [1, 2, 3, 4, 5, 6, 7, 8]
        XCTAssertEqual(remix(quad, from: 4, to: 2), [1, 2, 5, 6])
    }

    func testOutputBufferIsReusedWhenLargeEnough() {
        var output = [Int16](repeating: 99, count: 16)
        let stereo: [Int16] = [2, 4]
        stereo.withUnsafeBufferPointer { buffer in
            EchoCanceller.remix(buffer.baseAddress!, frames: 1, from: 2, to: 1, into: &output)
        }
        XCTAssertEqual(output.count, 16)
        XCTAssertEqual(output[0], 3)
    }
}
