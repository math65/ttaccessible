//
//  AudioDeviceStreamSource.swift
//  ttaccessible
//

import AVFoundation
import Foundation
import AudioToolbox
import CoreAudio
import Network

enum AudioDeviceStreamSourceError: Error {
    case deviceUnavailable
    case captureStartFailed
    case serverStartFailed
    case sourceUnsupportedOnThisOS
}

/// What a live-capture media stream captures.
enum DeviceStreamCaptureSpec: Equatable {
    /// A CoreAudio input device (the original "Stream Audio Device" source).
    case inputDevice(InputAudioDeviceInfo)
    /// The audio output of a set of processes (an application's audio, or
    /// VoiceOver's). Captured via CoreAudio process taps on macOS 14.2+ and
    /// ScreenCaptureKit audio on macOS 13.0–14.1; unavailable on macOS 12.
    case processes(ProcessSelection)

    struct ProcessSelection: Equatable {
        /// Bundle-identifier prefixes to capture — prefix matching so an app's
        /// helper processes (e.g. browser audio helpers) are included. Several
        /// applications can be captured at once: both backends mix N sources
        /// themselves (CATapDescription takes a list of processes, SCContentFilter
        /// a list of applications), so cumulating prefixes is all it takes.
        /// Empty when `capturesEntireSystem`.
        let bundleIDPrefixes: [String]
        let displayName: String
        /// Stable token stored in preferences ("voiceover", "app:<bundleID>",
        /// "system", or "multi:<token>+<token>" for a cumulated selection).
        let persistenceToken: String
        /// Capture everything this Mac plays, minus our own output — otherwise
        /// the channel we broadcast to would loop straight back into the stream.
        var capturesEntireSystem = false
    }

    var displayName: String {
        switch self {
        case .inputDevice(let device): return device.name
        case .processes(let selection): return selection.displayName
        }
    }

    /// Token persisted as the last-used source ("device:<uid>" for devices).
    var persistenceToken: String {
        switch self {
        case .inputDevice(let device): return "device:\(device.uid)"
        case .processes(let selection): return selection.persistenceToken
        }
    }

    static let voiceOverPersistenceToken = "voiceover"

    /// Bundle prefixes that carry VoiceOver's audio output. VoiceOver itself
    /// plus the speech-synthesis hosts — the process actually rendering VO
    /// speech varies by macOS version, so the net is deliberately wide and the
    /// capture logs which processes matched (see ProcessTapCaptureBackend).
    static let voiceOverBundlePrefixes = [
        "com.apple.VoiceOver",
        "com.apple.speech",
        "com.apple.SpeechSynthesis",
        "com.apple.accessibility.speech",
    ]

    static func voiceOver() -> DeviceStreamCaptureSpec {
        .processes(ProcessSelection(
            bundleIDPrefixes: voiceOverBundlePrefixes,
            displayName: L10n.text("mediaStream.device.source.voiceOver"),
            persistenceToken: voiceOverPersistenceToken
        ))
    }

    static func application(bundleID: String, displayName: String) -> DeviceStreamCaptureSpec {
        .processes(ProcessSelection(
            bundleIDPrefixes: [bundleID],
            displayName: displayName,
            persistenceToken: "app:\(bundleID)"
        ))
    }

    static let systemAudioPersistenceToken = "system"

    /// Everything the Mac plays, minus tt-Accessible itself.
    static func systemAudio() -> DeviceStreamCaptureSpec {
        .processes(ProcessSelection(
            bundleIDPrefixes: [],
            displayName: L10n.text("mediaStream.device.source.systemAudio"),
            persistenceToken: systemAudioPersistenceToken,
            capturesEntireSystem: true
        ))
    }

    static let multiPersistenceTokenPrefix = "multi:"
    private static let multiPersistenceTokenSeparator = "+"

