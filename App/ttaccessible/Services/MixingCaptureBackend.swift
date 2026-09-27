//
//  MixingCaptureBackend.swift
//  ttaccessible
//
//  Several capture sources streamed as one — any mix of input devices, plus the chosen
//  applications or all audio from this Mac. Each part keeps its own capture backend,
//  filling a ring of its own; a 10 ms beat on the wall clock mixes them into the stream's
//  ring, which the loopback server paces and serves exactly as it does a single source.
//
//  Every device runs on its own clock, and none of them is the wall clock the server
//  paces by, so over minutes each source would drift ahead or behind. StreamMixer keeps a
//  small cushion per source and nudges that source's playback rate — by a few hundred
//  parts per million at most, far below anything audible — to hold the cushion steady.
//  Nothing is dropped or padded to follow the drift, so there is nothing to click. Only a
//  genuine stall (an unplugged device, a silent app backend) falls back to silence, and a
//  source that comes back is picked up again.
//

import Foundation

/// What the mixer reads: a ring a capture backend writes into.
protocol StreamMixerInput: AnyObject {
    var liveEdge: UInt64 { get }
    func read(from cursor: UInt64, maxFrames: Int) -> ([Int16], Int, UInt64)
}

extension AudioDeviceStreamSource.PCMRing: StreamMixerInput {}

/// Mixes several sources into one, holding each a small cushion ahead of the mix and
/// following each one's clock by nudging its rate. One caller, one mix at a time.
final class StreamMixer {

    struct SourceStats {
        /// Frames buffered ahead of the mix, smoothed.
        let fill: Double
        /// Playback rate relative to nominal: above 1 when the source's clock runs fast.
        let ratio: Double
        /// Times the source ran dry while playing — a stall, not drift.
        let underruns: Int
        /// Times a burst was cut back to the cushion.
        let skips: Int
        let primed: Bool
    }

    static let channels = AudioDeviceStreamSource.outputChannels
    static let sampleRate = Double(AudioDeviceStreamSource.outputSampleRate)

    /// Audio held per source between its capture and the mix: enough to ride out a backend
    /// that delivers in bursts (ScreenCaptureKit hands over tens of milliseconds at a time).
    /// The voice-sync measurement adds it back (MixingCaptureBackend.addedLatencySeconds).
    static let cushionFrames = 2_880
    static var cushionSeconds: Double { Double(cushionFrames) / sampleRate }
    /// A source this far ahead has come back from a stall in one go; it is cut back to the
    /// cushion rather than left running behind the others.
    static let overrunFrames = cushionFrames * 5
    /// The largest rate correction: 0.5 %. Real clock skew is a few dozen parts per million;
    /// the headroom only matters while a cushion settles.
    static let maxRateDeviation = 0.005
    /// How hard the rate leans on the cushion error: a one-beat (10 ms) error moves it by
    /// about 0.1 %, which works the error off in some ten seconds, inaudibly.
    static let rateGain = 0.006
    /// Smoothing of the measured cushion per mix, so the rate follows the trend of a bursty
    /// source rather than every burst.
    static let fillSmoothing = 0.02
    /// Most frames pulled from a source's ring in one go.
    private static let maxPullFrames = AudioDeviceStreamSource.outputSampleRate * 2

    private final class Source {
        let input: StreamMixerInput
        var cursor: UInt64 = 0
        /// Samples pulled but not yet played, interleaved, as Float. `position` is the play
        /// position in frames; the frame before it is kept for interpolation.
        var pending: [Float] = []
        var position: Double = 1
        var primed = false
        var smoothedFill: Double = 0
        var ratio: Double = 1
        var underruns = 0
        var skips = 0

        init(input: StreamMixerInput) { self.input = input }

        var pendingFrames: Int { pending.count / StreamMixer.channels }
        /// Frames waiting past the play position.
        var ahead: Double { Double(pendingFrames) - position }
    }

    private let sources: [Source]
    private var mixBuffer: [Float] = []

    /// Keeps the sum under full scale; nil mixes at unity and clips (the tests' bit-exact
    /// path). MixingCaptureBackend always gives it one.
    let limiter: PeakLimiter?

    init(inputs: [StreamMixerInput], limiter: PeakLimiter? = nil) {
        sources = inputs.map(Source.init)
        self.limiter = limiter
    }

    func stats(ofSource index: Int) -> SourceStats {
        let source = sources[index]
        return SourceStats(fill: source.smoothedFill, ratio: source.ratio,
                           underruns: source.underruns, skips: source.skips, primed: source.primed)
    }

