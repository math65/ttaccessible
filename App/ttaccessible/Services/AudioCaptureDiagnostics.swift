//
//  AudioCaptureDiagnostics.swift
//  ttaccessible
//

import Foundation

/// Throttled counters for microphone capture and TeamTalk injection diagnostics.
final class AudioCaptureDiagnostics {
    static let shared = AudioCaptureDiagnostics()

    private let lock = NSLock()
    private var lastLogTime: CFAbsoluteTime = 0
    // Heartbeat cadence. The counters are cumulative, so a sparse line still shows
    // the full trend — keep it low-volume so a days-long session doesn't bloat the log.
    private let logInterval: CFAbsoluteTime = 30.0

    private(set) var capturePath = "none"
    private(set) var captureSampleRate: Int = 0
    private(set) var outputSampleRate: Int = 0

    private var chunkCount: UInt64 = 0
    private var insertAttemptCount: UInt64 = 0
    private var insertSuccessCount: UInt64 = 0
    private var insertDropCount: UInt64 = 0
    private var gatedDropCount: UInt64 = 0
    private var peakSample: Int32 = 0
    private var nonZeroChunkCount: UInt64 = 0
    private var aecPassthroughCount: UInt64 = 0

    private init() {}

    func resetForNewCapture(path: String, captureRate: Int, outputRate: Int) {
        lock.lock()
        capturePath = path
        captureSampleRate = captureRate
        outputSampleRate = outputRate
        chunkCount = 0
        insertAttemptCount = 0
        insertSuccessCount = 0
        insertDropCount = 0
        gatedDropCount = 0
        peakSample = 0
        nonZeroChunkCount = 0
        aecPassthroughCount = 0
        lastLogTime = 0
        lock.unlock()
        AudioLogger.log(
            "capture start: path=%@ captureRate=%d outputRate=%d",
            path,
            captureRate,
            outputRate
        )
    }

    func recordChunk(sampleRate: Int32, peak: Int32, nonZero: Bool) {
        lock.lock()
        chunkCount += 1
        if peak > peakSample {
            peakSample = peak
        }
        if nonZero {
            nonZeroChunkCount += 1
        }
        let shouldLog = shouldEmitLogLocked()
        let snapshot = shouldLog ? snapshotLocked(chunkRate: Int(sampleRate)) : nil
        lock.unlock()

        if let snapshot {
            AudioLogger.log(snapshot)
        }
    }

    func recordAECPassthrough() {
        lock.lock()
        aecPassthroughCount += 1
        lock.unlock()
    }

    func recordInsertAttempt(sampleRate: Int32, accepted: Bool, gated: Bool) {
        lock.lock()
        if gated {
            gatedDropCount += 1
        } else {
            insertAttemptCount += 1
            if accepted {
                insertSuccessCount += 1
            } else {
                insertDropCount += 1
            }
        }
        let shouldLog = shouldEmitLogLocked()
        let snapshot = shouldLog ? snapshotLocked(chunkRate: Int(sampleRate)) : nil
        lock.unlock()

        if let snapshot {
            AudioLogger.log(snapshot)
        }
    }

    private func shouldEmitLogLocked() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLogTime >= logInterval else {
            return false
        }
        lastLogTime = now
        return true
    }

    private func snapshotLocked(chunkRate: Int) -> String {
        String(
            format: "audio diag: path=%@ captureRate=%d outputRate=%d chunkRate=%d chunks=%llu nonzero=%llu peak=%d inserts=%llu ok=%llu queueFull=%llu gated=%llu aecPass=%llu",
            capturePath,
            captureSampleRate,
            outputSampleRate,
            chunkRate,
            chunkCount,
            nonZeroChunkCount,
            peakSample,
            insertAttemptCount,
            insertSuccessCount,
            insertDropCount,
            gatedDropCount,
            aecPassthroughCount
        )
    }
}