    /// Fuse several application sources (VoiceOver included) into the single
    /// selection the capture backends consume. Returns the sole spec unchanged
    /// when there is only one, and nil when there is nothing to stream.
    ///
    /// Only process sources cumulate: an input device is captured by a wholly
    /// different backend, and the system-wide tap already contains everything.
    static func merging(_ specs: [DeviceStreamCaptureSpec]) -> DeviceStreamCaptureSpec? {
        let selections: [ProcessSelection] = specs.compactMap { spec in
            guard case .processes(let selection) = spec, !selection.capturesEntireSystem else { return nil }
            return selection
        }
        guard selections.isEmpty == false else { return nil }
        guard selections.count > 1 else { return .processes(selections[0]) }

        var prefixes: [String] = []
        for selection in selections where selection.bundleIDPrefixes.isEmpty == false {
            prefixes.append(contentsOf: selection.bundleIDPrefixes.filter { !prefixes.contains($0) })
        }
        let token = multiPersistenceTokenPrefix
            + selections.map(\.persistenceToken).joined(separator: multiPersistenceTokenSeparator)
        return .processes(ProcessSelection(
            bundleIDPrefixes: prefixes,
            displayName: joinedDisplayName(selections.map(\.displayName)),
            persistenceToken: token
        ))
    }

    /// The individual tokens a "multi:" token was built from, in order. Any
    /// other token yields itself, so callers can restore a selection blind.
    static func componentTokens(of token: String) -> [String] {
        guard token.hasPrefix(multiPersistenceTokenPrefix) else { return [token] }
        return token
            .dropFirst(multiPersistenceTokenPrefix.count)
            .components(separatedBy: multiPersistenceTokenSeparator)
            .filter { $0.isEmpty == false }
    }

    /// "Music, Safari and VoiceOver" — but a long selection is summarised
    /// rather than read out in full: this name is spoken on every progress
    /// update of the player.
    private static func joinedDisplayName(_ names: [String]) -> String {
        let maximumNamed = 3
        guard names.count > maximumNamed else {
            return ListFormatter.localizedString(byJoining: names)
        }
        let head = ListFormatter.localizedString(byJoining: Array(names.prefix(maximumNamed)))
        return L10n.format("mediaStream.device.source.andOthers", head, names.count - maximumNamed)
    }
}

/// A capture implementation that feeds 48 kHz stereo Int16 frames into the
/// stream source's ring. Implementations must be safe to start off the main
/// thread and must honor `setMuted` by writing silence (never by stopping —
/// the ring must keep advancing in real time so the stream never starves).
protocol DeviceStreamCaptureBackend: AnyObject {
    func start() throws
    func stop()
    func setMuted(_ muted: Bool)
}

/// Captures a CoreAudio input device and serves it as an endless Ogg Opus
/// stream on a loopback HTTP server, so the SDK's media streamer can broadcast
/// it to the channel exactly like a URL stream.
///
/// Opus (5 ms frames) because of the SDK's FFmpeg stream analysis: when the SDK
/// opens the loopback URL, FFmpeg reads a fixed BATCH OF PACKETS before playback
/// starts, holding the SDK's audio lock the whole time (freezing the channel's
/// voice) AND replaying everything it consumed as permanent standing latency.
/// Both scale with packet size, so smaller packets = less freeze + less latency:
/// PCM/WAV packets ~85 ms (≈4.3 s), AAC ~21 ms (≈2 s), Opus at 5 ms → measured
/// ~0.4 s. libopus comes from the exported symbols in libTeamTalk5.dylib (see
/// OpusShim), so no extra dependency; the channel's own Opus codec re-encodes.
///
/// The server paces its output against the wall clock and substitutes silence
/// whenever the device stops delivering (silent source, unplugged, stalled), so the
/// SDK never sees the stream starve — a starved stream would otherwise be treated
/// as finished and the broadcast would stop.
final class AudioDeviceStreamSource {

    nonisolated static let outputSampleRate = 48_000
    nonisolated static let outputChannels = 2

    private let spec: DeviceStreamCaptureSpec
    private let muteSourceOutput: Bool
    /// Passed to the process-tap backend so its transient aggregate device
    /// doesn't trigger a sound-system restart. See `ProcessTapCaptureBackend`.
    private let suppressDeviceChanges: ((TimeInterval) -> Void)?
    private let ring = PCMRing(capacityFrames: outputSampleRate * 2, channels: outputChannels)
    private let serverQueue = DispatchQueue(label: "com.ttaccessible.device-stream-server")
    private var backend: DeviceStreamCaptureBackend?