    /// Mixes the next `frames` frames of every source into `output`, interleaved stereo Int16,
    /// sized to fit. A source that isn't ready contributes silence.
    func mix(frames: Int, into output: inout [Int16]) {
        let count = frames * Self.channels
        if mixBuffer.count != count {
            mixBuffer = [Float](repeating: 0, count: count)
        } else {
            mixBuffer.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        }
        for source in sources {
            add(source, frames: frames)
        }
        limiter?.process(&mixBuffer, frames: frames)
        if output.count != count {
            output = [Int16](repeating: 0, count: count)
        }
        for index in 0 ..< count {
            // Sources add up. The limiter keeps the sum under full scale; without one, a sum
            // past it clips rather than wrapping round.
            output[index] = Int16(max(-32_768, min(32_767, mixBuffer[index].rounded())))
        }
    }

    private func add(_ source: Source, frames: Int) {
        pull(source)

        if source.primed == false {
            // Silent until a full cushion has built up, then play from it.
            guard source.ahead >= Double(Self.cushionFrames) else { return }
            trim(source, toAhead: Self.cushionFrames)
            source.primed = true
            source.smoothedFill = Double(Self.cushionFrames)
            source.ratio = 1
        } else if source.ahead > Double(Self.overrunFrames) {
            trim(source, toAhead: Self.cushionFrames)
            source.smoothedFill = Double(Self.cushionFrames)
            source.skips += 1
        }

        source.smoothedFill += (source.ahead - source.smoothedFill) * Self.fillSmoothing
        let error = (source.smoothedFill - Double(Self.cushionFrames)) / Double(Self.cushionFrames)
        source.ratio = 1 + max(-Self.maxRateDeviation, min(Self.maxRateDeviation, error * Self.rateGain))

        let channels = Self.channels
        let available = source.pendingFrames
        source.pending.withUnsafeBufferPointer { pending in
            mixBuffer.withUnsafeMutableBufferPointer { mix in
                for frame in 0 ..< frames {
                    let base = Int(source.position)
                    guard base + 2 < available else {
                        // Ran dry: a stall, not drift. The rest of this mix stays silent, and
                        // the source plays again once a cushion is back.
                        source.primed = false
                        source.underruns += 1
                        return
                    }
                    let t = Float(source.position - Double(base))
                    for channel in 0 ..< channels {
                        mix[frame * channels + channel] += Self.interpolate(
                            pending[(base - 1) * channels + channel],
                            pending[base * channels + channel],
                            pending[(base + 1) * channels + channel],
                            pending[(base + 2) * channels + channel],
                            t
                        )
                    }
                    source.position += source.ratio
                }
            }
        }
        compact(source)
    }

    private func pull(_ source: Source) {
        let (samples, frames, next) = source.input.read(from: source.cursor, maxFrames: Self.maxPullFrames)
        source.cursor = next
        guard frames > 0 else { return }
        source.pending.reserveCapacity(source.pending.count + samples.count)
        for sample in samples {
            source.pending.append(Float(sample))
        }
    }

    /// Drops audio so that exactly `frames` frames wait past the play position.
    private func trim(_ source: Source, toAhead frames: Int) {
        let excess = source.ahead - Double(frames)
        guard excess > 0 else { return }
        source.position += excess
        compact(source)
    }

    /// Forgets what has been played, keeping the one frame before the play position.
    private func compact(_ source: Source) {
        let consumed = Int(source.position) - 1
        guard consumed > 0 else { return }
        source.pending.removeFirst(min(consumed, source.pendingFrames) * Self.channels)
        source.position -= Double(consumed)
    }

    /// Four-point cubic (Catmull-Rom) at fraction `t` between y1 and y2. At t = 0 it is y1
    /// exactly, so a source running at exactly the mix's rate passes through untouched.
    @inline(__always)
    static func interpolate(_ y0: Float, _ y1: Float, _ y2: Float, _ y3: Float, _ t: Float) -> Float {
        let c1 = 0.5 * (y2 - y0)
        let c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
        let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
        return ((c3 * t + c2) * t + c1) * t + y1
    }
}

/// Streams several capture backends as one. Each part fills its own ring; a 10 ms beat on
/// the wall clock — the clock the loopback server paces by — mixes them into the stream's
/// ring through StreamMixer.
final class MixingCaptureBackend: DeviceStreamCaptureBackend {

    struct Part {
        let backend: DeviceStreamCaptureBackend
        let ring: AudioDeviceStreamSource.PCMRing
        let name: String
    }

