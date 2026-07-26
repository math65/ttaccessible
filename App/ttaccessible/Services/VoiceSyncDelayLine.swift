//
//  VoiceSyncDelayLine.swift
//  ttaccessible
//
//  Voice↔stream sync for live-capture media streams ("Stream Audio Device"):
//  the media path carries ~0.7–1 s of sender-side latency (operating buffer +
//  the SDK/FFmpeg open's standing latency), while voice inserts near-live —
//  so a singer riding their own streamed instrument arrives out of time at
//  receivers. MediaSyncEstimator measures the media path's real latency from
//  the SDK's local playback of our own stream (position mapped back to capture
//  time via MediaSyncClock), and VoiceSyncDelayLine delays outgoing voice
//  chunks by that amount so both streams align at transmit time.
//

import Foundation

/// Measures how far behind live the outgoing media stream runs.
///
/// Thread-safe: `ingest` is called from AudioBlockPump's queue for every local
/// media block; the controller reads the snapped delay on its own queue.
final class MediaSyncEstimator {

    /// Used when measurement is unavailable (no output engine running, mapping
    /// never established): the empirically-typical sender-side media latency
    /// of the Opus loopback path.
    static let fallbackDelaySeconds = 0.7

    /// Measurement window before the delay is snapped.
    private static let snapWindowSeconds = 2.0
    private static let snapMinimumSamples = 10
    /// Drift tracking: the media path is paced by wall clock while capture
    /// runs on the device's clock, so the media latency CREEPS a few ms per
    /// minute of clock skew (and steps when the server skip-ahead fires).
    /// Re-snap whenever the rolling median moves this far — adoptions apply
    /// only at silent chunks, where a small grow-gap or silence-skip shrink
    /// is inaudible, so tracking can afford to be tight.
    private static let resnapThresholdSeconds = 0.03
    private static let resnapWindowSeconds = 3.0
    private static let resnapMinimumSamples = 20
    /// Discard nonsense latencies (mapping glitch, cross-session block).
    private static let sanityMaxSeconds = 5.0
    /// Periodic diagnostic cadence (drift investigations read these).
    private static let diagIntervalSeconds = 5.0

    private let lock = NSLock()
    private var clock: MediaSyncClock?
    private var sessionStart: DispatchTime = .now()
    private var snapped: Double?
    private var pendingResnap: Double?
    private var snapSamples: [Double] = []
    private var rollingSamples: [(at: DispatchTime, latency: Double)] = []

    // uSampleIndex trust state (its semantics for local media blocks are
    // undocumented — it may be a real cumulative position, or constant 0 like
    // the value we ourselves pass on insert). Trust it only after it tracks an
    // nSamples accumulator; otherwise the accumulator is the position source.
    private enum IndexTrust { case undecided(matches: Int); case trusted; case untrusted }
    private var indexTrust = IndexTrust.undecided(matches: 0)
    private var accumulatedNativeFrames: UInt64 = 0
    /// The accumulator seeds from the FIRST block's index: if early blocks were
    /// dropped before the event was enabled, starting the accumulator at 0
    /// would bake that offset into every measurement. (An unmaintained
    /// constant-0 index seeds 0 — harmless.)
    private var accumulatorSeeded = false
    private var lastIndex: UInt32 = 0
    private var loggedSnap = false
    private var diagLastAt: DispatchTime = .now()

    /// Begin measuring a stream session. `preservingSnap` keeps the previous
    /// snapped delay as a provisional value during re-measurement (channel
    /// switch restarts the same source); a fresh stream start passes false.
    func beginSession(clock: MediaSyncClock, preservingSnap: Bool) {
        lock.lock()
        self.clock = clock
        sessionStart = .now()
        if preservingSnap == false { snapped = nil }
        pendingResnap = nil
        snapSamples.removeAll()
        rollingSamples.removeAll()
        indexTrust = .undecided(matches: 0)
        accumulatedNativeFrames = 0
        accumulatorSeeded = false
        lastIndex = 0
        loggedSnap = false
        lock.unlock()
    }

    func endSession() {
        lock.lock()
        clock = nil
        snapped = nil
        pendingResnap = nil
        snapSamples.removeAll()
        rollingSamples.removeAll()
        lock.unlock()
    }

    /// The snapped voice delay, nil until measurement has settled (callers
    /// apply the fallback + manual trim themselves).
    var snappedDelaySeconds: Double? {
        lock.lock()
        defer { lock.unlock() }
        return snapped
    }