    /// Media-position → capture-time mapping for the voice-sync feature: the
    /// active connection publishes where its media timeline sits in the ring,
    /// so the controller can measure how far behind live the broadcast runs.
    let syncClock: MediaSyncClock

    // Server state (guarded by serverQueue).
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: StreamConnection] = [:]
    private var stopped = false
    /// Monotonic per-connection generation, for publisher election (guarded by
    /// serverQueue). The SDK/FFmpeg can open the URL more than once (probe +
    /// playback, channel-switch restart overlap); only the newest LIVE
    /// connection publishes to the sync clock.
    private var nextConnectionGeneration: UInt64 = 0

    private let stopLock = NSLock()
    private var didStop = false

    /// `muteSourceOutput`: process-tap sources only — silence the captured
    /// app/VoiceOver on this Mac while it streams (CATapDescription's
    /// muted-while-tapped behavior). Ignored for devices and the SCK backend.
    init(
        spec: DeviceStreamCaptureSpec,
        muteSourceOutput: Bool = false,
        suppressDeviceChanges: ((TimeInterval) -> Void)? = nil
    ) {
        self.spec = spec
        self.muteSourceOutput = muteSourceOutput
        self.suppressDeviceChanges = suppressDeviceChanges
        self.syncClock = MediaSyncClock(ring: ring)
    }

    convenience init(device: InputAudioDeviceInfo) {
        self.init(spec: .inputDevice(device))
    }

    var displayName: String { spec.displayName }

    deinit {
        stop()
    }

    /// Start capture and the loopback server. Returns the URL the SDK should stream.
    func start() throws -> URL {
        let backend = try makeBackend()
        let port = try startServer()
        do {
            try backend.start()
        } catch {
            self.backend = backend  // so stop() tears it down
            stop()
            throw error
        }
        self.backend = backend
        guard let url = URL(string: "http://127.0.0.1:\(port)/device-stream.ogg") else {
            stop()
            throw AudioDeviceStreamSourceError.serverStartFailed
        }
        AudioLogger.log("device stream: source started source=%@ url=%@", spec.displayName, url.absoluteString)
        return url
    }

    private func makeBackend() throws -> DeviceStreamCaptureBackend {
        switch spec {
        case .inputDevice(let device):
            return DeviceInputCaptureBackend(device: device, ring: ring)
        case .processes(let selection):
            if #available(macOS 14.2, *) {
                return ProcessTapCaptureBackend(
                    selection: selection,
                    ring: ring,
                    muteLocalOutput: muteSourceOutput,
                    suppressDeviceChanges: suppressDeviceChanges
                )
            }
            if #available(macOS 13.0, *) {
                return SCKAudioCaptureBackend(selection: selection, ring: ring)
            }
            throw AudioDeviceStreamSourceError.sourceUnsupportedOnThisOS
        }
    }

    /// Pause/resume the stream by muting the capture — the backend keeps
    /// feeding real-time silence so the SDK never sees a discontinuity.
    func setMuted(_ muted: Bool) {
        backend?.setMuted(muted)
        AudioLogger.log("device stream: %@", muted ? "paused (muted)" : "resumed")
    }

    func stop() {
        guard claimStop() else { return }

        // Capture first, so no more ring writes; then the server.
        backend?.stop()
        backend = nil
        shutdownServer()
        AudioLogger.log("device stream: source stopped source=%@", spec.displayName)
    }

    /// Stop without blocking the caller on backend teardown.
    ///
    /// The controller tears streams down from its serial queue
    /// (`finalizeMediaStreamingLocked`, `destroyLocked`), and backend teardown
    /// is slow: `SCKAudioCaptureBackend` waits on a semaphore for up to 2 s,
    /// and `ProcessTapCaptureBackend.stop()` takes `controlQueue`, which may be
    /// mid-rebuild (a 0.1 s settle plus aggregate-device create/destroy). Held
    /// on the SDK's serial queue that stalls the message loop — and
    /// `disconnectSynchronously()` puts the main thread behind that same queue,
    /// so the UI freezes with it.
    ///
    /// Teardown order is inverted relative to `stop()`: the server closes
    /// first, so whatever the backend still writes to the ring while it winds
    /// down simply has no reader.
    func stopAsynchronously() {
        guard claimStop() else { return }

        let backend = self.backend
        self.backend = nil
        shutdownServer()
        DispatchQueue.global(qos: .userInitiated).async { [spec] in
            backend?.stop()
            AudioLogger.log("device stream: source stopped source=%@", spec.displayName)
        }
    }

    /// Returns true for the one caller that wins the stop race.
    private func claimStop() -> Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        guard didStop == false else { return false }
        didStop = true
        return true
    }

    private func shutdownServer() {
        serverQueue.sync {
            stopped = true
            // Snapshot + clear before cancelling: cancel() → finish() → onFinish
            // removes from `connections` synchronously, which would mutate the
            // dictionary mid-iteration.
            let active = Array(connections.values)
            connections.removeAll()
            for connection in active {
                connection.cancel()
            }
            listener?.cancel()
            listener = nil
        }
    }

    // MARK: - Loopback HTTP server

    private func startServer() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            AudioLogger.log("device stream: listener create failed — %@", error.localizedDescription)
            throw AudioDeviceStreamSourceError.serverStartFailed
        }

        let readySemaphore = DispatchSemaphore(value: 0)
        var readyPort: UInt16?
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                readyPort = listener.port?.rawValue
                readySemaphore.signal()
            case .failed(let error):
                AudioLogger.log("device stream: listener failed — %@", error.localizedDescription)
                readySemaphore.signal()
                self?.serverQueue.async { self?.listener = nil }
            case .cancelled:
                readySemaphore.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.acceptConnection(connection)
        }

        // `stopped` already defaults to false (fresh instance per stream); don't
        // re-write it off serverQueue. `listener` is published here before start()
        // returns and is only mutated on serverQueue thereafter.
        self.listener = listener
        listener.start(queue: serverQueue)

        _ = readySemaphore.wait(timeout: .now() + 5)
        guard let port = readyPort else {
            listener.cancel()
            self.listener = nil
            throw AudioDeviceStreamSourceError.serverStartFailed
        }
        return port
    }

    private func acceptConnection(_ connection: NWConnection) {
        // Runs on serverQueue (the listener's queue).
        guard stopped == false else {
            connection.cancel()
            return
        }
        nextConnectionGeneration += 1
        let stream = StreamConnection(
            connection: connection,
            ring: ring,
            queue: serverQueue,
            generation: nextConnectionGeneration,
            clock: syncClock
        ) { [weak self] finished in
            self?.connections.removeValue(forKey: ObjectIdentifier(finished))
            self?.electSyncPublisherLocked()
        }
        connections[ObjectIdentifier(stream)] = stream
        stream.start()
        electSyncPublisherLocked()
    }

    /// Elect the newest LIVE connection as the sync-clock publisher. Runs on
    /// serverQueue (same queue as every connection's ticks), recomputed on both
    /// accept and finish so a short-lived probe connection can't permanently
    /// steal publishing from the surviving playback connection.
    private func electSyncPublisherLocked() {
        let publisher = connections.values.max(by: { $0.generation < $1.generation })
        var changed = false
        for connection in connections.values {
            let shouldPublish = connection === publisher
            if connection.isSyncPublisher != shouldPublish {
                connection.isSyncPublisher = shouldPublish
                changed = true
            }
        }
        if changed || publisher == nil {
            // Old mapping belongs to the previous publisher's timeline; drop it
            // until the new publisher's first real send republishes.
            syncClock.invalidate()
        }
    }

    // MARK: - Per-connection realtime pump

    /// One accepted HTTP connection: consumes the request head, replies with an
    /// endless Ogg Opus body paced to realtime (in the PCM domain, before the
    /// encoder), padding with silence whenever capture falls behind so the
    /// stream never starves.
    private final class StreamConnection {
        private let connection: NWConnection
        private let ring: PCMRing
        private let queue: DispatchQueue
        private let onFinish: (StreamConnection) -> Void

        /// Monotonic accept order, for publisher election.
        let generation: UInt64
        /// Whether this connection publishes its media-position → capture-time
        /// mapping to the sync clock. Set by the source's election; read in
        /// tick() — both on `queue`, no synchronization needed.
        var isSyncPublisher = false
        private let clock: MediaSyncClock
        /// PCM frames actually emitted into the media timeline (real sends +
        /// silence pads) since this connection started. This — not the pacing
        /// ledger `framesSent`, which also advances on skips — is the position
        /// the SDK's decoder reports back in its audio blocks.
        private var mediaFramesEmitted: UInt64 = 0
        /// Media frame before which the (media → capture) mapping is broken for
        /// this connection: any pad (media advanced without capture), skip, or
        /// stall-reset (capture cursor jumped without media) moves it forward.
        private var syncWatermark: UInt64 = 0

        private var timer: DispatchSourceTimer?
        private var cursor: UInt64 = 0
        private var framesSent: UInt64 = 0
        private var epoch: DispatchTime = .now()
        /// ~5 s diagnostic cadence in ticks (drift investigations: a ramping
        /// backlog = capture clock vs wall clock skew; ramping pendingSend =
        /// the SDK consuming slower than wall; both shift the broadcast.
        private var ticksSinceDiag = 0
        private static let diagTickInterval = 250
        /// PCM frames' worth of encoded audio sitting in the socket, awaiting
        /// send completion. Media time, not bytes: AAC compresses silence to a
        /// few bytes per frame, so a byte cap would let a stalled reader build
        /// minutes of media-time backlog while quiet.
        private var pendingSendMediaFrames = 0
        private var finished = false
        private var encoder: OggOpusStreamEncoder?

        /// Operating buffer: the pump deliberately runs this far behind the
        /// capture live edge, so scheduling jitter on either side is absorbed
        /// by real buffered audio instead of audible silence patches.
        private static let bufferFrames = AudioDeviceStreamSource.outputSampleRate * 3 / 10
        /// Tolerated shortfall beyond the operating buffer before silence is
        /// padded in — only a genuine capture stall gets this far.
        private static let graceFrames = AudioDeviceStreamSource.outputSampleRate / 10
        /// Maximum backlog of captured-but-unsent audio before skipping ahead
        /// (must comfortably exceed bufferFrames, the steady-state backlog).
        private static let maxLagFrames = AudioDeviceStreamSource.outputSampleRate * 3 / 5
        /// Stop enqueueing while this much audio (media time, as PCM frames) is
        /// stuck in the socket (the SDK reader stalled); the pump then skips
        /// ahead instead of buffering.
        private static let maxPendingSendFrames = AudioDeviceStreamSource.outputSampleRate * 2

        private static let tickMSec = 20

        init(
            connection: NWConnection,
            ring: PCMRing,
            queue: DispatchQueue,
            generation: UInt64,
            clock: MediaSyncClock,
            onFinish: @escaping (StreamConnection) -> Void
        ) {
            self.connection = connection
            self.ring = ring
            self.queue = queue
            self.generation = generation
            self.clock = clock
            self.onFinish = onFinish
        }

        func start() {
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.finish()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            receiveRequestHead(accumulated: Data())
        }

        func cancel() {
            finish()
        }

        private func finish() {
            guard finished == false else { return }
            finished = true
            timer?.cancel()
            timer = nil
            connection.cancel()
            onFinish(self)
        }

        private func receiveRequestHead(accumulated: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
                guard let self, self.finished == false else { return }
                if error != nil || isComplete {
                    self.finish()
                    return
                }
                var head = accumulated
                if let data { head.append(data) }
                if head.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.beginStreaming()
                } else if head.count < 16_384 {
                    self.receiveRequestHead(accumulated: head)
                } else {
                    self.finish()
                }
            }
        }

        private func beginStreaming() {
            guard let encoder = OggOpusStreamEncoder(
                sampleRate: AudioDeviceStreamSource.outputSampleRate,
                channels: AudioDeviceStreamSource.outputChannels,
                bitrate: 128_000,
                serial: UInt32.random(in: 1...UInt32.max)
            ) else {
                AudioLogger.log("device stream: Opus encoder unavailable — closing connection")
                finish()
                return
            }
            self.encoder = encoder

            let headers = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: audio/ogg\r\n"
                + "Cache-Control: no-store\r\n"
                + "Connection: close\r\n"
                + "\r\n"
            send(Data(headers.utf8))
            // Ogg Opus stream headers (OpusHead + OpusTags) must precede audio.
            send(encoder.streamHeaders())

            cursor = ring.liveEdge
            // Crediting the operating buffer as already-sent delays the first
            // send until that much capture has accumulated behind the cursor.
            framesSent = UInt64(Self.bufferFrames)
            epoch = .now()

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(Self.tickMSec),
                           repeating: .milliseconds(Self.tickMSec),
                           leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            timer.resume()
        }

        private func tick() {
            guard finished == false else { return }

            ticksSinceDiag += 1
            if ticksSinceDiag >= Self.diagTickInterval {
                ticksSinceDiag = 0
                let live = ring.liveEdge
                let backlogMs = live > cursor
                    ? Int((live - cursor) * 1000 / UInt64(AudioDeviceStreamSource.outputSampleRate))
                    : 0
                let wallSec = Double(DispatchTime.now().uptimeNanoseconds - epoch.uptimeNanoseconds) / 1_000_000_000
                AudioLogger.log(
                    "stream diag: backlog=%dms pendingSend=%dms emitted=%.1fs wall=%.1fs publisher=%d",
                    backlogMs,
                    pendingSendMediaFrames * 1000 / AudioDeviceStreamSource.outputSampleRate,
                    Double(mediaFramesEmitted) / Double(AudioDeviceStreamSource.outputSampleRate),
                    wallSec,
                    isSyncPublisher ? 1 : 0
                )
            }

            let elapsedSec = Double(DispatchTime.now().uptimeNanoseconds - epoch.uptimeNanoseconds) / 1_000_000_000
            let targetFrames = UInt64(elapsedSec * Double(AudioDeviceStreamSource.outputSampleRate))
            guard targetFrames > framesSent else { return }
            var owed = Int(targetFrames - framesSent)
            // A long scheduler stall (sleep, suspension) would otherwise demand a
            // huge burst; skip the gap and resume live with the buffer restored.
            if owed > AudioDeviceStreamSource.outputSampleRate * 2 {
                framesSent = targetFrames + UInt64(Self.bufferFrames)
                cursor = ring.liveEdge
                syncWatermark = mediaFramesEmitted
                return
            }

            // If the reader has stalled (socket backlog), drop this tick's audio
            // and keep the timeline moving so we stay live once it drains.
            if pendingSendMediaFrames > Self.maxPendingSendFrames {
                framesSent = targetFrames + UInt64(Self.bufferFrames)
                cursor = ring.liveEdge
                syncWatermark = mediaFramesEmitted
                return
            }

            // Keep the broadcast near-live: if capture ran ahead of what we've
            // sent by more than maxLag, skip forward (drops backlog audio).
            let liveEdge = ring.liveEdge
            if liveEdge > cursor, Int(liveEdge - cursor) > Self.maxLagFrames + owed {
                cursor = liveEdge - UInt64(Self.maxLagFrames)
                syncWatermark = mediaFramesEmitted
            }

            let (samples, framesRead, newCursor) = ring.read(from: cursor, maxFrames: owed)
            if framesRead > 0 {
                cursor = newCursor
                framesSent += UInt64(framesRead)
                owed -= framesRead
                mediaFramesEmitted += UInt64(framesRead)
                sendEncoded(samples, mediaFrames: framesRead)
                // Real audio: media timeline and capture cursor advanced in
                // lockstep, so the mapping at this instant is exact — publish it.
                if isSyncPublisher {
                    clock.update(
                        mediaFrameBase: mediaFramesEmitted,
                        captureCursorBase: cursor,
                        watermark: syncWatermark
                    )
                }
            }

            // Capture isn't delivering (silent stall, unplug): pad silence so the
            // SDK's reader never starves. Padding the operating buffer on top
            // restores the jitter margin before real audio resumes, so recovery
            // doesn't crackle along with zero headroom.
            if owed > Self.graceFrames {
                let padFrames = owed + Self.bufferFrames
                let silence = [Int16](repeating: 0,
                                      count: padFrames * AudioDeviceStreamSource.outputChannels)
                framesSent += UInt64(padFrames)
                cursor = ring.liveEdge
                mediaFramesEmitted += UInt64(padFrames)
                // Padded frames occupy media time with no capture behind them.
                syncWatermark = mediaFramesEmitted
                sendEncoded(silence, mediaFrames: padFrames)
            }
        }

        private func sendEncoded(_ samples: [Int16], mediaFrames: Int) {
            guard let encoder else { return }
            let encoded = encoder.encode(samples)
            if encoded.isEmpty == false {
                send(encoded, mediaFrames: mediaFrames)
            }
        }

        private func send(_ data: Data, mediaFrames: Int = 0) {
            guard finished == false, data.isEmpty == false else { return }
            pendingSendMediaFrames += mediaFrames
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.pendingSendMediaFrames -= mediaFrames
                if error != nil {
                    self.finish()
                }
            })
        }

    }

    // MARK: - Ring buffer

    /// Fixed-capacity interleaved Int16 ring with absolute frame counters, so
    /// multiple connections read at independent cursors without consuming.
    ///
    /// Single-producer (the RT audio thread) / multi-consumer (connection sends).
    /// The producer is lock-free and allocation-free: it copies into a raw buffer,
    /// then publishes the absolute write cursor with a release store. Readers load
    /// it with acquire, copy, then re-validate that the producer hasn't lapped and
    /// overwritten the copied region — a seqlock, so no lock touches the RT thread.
    ///
    /// Internal (not private): the capture backends in their own files write
    /// into it, and MediaSyncClock reads its live edge.
    final class PCMRing {
        private let bufferPtr: UnsafeMutablePointer<Int16>
        private let sampleCount: Int
        private let capacityFrames: Int
        private let channels: Int
        /// Published write cursor (absolute frames). Producer release-stores here;
        /// readers acquire-load. Heap-boxed C atomic — see AtomicU64.
        private let writeCursor: OpaquePointer
        /// Producer-private running frame count; only `write()` touches it, and
        /// `write()` is only ever called from the single AUHAL callback thread.
        private var producerFrames: UInt64 = 0

        init(capacityFrames: Int, channels: Int) {
            self.capacityFrames = capacityFrames
            self.channels = channels
            self.sampleCount = capacityFrames * channels
            let ptr = UnsafeMutablePointer<Int16>.allocate(capacity: capacityFrames * channels)
            ptr.initialize(repeating: 0, count: capacityFrames * channels)
            self.bufferPtr = ptr
            self.writeCursor = ttac_atomic_u64_create(0)
        }

        deinit {
            bufferPtr.deinitialize(count: sampleCount)
            bufferPtr.deallocate()
            ttac_atomic_u64_destroy(writeCursor)
        }

        var liveEdge: UInt64 { ttac_atomic_u64_load(writeCursor) }

        /// Called only from the RT audio thread. Lock-free and allocation-free.
        func write(_ samples: UnsafePointer<Int16>, frames: Int) {
            guard frames > 0 else { return }
            // Writes larger than the ring keep only the newest capacity worth.
            let usableFrames = min(frames, capacityFrames)
            let skippedFrames = frames - usableFrames
            var writeIndex = Int((producerFrames + UInt64(skippedFrames)) % UInt64(capacityFrames))
            var sourceFrame = skippedFrames
            var remaining = usableFrames
            while remaining > 0 {
                let run = min(remaining, capacityFrames - writeIndex)
                (bufferPtr + writeIndex * channels)
                    .update(from: samples + sourceFrame * channels, count: run * channels)
                sourceFrame += run
                writeIndex = (writeIndex + run) % capacityFrames
                remaining -= run
            }
            producerFrames += UInt64(frames)
            // Release-publish so acquiring readers observe the buffer writes above.
            ttac_atomic_u64_store(writeCursor, producerFrames)
        }

        /// Copy up to `maxFrames` starting at absolute frame `cursor`. A cursor
        /// that has been overwritten is advanced to the oldest retained frame.
        /// Runs on a connection's serial queue (not the RT thread), so allocating
        /// the returned array is fine.
        func read(from cursor: UInt64, maxFrames: Int) -> ([Int16], Int, UInt64) {
            guard maxFrames > 0 else { return ([], 0, cursor) }

            var attempt = 0
            while true {
                let writeFrames = ttac_atomic_u64_load(writeCursor)
                guard writeFrames > cursor else { return ([], 0, cursor) }

                let oldestRetained = writeFrames > UInt64(capacityFrames)
                    ? writeFrames - UInt64(capacityFrames)
                    : 0
                let effectiveCursor = max(cursor, oldestRetained)
                let available = Int(writeFrames - effectiveCursor)
                let framesToRead = min(maxFrames, available)
                guard framesToRead > 0 else { return ([], 0, effectiveCursor) }

                var output = [Int16](repeating: 0, count: framesToRead * channels)
                var readIndex = Int(effectiveCursor % UInt64(capacityFrames))
                output.withUnsafeMutableBufferPointer { dest in
                    guard let destBase = dest.baseAddress else { return }
                    var destFrame = 0
                    var remaining = framesToRead
                    while remaining > 0 {
                        let run = min(remaining, capacityFrames - readIndex)
                        destBase
                            .advanced(by: destFrame * channels)
                            .update(from: bufferPtr + readIndex * channels, count: run * channels)
                        destFrame += run
                        readIndex = (readIndex + run) % capacityFrames
                        remaining -= run
                    }
                }

                // Seqlock validation: if the producer lapped far enough to overwrite
                // the start of the region we just copied, the copy is torn — retry
                // with the newer edge (bounded; the producer can't lap forever within
                // a tick, so this converges immediately in practice).
                let writeFramesAfter = ttac_atomic_u64_load(writeCursor)
                let oldestAfter = writeFramesAfter > UInt64(capacityFrames)
                    ? writeFramesAfter - UInt64(capacityFrames)
                    : 0
                if oldestAfter <= effectiveCursor || attempt >= 3 {
                    return (output, framesToRead, effectiveCursor + UInt64(framesToRead))
                }
                attempt += 1
            }
        }
    }
}