    /// Delay the mix adds between capture and the stream's ring: the cushion, half a beat on
    /// average, and the limiter's look-ahead. The voice-sync measurement only sees the
    /// stream's ring, so it is told (MediaSyncClock.setAddedLatency).
    static var addedLatencySeconds: Double {
        StreamMixer.cushionSeconds + Double(beatMilliseconds) / 2_000
            + PeakLimiter.lookaheadSeconds(sampleRate: StreamMixer.sampleRate)
    }

    private static let beatMilliseconds = 10
    private static let framesPerBeat = AudioDeviceStreamSource.outputSampleRate * beatMilliseconds / 1_000
    /// A beat this late (the Mac slept, the queue stalled) restarts the clock instead of
    /// mixing the whole gap at once; the server pads the gap with silence as it always has.
    private static let maxCatchUpFrames = AudioDeviceStreamSource.outputSampleRate / 10
    /// About five seconds between diagnostic lines.
    private static let diagnosticBeats = 500

    private let parts: [Part]
    private let output: AudioDeviceStreamSource.PCMRing
    private let mixer: StreamMixer
    private let queue = DispatchQueue(label: "com.ttaccessible.device-stream-mixer", qos: .userInteractive)
    // Beat state, touched only on `queue`.
    private var timer: DispatchSourceTimer?
    private var epoch = DispatchTime.now()
    private var framesProduced: UInt64 = 0
    private var beatsSinceDiagnostic = 0
    private var scratch: [Int16] = []

    init(parts: [Part], output: AudioDeviceStreamSource.PCMRing) {
        self.parts = parts
        self.output = output
        self.mixer = StreamMixer(inputs: parts.map(\.ring),
                                 limiter: PeakLimiter(channels: StreamMixer.channels,
                                                      sampleRate: StreamMixer.sampleRate))
    }

    deinit {
        timer?.cancel()
    }

    func start() throws {
        var started: [DeviceStreamCaptureBackend] = []
        do {
            for part in parts {
                try part.backend.start()
                started.append(part.backend)
            }
        } catch {
            // One part failing fails the stream: a clear error beats a mix quietly missing
            // something the user checked.
            started.forEach { $0.stop() }
            throw error
        }
        queue.sync {
            epoch = .now()
            framesProduced = 0
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(Self.beatMilliseconds),
                           repeating: .milliseconds(Self.beatMilliseconds),
                           leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.beat() }
            self.timer = timer
            timer.resume()
        }
        AudioLogger.log("device stream: mixing %ld sources — %@",
                        parts.count, parts.map(\.name).joined(separator: ", "))
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
        parts.forEach { $0.backend.stop() }
    }

    /// Every part writes silence, so the mix does too while the beat keeps the stream's
    /// ring advancing in real time.
    func setMuted(_ muted: Bool) {
        parts.forEach { $0.backend.setMuted(muted) }
    }

    private func beat() {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds &- epoch.uptimeNanoseconds
        let due = UInt64(Double(elapsedNanoseconds) / 1_000_000_000 * StreamMixer.sampleRate)
        guard due > framesProduced else { return }
        var owed = Int(due - framesProduced)
        if owed > Self.maxCatchUpFrames {
            epoch = .now()
            framesProduced = 0
            owed = Self.framesPerBeat
        }
        mixer.mix(frames: owed, into: &scratch)
        scratch.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            output.write(base, frames: owed)
        }
        framesProduced += UInt64(owed)
        logDiagnosticIfDue()
    }

    /// Per part: the cushion, the rate correction in parts per million, and how often it ran
    /// dry or was cut back — what shows whether drift is being followed.
    private func logDiagnosticIfDue() {
        beatsSinceDiagnostic += 1
        guard beatsSinceDiagnostic >= Self.diagnosticBeats else { return }
        beatsSinceDiagnostic = 0
        let lines = parts.indices.map { index -> String in
            let stats = mixer.stats(ofSource: index)
            return String(format: "%@ cushion=%.0fms rate=%+.0fppm dry=%ld cut=%ld",
                          parts[index].name,
                          stats.fill / StreamMixer.sampleRate * 1_000,
                          (stats.ratio - 1) * 1_000_000,
                          stats.underruns,
                          stats.skips)
        }
        var limiterLine = ""
        if let limiter = mixer.limiter {
            let (framesReduced, deepestGain) = limiter.takeDiagnostics()
            limiterLine = String(format: " | limiter reduced=%.0fms deepest=%.1fdB",
                                 Double(framesReduced) / StreamMixer.sampleRate * 1_000,
                                 20 * log10(Double(deepestGain)))
        }
        AudioLogger.log("stream mix diag: %@%@", lines.joined(separator: " | "), limiterLine)
    }
}
