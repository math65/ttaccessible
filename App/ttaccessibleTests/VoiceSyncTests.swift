//
//  VoiceSyncTests.swift
//  ttaccessibleTests
//
//  Unit checks for the voice↔stream sync pieces: MediaSyncEstimator's
//  position-trust + snap logic against a synthetic MediaSyncClock, and
//  VoiceSyncDelayLine's ordering guarantee.
//

import XCTest
@testable import ttaccessible

final class VoiceSyncTests: XCTestCase {

    /// Ring with a known live edge: 48 000 frames (1 s at the stream rate).
    private func makeRing(liveEdgeFrames: Int = 48_000) -> AudioDeviceStreamSource.PCMRing {
        let ring = AudioDeviceStreamSource.PCMRing(capacityFrames: 96_000, channels: 2)
        let silence = [Int16](repeating: 0, count: liveEdgeFrames * 2)
        silence.withUnsafeBufferPointer { buffer in
            ring.write(buffer.baseAddress!, frames: liveEdgeFrames)
        }
        return ring
    }

    func testEstimatorSnapsToConstantLatencyWithTrustedIndex() {
        let ring = makeRing()
        let clock = MediaSyncClock(ring: ring)
        let estimator = MediaSyncEstimator()
        estimator.beginSession(clock: clock, preservingSnap: false)

        // Media frame p == mediaFrameBase with captureCursorBase held half a
        // second behind the live edge → constant 0.5 s latency per sample.
        let blockFrames = 960
        for step in 1...16 {
            let position = UInt64(step * blockFrames)
            clock.update(mediaFrameBase: position, captureCursorBase: 24_000, watermark: 0)
            estimator.ingest(sampleIndex: UInt32(position), frames: blockFrames, sampleRate: 48_000)
            Thread.sleep(forTimeInterval: 0.14)
        }

        let snapped = estimator.snappedDelaySeconds
        XCTAssertNotNil(snapped, "estimator never snapped after >2 s of samples")
        XCTAssertEqual(snapped ?? 0, 0.5, accuracy: 0.02)
    }

    func testEstimatorFallsBackToAccumulatorWhenIndexUnmaintained() {
        let ring = makeRing()
        let clock = MediaSyncClock(ring: ring)
        let estimator = MediaSyncEstimator()
        estimator.beginSession(clock: clock, preservingSnap: false)

        // uSampleIndex constant 0 (like our own inserts): the accumulator must
        // carry the position instead. Positions advance blockFrames per ingest.
        let blockFrames = 4_800  // 100 ms — crosses the 1 s untrusted threshold fast
        for step in 1...16 {
            let position = UInt64(step * blockFrames)
            clock.update(mediaFrameBase: position, captureCursorBase: 33_600, watermark: 0)
            estimator.ingest(sampleIndex: 0, frames: blockFrames, sampleRate: 48_000)
            Thread.sleep(forTimeInterval: 0.14)
        }

        // The estimator measures each block's START, one block behind the
        // publish base here: captureFrame = 33 600 − 4 800, so latency =
        // (48 000 − 28 800) / 48 000 = 0.4 s.
        let snapped = estimator.snappedDelaySeconds
        XCTAssertNotNil(snapped, "estimator never snapped in accumulator mode")
        XCTAssertEqual(snapped ?? 0, 0.4, accuracy: 0.02)
    }

    func testClockRefusesPositionsAcrossDiscontinuity() {
        let ring = makeRing()
        let clock = MediaSyncClock(ring: ring)
        clock.update(mediaFrameBase: 10_000, captureCursorBase: 20_000, watermark: 5_000)

        XCTAssertNil(clock.latencySeconds(forMediaFrame48k: 4_000),
                     "position older than the pad/skip watermark must not map")
        XCTAssertNil(clock.latencySeconds(forMediaFrame48k: 12_000),
                     "position newer than the last publish must not map")
        XCTAssertEqual(clock.latencySeconds(forMediaFrame48k: 10_000) ?? 0,
                       (48_000 - 20_000) / 48_000.0, accuracy: 0.001)
    }

    func testDelayLineNeverReordersWhenDelayShrinks() {
        let queue = DispatchQueue(label: "voice-sync-test")
        let delayLine = VoiceSyncDelayLine(queue: queue)
        var inserted: [Int32] = []
        delayLine.insertHandler = { chunk in
            inserted.append(chunk.streamID)
            return true
        }

        func chunk(_ id: Int32) -> AdvancedMicrophoneAudioChunk {
            AdvancedMicrophoneAudioChunk(streamID: id, sampleRate: 48_000, channels: 1,
                                         sampleCount: 480, samples: [Int16](repeating: 0, count: 480))
        }

        queue.sync {
            delayLine.enqueue(chunk(1), delaySeconds: 0.20, isSilent: false)
            // Delay collapsed to zero (stream stopped) — must still come after 1.
            delayLine.enqueue(chunk(2), delaySeconds: 0, isSilent: false)
            delayLine.enqueue(chunk(3), delaySeconds: 0, isSilent: false)
        }
        Thread.sleep(forTimeInterval: 0.45)

        queue.sync {
            XCTAssertTrue(delayLine.isEmpty, "delay line did not drain")
        }
        XCTAssertEqual(inserted, [1, 2, 3])
    }

    func testDelayLineShrinksByDroppingSilenceWhenOverTarget() {
        let queue = DispatchQueue(label: "voice-sync-shrink-test")
        let delayLine = VoiceSyncDelayLine(queue: queue)
        var inserted: [Int32] = []
        delayLine.insertHandler = { chunk in
            inserted.append(chunk.streamID)
            return true
        }

        func chunk(_ id: Int32) -> AdvancedMicrophoneAudioChunk {
            AdvancedMicrophoneAudioChunk(streamID: id, sampleRate: 48_000, channels: 1,
                                         sampleCount: 480, samples: [Int16](repeating: 0, count: 480))
        }

        queue.sync {
            // Backlog built at a large delay…
            delayLine.enqueue(chunk(1), delaySeconds: 0.30, isSilent: false)
            // …then the target shrinks: silent chunks are DROPPED while the
            // backlog exceeds the target (+hysteresis), voiced ones are kept.
            delayLine.enqueue(chunk(2), delaySeconds: 0.05, isSilent: true)
            delayLine.enqueue(chunk(3), delaySeconds: 0.05, isSilent: false)
            // Silence with no over-target backlog is NOT dropped: target far
            // beyond the queued deadlines keeps the stream continuous.
            delayLine.enqueue(chunk(4), delaySeconds: 0.40, isSilent: true)
        }
        Thread.sleep(forTimeInterval: 0.75)

        queue.sync {
            XCTAssertTrue(delayLine.isEmpty, "delay line did not drain")
        }
        XCTAssertEqual(inserted, [1, 3, 4], "silent chunk 2 should be dropped to shrink; 4 kept")
    }
}