/// Thread-safe media-position → capture-time mapping for voice sync.
///
/// The stream's publisher connection updates the mapping after every real send
/// (media timeline and capture cursor advance in lockstep there, so the pair is
/// exact at that instant); the voice-sync estimator asks, for a media position
/// the SDK reports it is currently playing back locally, how far behind the
/// capture live edge that audio is. Positions older than the watermark crossed
/// a pad/skip discontinuity and cannot be mapped.
final class MediaSyncClock {
    private let lock = NSLock()
    private let ring: AudioDeviceStreamSource.PCMRing
    private var hasMapping = false
    private var mediaFrameBase: UInt64 = 0
    private var captureCursorBase: UInt64 = 0
    private var watermark: UInt64 = 0

    init(ring: AudioDeviceStreamSource.PCMRing) {
        self.ring = ring
    }

    /// Drop the mapping (publisher changed; next real send republishes).
    func invalidate() {
        lock.lock()
        hasMapping = false
        lock.unlock()
    }

    func update(mediaFrameBase: UInt64, captureCursorBase: UInt64, watermark: UInt64) {
        lock.lock()
        self.mediaFrameBase = mediaFrameBase
        self.captureCursorBase = captureCursorBase
        self.watermark = watermark
        hasMapping = true
        lock.unlock()
    }

    /// Seconds behind the capture live edge for media frame `mediaFrame48k`
    /// (a position on the stream's 48 kHz media timeline), or nil when the
    /// position can't be mapped (no mapping yet, position crossed a
    /// discontinuity, or position newer than the last publish).
    func latencySeconds(forMediaFrame48k mediaFrame48k: UInt64) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard hasMapping,
              mediaFrame48k >= watermark,
              mediaFrame48k <= mediaFrameBase else { return nil }
        let framesBehindBase = mediaFrameBase - mediaFrame48k
        guard captureCursorBase >= framesBehindBase else { return nil }
        let captureFrame = captureCursorBase - framesBehindBase
        let liveEdge = ring.liveEdge
        guard liveEdge >= captureFrame else { return nil }
        return Double(liveEdge - captureFrame) / Double(AudioDeviceStreamSource.outputSampleRate)
    }
}