    /// Whether a measurement session is live (a snap is coming). Callers use
    /// this to WAIT (delay 0) instead of applying the blind fallback — an
    /// early too-large delay can never fully unwind under a continuously-open
    /// mic, so guessing high is worse than starting live.
    var isMeasuring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return clock != nil
    }

    /// Adopt a watchdog re-snap. Call only while the voice delay FIFO is empty
    /// (a transmission pause) — changing the delay mid-phrase would gap or
    /// overlap the voice. Returns the newly-adopted delay, if any.
    @discardableResult
    func adoptPendingResnapIfAny() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let pending = pendingResnap else { return nil }
        pendingResnap = nil
        let previous = snapped
        snapped = pending
        // Every adoption is logged: unlogged small steps can ratchet the
        // delay far without leaving a trace (learned the hard way).
        AudioLogger.log("voice sync: delay tracked %.0f → %.0f ms",
                        (previous ?? 0) * 1000, pending * 1000)
        return pending
    }

    /// Feed one local-media audio block (from AudioBlockPump's drain).
    func ingest(sampleIndex: UInt32, frames: Int, sampleRate: Int) {
        guard frames > 0, sampleRate > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let clock else { return }

        // Session-reset detection: the SDK restarts the media stream (channel
        // switch) → position restarts. Re-measure, holding the previous snap
        // as provisional so voice stays roughly aligned meanwhile.
        if case .trusted = indexTrust, sampleIndex < lastIndex {
            AudioLogger.log("voice sync: media position reset (index %u → %u), re-measuring",
                            lastIndex, sampleIndex)
            resetMeasurementLocked()
        }

        if accumulatorSeeded == false {
            accumulatedNativeFrames = UInt64(sampleIndex)
            accumulatorSeeded = true
        }

        let positionNative: UInt64
        switch indexTrust {
        case .trusted:
            positionNative = UInt64(sampleIndex)
            // A forward jump beyond this block's span is a dropped-block gap;
            // the index is authoritative, resync the accumulator.
            accumulatedNativeFrames = UInt64(sampleIndex) &+ UInt64(frames)
        case .untrusted:
            positionNative = accumulatedNativeFrames
            accumulatedNativeFrames &+= UInt64(frames)
        case .undecided(let matches):
            positionNative = accumulatedNativeFrames
            let indexMatches = UInt64(sampleIndex) == accumulatedNativeFrames
            accumulatedNativeFrames &+= UInt64(frames)
            if indexMatches, sampleIndex > 0 {
                let newMatches = matches + 1
                indexTrust = newMatches >= 10 ? .trusted : .undecided(matches: newMatches)
                if case .trusted = indexTrust {
                    AudioLogger.log("voice sync: uSampleIndex verified as cumulative position")
                }
            } else if accumulatedNativeFrames > 0, sampleIndex == 0, matches == 0 {
                // Index stays 0 while real audio accumulates → not maintained.
                if accumulatedNativeFrames > UInt64(sampleRate) {
                    indexTrust = .untrusted
                    AudioLogger.log("voice sync: uSampleIndex unmaintained, using accumulator")
                }
            } else if indexMatches == false, sampleIndex != 0 {
                indexTrust = .untrusted
                AudioLogger.log("voice sync: uSampleIndex diverges from accumulator, using accumulator")
            }
        }
        lastIndex = sampleIndex

        // Native-rate position → the stream's 48 kHz media timeline.
        let position48k = UInt64(Double(positionNative)
            * Double(AudioDeviceStreamSource.outputSampleRate) / Double(sampleRate))

        // Drift diagnostics: position must advance at ~1 s of media per wall
        // second — a lower rate means the position source (accumulator) is
        // undercounting (dropped blocks) and every measurement inflates by
        // the deficit, which a tracker would wrongly chase.
        let diagNow = DispatchTime.now()
        if Double(diagNow.uptimeNanoseconds - diagLastAt.uptimeNanoseconds) / 1_000_000_000 >= Self.diagIntervalSeconds {
            diagLastAt = diagNow
            let wallElapsed = Double(diagNow.uptimeNanoseconds - sessionStart.uptimeNanoseconds) / 1_000_000_000
            let mediaElapsed = Double(position48k) / Double(AudioDeviceStreamSource.outputSampleRate)
            let rollingMedian = rollingSamples.isEmpty ? 0 : Self.median(of: rollingSamples.map(\.latency))
            AudioLogger.log(
                "voice sync diag: pos=%.1fs wall=%.1fs rate=%.4f median=%.0fms snapped=%.0fms samples=%d",
                mediaElapsed, wallElapsed,
                wallElapsed > 0 ? mediaElapsed / wallElapsed : 0,
                rollingMedian * 1000, (snapped ?? -1) * 1000, rollingSamples.count
            )
        }

        guard let latency = clock.latencySeconds(forMediaFrame48k: position48k),
              latency > 0, latency < Self.sanityMaxSeconds else { return }

        let now = DispatchTime.now()
        rollingSamples.append((at: now, latency: latency))
        let cutoff = now.uptimeNanoseconds - UInt64(Self.resnapWindowSeconds * 1_000_000_000)
        rollingSamples.removeAll { $0.at.uptimeNanoseconds < cutoff }

        if snapped == nil || loggedSnap == false {
            snapSamples.append(latency)
            let elapsed = Double(now.uptimeNanoseconds - sessionStart.uptimeNanoseconds) / 1_000_000_000
            if elapsed >= Self.snapWindowSeconds, snapSamples.count >= Self.snapMinimumSamples {
                let median = Self.median(of: snapSamples)
                snapped = median
                loggedSnap = true
                let spread = (snapSamples.max() ?? 0) - (snapSamples.min() ?? 0)
                AudioLogger.log("voice sync: snapped delay %.0f ms (samples=%d spread=%.0f ms)",
                                median * 1000, snapSamples.count, spread * 1000)
            }
        } else if let current = snapped,
                  rollingSamples.count >= Self.resnapMinimumSamples,
                  let oldest = rollingSamples.first,
                  Double(now.uptimeNanoseconds - oldest.at.uptimeNanoseconds) / 1_000_000_000 >= Self.resnapWindowSeconds - 0.5 {
            let rollingMedian = Self.median(of: rollingSamples.map(\.latency))
            if abs(rollingMedian - current) > Self.resnapThresholdSeconds {
                pendingResnap = rollingMedian
            } else {
                pendingResnap = nil
            }
        }
    }

    private func resetMeasurementLocked() {
        sessionStart = .now()
        pendingResnap = nil
        snapSamples.removeAll()
        rollingSamples.removeAll()
        indexTrust = .undecided(matches: 0)
        accumulatedNativeFrames = 0
        accumulatorSeeded = false
        lastIndex = 0
        loggedSnap = false
        // `snapped` deliberately kept: provisional until the re-measure lands.
    }

    private static func median(of values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

/// Deadline FIFO that delays outgoing voice chunks by the measured media
/// latency. Confined to the controller's serial queue: `enqueue`, `clear` and
/// the drain timer all run there, so no locking.
final class VoiceSyncDelayLine {

    private struct PendingChunk {
        let chunk: AdvancedMicrophoneAudioChunk
        let deadline: DispatchTime
    }

    /// Chunks whose deadline passed this long ago are dropped, not inserted —
    /// they're post-sleep/suspension garbage, not a recoverable backlog.
    private static let staleSeconds = 2.0
    private static let tickMSec = 10

    private let queue: DispatchQueue
    /// Performs the actual SDK insert; returns false when the SDK queue is
    /// full — the chunk stays at the head and is retried next tick, preserving
    /// order.
    var insertHandler: ((AdvancedMicrophoneAudioChunk) -> Bool)?

    private var pending: [PendingChunk] = []
    private var timer: DispatchSourceTimer?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var isEmpty: Bool { pending.isEmpty }

    /// Enqueue a transmitting chunk. The deadline never precedes the last
    /// queued one, so a shrinking delay (re-snap, stream stopped) can never
    /// reorder audio. Shrinking works by SKIPPING SILENCE: while the queued
    /// backlog exceeds the current target delay, silent chunks are dropped
    /// instead of enqueued — real time then catches up with the frozen
    /// deadline and the effective delay converges to the target. Without
    /// this, a continuously-open mic (always-on mode has no transmission
    /// pauses) would pin the delay at the largest value ever applied.
    func enqueue(_ chunk: AdvancedMicrophoneAudioChunk, delaySeconds: Double, isSilent: Bool) {
        let target = DispatchTime.now() + delaySeconds
        // 60 ms hysteresis so steady-state scheduling jitter doesn't nibble
        // at silence — only a genuine over-target backlog shrinks.
        if isSilent, let last = pending.last, last.deadline > target + 0.06 {
            return
        }
        let deadline = pending.last.map { max($0.deadline, target) } ?? target
        pending.append(PendingChunk(chunk: chunk, deadline: deadline))
        ensureTimer()
    }

    func clear() {
        pending.removeAll()
        cancelTimer()
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(Self.tickMSec),
                       repeating: .milliseconds(Self.tickMSec),
                       leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.drainDue() }
        self.timer = timer
        timer.resume()
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func drainDue() {
        let now = DispatchTime.now()
        while let first = pending.first, first.deadline <= now {
            let ageSeconds = Double(now.uptimeNanoseconds - first.deadline.uptimeNanoseconds) / 1_000_000_000
            if ageSeconds > Self.staleSeconds {
                pending.removeFirst()
                continue
            }
            guard insertHandler?(first.chunk) == true else {
                // SDK queue full: retry this chunk next tick, keep order.
                break
            }
            pending.removeFirst()
        }
        if pending.isEmpty {
            cancelTimer()
        }
    }
}
