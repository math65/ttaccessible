//
//  OutputAudioRenderEngine.swift
//  ttaccessible
//
//  Custom CoreAudio OUTPUT engine — the symmetric counterpart of
//  AdvancedMicrophoneAudioEngine. The TeamTalk SDK is pointed at the virtual
//  output device (TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) so it never owns a
//  physical CoreAudio output device (whose close intermittently deadlocks).
//
//  Instead of playing the SDK's pre-mixed "muxed" stream (which includes the
//  local user's own transmitted voice and can't be split per-person), this
//  engine MIXES PER USER: each remote user's decoded PCM is fed via
//  `enqueueUser(...)`, and a mixer sums the users — with per-user volume / pan /
//  mute — into a stereo ring at the output device rate. The render callback
//  plays that ring to the selected device. The local user is simply never fed
//  in, so you never hear yourself; and because we own the mix, per-user controls
//  (pan/mix/mute) are possible. Switching the output device is a fast rebind of
//  our AudioUnit — no SDK close, no deadlock.
//
//  Threading:
//  - Producer / control / mix plane: this engine's OWN dedicated serial queue
//    (`engineQueue`, user-interactive). `enqueueUser`, `pumpMix`, `start`, `stop`,
//    `switchDevice`, and the per-user settings all run there (serially), so per-user
//    state is single-threaded and needs no locking. `pumpMix` is driven by a fine
//    timer ON this queue — NOT piggy-backed on the TeamTalk message loop — so the
//    occasional heavy channel-tree rebuild (publishSessionLocked) can never stall it.
//    That decoupling is what lets the output ring stay small (low latency) without
//    underrunning. The producer (`enqueueUser`) is fed a COPIED PCM buffer from the
//    message loop, then hops to engineQueue. Master gain/mute setters write atomic
//    cells directly (read by the render callback) and need no queue.
//  - Consumer: the CoreAudio render callback (real-time thread).
//  The only cross-thread state is the mixed-output SPSC ring (ordered with
//  acquire/release fences) and the master gain/mute/primed cells (benign
//  single-word; gain is smoothed in the render loop). The render callback never
//  allocates, locks, or calls into ObjC.
//

import AudioToolbox
import CoreAudio
import Foundation

/// Per-user mix controls (applied on the mix thread). Pan is constant-balance:
/// -1 = hard left, 0 = center, +1 = hard right.
struct OutputUserMixSettings: Equatable {
    var volume: Float = 1      // linear gain
    var pan: Float = 0         // -1 .. +1
    var muted: Bool = false
}

/// Buffering profile for a mix source, picked by how its PCM is delivered.
enum OutputSourceBufferProfile {
    /// Regularly-clocked real-time source (the local mic "hear myself" monitor):
    /// minimal buffering for low latency.
    case lowLatency
    /// Network-delivered remote user audio: the standard jitter target.
    case network
    /// Our OWN decoded media-file stream — burstier than network (the SDK feeds it
    /// from the file decoder, not a paced network jitter buffer), so it needs a
    /// deeper prime buffer and a much higher catch-up ceiling to stay smooth.
    case localMedia
}

/// Lock-free single-producer / single-consumer ring of interleaved Int16 at the
/// output device rate. Producer (mix thread) writes `tail`, consumer (RT) writes
/// `head`; monotonic 64-bit counters index a power-of-two buffer.
private final class OutputAudioSampleRing {
    private let buffer: UnsafeMutablePointer<Int16>
    let capacity: Int
    private let mask: Int
    private let headPtr: UnsafeMutablePointer<Int>
    private let tailPtr: UnsafeMutablePointer<Int>

    init(minimumCapacity: Int) {
        var cap = 1
        while cap < minimumCapacity { cap <<= 1 }
        capacity = cap
        mask = cap - 1
        buffer = UnsafeMutablePointer<Int16>.allocate(capacity: cap)
        buffer.initialize(repeating: 0, count: cap)
        headPtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        headPtr.initialize(to: 0)
        tailPtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        tailPtr.initialize(to: 0)
    }

    func free() {
        buffer.deallocate()
        headPtr.deallocate()
        tailPtr.deallocate()
    }

    func fillCount() -> Int {
        let t = tailPtr.pointee
        ttac_atomic_fence_acquire()
        let h = headPtr.pointee
        return t - h
    }

    @discardableResult
    func write(_ src: UnsafePointer<Int16>, count: Int) -> Int {
        let h = headPtr.pointee
        ttac_atomic_fence_acquire()
        let t = tailPtr.pointee
        let free = capacity - (t - h)
        let toWrite = min(count, free)
        if toWrite <= 0 { return 0 }
        var idx = t & mask
        var remaining = toWrite
        var srcIdx = 0
        while remaining > 0 {
            let chunk = min(remaining, capacity - idx)
            (buffer + idx).update(from: src + srcIdx, count: chunk)
            idx = (idx + chunk) & mask
            srcIdx += chunk
            remaining -= chunk
        }
        ttac_atomic_fence_release()
        tailPtr.pointee = t + toWrite
        return toWrite
    }

    /// Consumer-side (real-time): read up to `maxSamples`; pure memmove, RT-safe.
    func read(into dst: UnsafeMutablePointer<Int16>, maxSamples: Int) -> Int {
        let t = tailPtr.pointee
        ttac_atomic_fence_acquire()
        let h = headPtr.pointee
        let avail = t - h
        let toRead = min(maxSamples, avail)
        if toRead <= 0 { return 0 }
        var idx = h & mask
        var remaining = toRead
        var dstIdx = 0
        while remaining > 0 {
            let chunk = min(remaining, capacity - idx)
            (dst + dstIdx).update(from: buffer + idx, count: chunk)
            idx = (idx + chunk) & mask
            dstIdx += chunk
            remaining -= chunk
        }
        ttac_atomic_fence_release()
        headPtr.pointee = h + toRead
        return toRead
    }
}

/// One remote user's decoded PCM, resampled to the device rate and queued for
/// mixing. Touched only on `engineQueue` (the feed hops there from the message loop).
private final class PerUserMixSource {
    private var buffer: ContiguousArray<Int16> = []
    private var head: Int = 0
    let channels: Int
    var settings: OutputUserMixSettings
    private let primeFrames: Int
    private let maxFrames: Int
    private var isPrimed = false
    /// Largest single block (in frames) this source has received. The channel
    /// codec's tx interval sets the block size (20–120+ ms), and the buffer's
    /// ceiling must scale with it — see `append`.
    private(set) var maxBlockFrames = 0

    // Diagnostics (read/reset by the engine's periodic mix report).
    var statBlocksIn = 0
    var statUnderruns = 0
    var statCeilingDrops = 0
    var statDroppedFrames = 0

    init(channels: Int, primeFrames: Int, maxFrames: Int, settings: OutputUserMixSettings) {
        self.channels = max(1, channels)
        self.primeFrames = max(primeFrames, 1)
        self.maxFrames = max(maxFrames, primeFrames + 1)
        self.settings = settings
    }

    var availableFrames: Int { (buffer.count - head) / channels }

    func append(_ samples: [Int16]) {
        let blockFrames = samples.count / channels
        if blockFrames > maxBlockFrames { maxBlockFrames = blockFrames }
        statBlocksIn += 1
        buffer.append(contentsOf: samples)
        // Catch-up ceiling: never let this source run more than one normal swing
        // ahead of the device clock — beyond that is pure added latency, so drop
        // down to a healthy level instead of pinning at the cap forever.
        //
        // The ceiling MUST scale with the observed block size: the level swings by
        // a whole block per arrival, on top of the small cushion the source
        // self-builds against delivery jitter (each early underrun shifts the
        // consume phase later, so arrivals land "earlier" next time). A fixed
        // ceiling tuned for 40 ms blocks sat exactly at that swing's peak for the
        // 60 ms tx-interval channels used by busy community servers — every trip
        // gutted the cushion, re-underrunning and re-tripping in a permanent chop
        // cycle ("buffery, barely understandable"). Scaled headroom costs nothing
        // for 20/40 ms channels (the configured max still applies as the floor)
        // and steady-state latency is set by arrivals, not by the ceiling.
        let margin = primeFrames / 2
        let effectiveMax = max(maxFrames, primeFrames + 2 * maxBlockFrames + margin)
        let availFrames = (buffer.count - head) / channels
        if availFrames > effectiveMax {
            // Keep prime + one block after a trip (not bare prime): enough to
            // bridge to the next arrival without an immediate re-underrun.
            let dropTo = primeFrames + maxBlockFrames
            statCeilingDrops += 1
            statDroppedFrames += availFrames - dropTo
            head += (availFrames - dropTo) * channels
        }
        if head > 16_384 {
            buffer.removeFirst(head)
            head = 0
        }
    }

    /// Jitter-buffer gate: a source must accumulate `primeFrames` before it starts
    /// mixing, and re-primes after an underrun — so poll/delivery jitter doesn't
    /// produce per-frame silence gaps. Returns whether to mix this tick.
    func prepareForMix() -> Bool {
        if settings.muted { return false }
        if isPrimed {
            if availableFrames == 0 {
                isPrimed = false
                statUnderruns += 1
                return false
            }
            return true
        }
        if availableFrames >= primeFrames { isPrimed = true; return true }
        return false
    }

    /// Accumulate up to `frames` frames into the stereo Int32 accumulator with
    /// the given per-side gains. The per-sample work happens in the C hot loop
    /// (`ttac_mix_add`) so it stays real-time-fast even in unoptimized builds.
    /// Returns the number of frames consumed (short when the source runs dry).
    func mixInto(_ acc: UnsafeMutablePointer<Int32>, frames: Int, leftGain: Float, rightGain: Float, collapseToMono: Bool) -> Int {
        let n = min(frames, availableFrames)
        guard n > 0 else { return 0 }
        buffer.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            ttac_mix_add(acc, base + head, Int32(n), Int32(channels), leftGain, rightGain, collapseToMono ? 1 : 0)
        }
        head += n * channels
        return n
    }
}

final class OutputAudioRenderEngine {
    // MARK: AUHAL / device (serial queue, or while AU stopped)
    private var auhal: AudioUnit?
    private var deviceSampleRate: Double = 0
    private var deviceChannels: Int = 0
    private let maxFramesPerSlice = 4096

    // MARK: Mixed-output ring (mix thread → RT)
    private var ring: OutputAudioSampleRing?
    private var targetFillFrames: Int = 0          // stereo frames
    private let ringCapacitySamples = 65_536
    /// Ring latency target. Absorbs pump-timing jitter (the mixer pumps on the
    /// message-loop tick, which can be delayed by message processing / the periodic
    /// session publish — those delays were causing the occasional dropout). Per-user
    /// jitter is handled separately by each source's prime buffer.
    // Output ring target. The decoupled timer pump removed publish-stall underruns, but
    // under MULTIPLE users the per-block resampling (e.g. 48k users -> 44.1k device) piles
    // up on the mix queue and delays the pump, so the ring must absorb that. 20ms was too
    // tight (choppy with several people); 45ms is the reliable floor. (To reclaim the rest
    // of the latency safely, move resampling off the mix queue — see the producer.)
    private let targetFillSeconds = 0.045

    // MARK: Per-user mix sources (serial queue only)
    private var userSources: [Int32: PerUserMixSource] = [:]
    private var defaultUserSettings: [Int32: OutputUserMixSettings] = [:]

    // Effective channel count per source key (1 mono / 2 stereo) for the mixer's
    // "Center" vs "Stereo" announcement. This is deliberately NOT the SDK block's
    // nChannels: a channel configured with a stereo codec decodes EVERY sender to 2
    // channels, so a mono phone mic arrives stereo-shaped but with identical L/R. The
    // pump therefore reports a CONTENT-derived value (does L actually differ from R)
    // via setAnnouncedChannels. Written from the pump, read on the main thread
    // (announcements) — hence its own lock. No entry means "not judged yet" (nothing,
    // or only silence, heard so far).
    private let announcedChannelsLock = NSLock()
    private var announcedChannelsByKey: [Int32: Int] = [:]
    private var mixScratch: [Int16] = []
    /// Stereo Int32 accumulator the C mix loop sums sources into.
    private var accScratch: [Int32] = []
    private var perUserPrimeFrames: Int = 0   // per-user jitter-buffer target
    private var perUserMaxFrames: Int = 0      // per-user catch-up ceiling

    // MARK: Cross-thread cells
    private let gainCell = UnsafeMutablePointer<Float>.allocate(capacity: 1)   // master linear gain
    private let muteCell = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private let primedCell = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    // MARK: RT-only state
    private let mixChannels = 2                     // the ring is always stereo
    private var rtDeviceChannels = 0
    private var rtPull: UnsafeMutablePointer<Int16>?
    private var rtPullCapacity = 0
    /// C array of plane pointers handed to `ttac_render_planes` (no Swift
    /// array machinery on the render thread).
    private var rtPlanesC: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>?
    private var rtPlanesCapacity = 0
    private var currentGain: Float = 1
    private var gainSmoothCoeff: Float = 0.01

    private var underflowCount = 0

    /// The engine's own serial plane (see Threading note). Decoupled from the TeamTalk
    /// message loop so the heavy channel-tree rebuild can't stall the mixer pump.
    private let engineQueue = DispatchQueue(label: "com.ttaccessible.mix-engine", qos: .userInteractive)
    /// Fine timer on `engineQueue` that drives `pumpMix` (replaces the 20 ms message-loop tick).
    private var mixTimer: DispatchSourceTimer?
    private let pumpIntervalMS = 5
    /// Pump ticks since the last per-source diagnostics report (engineQueue only).
    private var ticksSinceMixReport = 0
    /// ~5 s at the 5 ms pump interval.
    private let mixReportEveryTicks = 1000

    init() {
        gainCell.initialize(to: 1)
        muteCell.initialize(to: 0)
        primedCell.initialize(to: 0)
    }

    deinit {
        stopImpl()   // direct (no queue hop) — self is being deallocated
        gainCell.deallocate()
        muteCell.deallocate()
        primedCell.deallocate()
    }

    var isRunning: Bool { auhal != nil }

    // MARK: - Lifecycle

    func start(deviceID: AudioDeviceID) throws {
        try engineQueue.sync { try self.startImpl(deviceID: deviceID) }
    }

    private func startImpl(deviceID: AudioDeviceID) throws {
        stopImpl()

        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw OutputAudioRenderEngineError.deviceUnavailable
        }
        var audioUnit: AudioUnit?
        guard AudioComponentInstanceNew(component, &audioUnit) == noErr, let au = audioUnit else {
            throw OutputAudioRenderEngineError.deviceUnavailable
        }

        var enableIO: UInt32 = 1
        var status = AudioUnitSetProperty(
            au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
            &enableIO, UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else { AudioComponentInstanceDispose(au); throw OutputAudioRenderEngineError.deviceUnavailable }
        var disableIO: UInt32 = 0
        status = AudioUnitSetProperty(
            au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
            &disableIO, UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else { AudioComponentInstanceDispose(au); throw OutputAudioRenderEngineError.deviceUnavailable }

        var devID = deviceID
        status = AudioUnitSetProperty(
            au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &devID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { AudioComponentInstanceDispose(au); throw OutputAudioRenderEngineError.deviceUnavailable }

        var nativeASBD = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(
            au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0,
            &nativeASBD, &asbdSize
        )
        guard status == noErr else { AudioComponentInstanceDispose(au); throw OutputAudioRenderEngineError.deviceUnavailable }

        let devChannels = max(Int(nativeASBD.mChannelsPerFrame), 1)
        let devRate = nativeASBD.mSampleRate > 0 ? nativeASBD.mSampleRate : 48_000

        var feedASBD = AudioStreamBasicDescription(
            mSampleRate: devRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(devChannels),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        status = AudioUnitSetProperty(
            au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
            &feedASBD, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else { AudioComponentInstanceDispose(au); throw OutputAudioRenderEngineError.deviceUnavailable }

        var maxFrames = UInt32(maxFramesPerSlice)
        AudioUnitSetProperty(
            au, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
            &maxFrames, UInt32(MemoryLayout<UInt32>.size)
        )

        let pullCapacity = maxFramesPerSlice * mixChannels
        let pull = UnsafeMutablePointer<Int16>.allocate(capacity: pullCapacity)
        pull.initialize(repeating: 0, count: pullCapacity)

        let newRing = OutputAudioSampleRing(minimumCapacity: ringCapacitySamples)
        let targetFrames = min(
            max(Int(targetFillSeconds * devRate), 64),
            newRing.capacity / (2 * mixChannels)
        )

        var callbackStruct = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            au, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
            &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            pull.deallocate(); newRing.free(); AudioComponentInstanceDispose(au)
            throw OutputAudioRenderEngineError.deviceUnavailable
        }

        self.auhal = au
        self.deviceSampleRate = devRate
        self.deviceChannels = devChannels
        self.ring = newRing
        self.targetFillFrames = targetFrames
        // Per-user jitter target ~25 ms. The ceiling must sit well ABOVE the normal
        // block swing — audio arrives in ~40 ms chunks atomically, so the buffer
        // naturally rises to prime+~40 ms right after each block. A ceiling near that
        // would drop on every block (choppy). ~120 ms only trips on a real backlog
        // (a burst / clock drift), dropping back to the jitter target.
        self.perUserPrimeFrames = max(Int(0.025 * devRate), 64)
        self.perUserMaxFrames = max(Int(0.120 * devRate), perUserPrimeFrames + 64)
        self.rtDeviceChannels = devChannels
        self.rtPull = pull
        self.rtPullCapacity = pullCapacity
        rtPlanesC?.deallocate()
        self.rtPlanesCapacity = max(devChannels, 1)
        self.rtPlanesC = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: rtPlanesCapacity)
        self.rtPlanesC?.initialize(repeating: nil, count: rtPlanesCapacity)
        self.currentGain = gainCell.pointee
        self.gainSmoothCoeff = Float(1.0 - exp(-1.0 / (0.008 * devRate)))
        self.underflowCount = 0
        primedCell.pointee = 0

        // Publish the RT render state written just above (rtPull / rtPullCapacity /
        // rtPlanePtrs / rtDeviceChannels / currentGain / ring) with a release fence,
        // paired with the acquire at the top of render(). On the very first start the
        // AudioOutputUnitStart below is itself a de-facto barrier, but switchDevice
        // re-runs startImpl on the SAME engine instance — make the happens-before
        // explicit instead of relying on the AU start internals.
        ttac_atomic_fence_release()

        status = AudioUnitInitialize(au)
        guard status == noErr else { teardownAfterFailedStart(); throw OutputAudioRenderEngineError.startFailed }
        status = AudioOutputUnitStart(au)
        guard status == noErr else {
            AudioUnitUninitialize(au); teardownAfterFailedStart(); throw OutputAudioRenderEngineError.startFailed
        }

        AudioLogger.log("OutputAudioRenderEngine: started device rate=%.0f ch=%d targetFill=%d frames", devRate, devChannels, targetFrames)
        startMixTimer()
    }

    /// Drive pumpMix from a fine timer on engineQueue (decoupled from the message loop).
    private func startMixTimer() {
        stopMixTimer()
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now() + .milliseconds(pumpIntervalMS),
                       repeating: .milliseconds(pumpIntervalMS), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.pumpMix() }
        mixTimer = timer
        timer.resume()
    }

    private func stopMixTimer() {
        mixTimer?.cancel()
        mixTimer = nil
    }

    private func teardownAfterFailedStart() {
        if let au = auhal { AudioComponentInstanceDispose(au) }
        auhal = nil
        rtPull?.deallocate(); rtPull = nil; rtPullCapacity = 0
        ring?.free(); ring = nil
        rtDeviceChannels = 0; deviceChannels = 0; deviceSampleRate = 0
        rtPlanesC?.deallocate(); rtPlanesC = nil; rtPlanesCapacity = 0
    }

    func stop() {
        engineQueue.sync { self.stopImpl() }
    }

    private func stopImpl() {
        stopMixTimer()
        guard let au = auhal else { return }
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        auhal = nil

        let drained = underflowCount
        rtPull?.deallocate(); rtPull = nil; rtPullCapacity = 0
        rtPlanesC?.deallocate(); rtPlanesC = nil; rtPlanesCapacity = 0
        ring?.free(); ring = nil
        userSources.removeAll()
        deviceChannels = 0; deviceSampleRate = 0; rtDeviceChannels = 0
        targetFillFrames = 0
        primedCell.pointee = 0

        AudioLogger.log("OutputAudioRenderEngine: stopped (underflows=%d)", drained)
    }

    /// Rebind to a new output device (no SDK calls). Per-user sources rebuild
    /// from the still-enabled TT events within a tick (settings persist in
    /// `defaultUserSettings`); master gain/mute persist in their cells.
    func switchDevice(_ deviceID: AudioDeviceID) throws {
        try engineQueue.sync {
            guard self.isRunning else { return }
            try self.startImpl(deviceID: deviceID)
        }
    }

    // MARK: - Master gain / mute (serial queue)

    func setMasterGainDB(_ gainDB: Double) {
        gainCell.pointee = Float(pow(10.0, gainDB / 20.0))
    }

    func setMuted(_ muted: Bool) {
        muteCell.pointee = muted ? 1 : 0
    }

    // MARK: - Per-user controls (engineQueue)

    func setUserSettings(_ settings: OutputUserMixSettings, for userID: Int32) {
        engineQueue.async { [weak self] in
            guard let self else { return }
            self.defaultUserSettings[userID] = settings
            self.userSources[userID]?.settings = settings
        }
    }

    func removeUser(_ userID: Int32) {
        engineQueue.async { [weak self] in
            self?.userSources.removeValue(forKey: userID)
        }
        announcedChannelsLock.lock()
        announcedChannelsByKey.removeValue(forKey: userID)
        announcedChannelsLock.unlock()
    }

    func removeAllUsers() {
        engineQueue.async { [weak self] in
            self?.userSources.removeAll()
        }
        announcedChannelsLock.lock()
        announcedChannelsByKey.removeAll()
        announcedChannelsLock.unlock()
    }

    /// Report the content-derived effective channel count (1 mono / 2 stereo) for a
    /// source key. The pump computes this from the actual L/R content, not the SDK's
    /// codec-driven nChannels (see `announcedChannelsByKey`).
    func setAnnouncedChannels(_ channels: Int, for key: Int32) {
        announcedChannelsLock.lock()
        announcedChannelsByKey[key] = channels
        announcedChannelsLock.unlock()
    }

    /// The effective channel count last judged for the given source key (1 mono /
    /// 2 stereo), or nil if not judged yet. Drives the mixer's "Center" vs "Stereo".
    func announcedChannels(for key: Int32) -> Int? {
        announcedChannelsLock.lock(); defer { announcedChannelsLock.unlock() }
        return announcedChannelsByKey[key]
    }

    // MARK: - Producer (engineQueue): feed one remote user's decoded PCM
    //
    // `pcm` is a COPY made by the caller (the SDK audio block is released right after),
    // so we can hop to engineQueue without lifetime concerns. Interleaved, frames*channels.

    /// `profile` selects the buffering target by how this source is delivered (see
    /// OutputSourceBufferProfile). Defaults to `.network` (remote users).
    func enqueueUser(_ userID: Int32, pcm: [Int16], frames: Int, channels: Int, sampleRate: Double, profile: OutputSourceBufferProfile = .network) {
        engineQueue.async { [weak self] in
            guard let self, self.isRunning, frames > 0, channels > 0, self.deviceSampleRate > 0 else { return }

            let source: PerUserMixSource
            if let existing = self.userSources[userID], existing.channels == channels {
                source = existing
            } else {
                let rate = self.deviceSampleRate
                let prime: Int
                let maxF: Int
                switch profile {
                case .lowLatency:
                    prime = max(Int(0.010 * rate), 32)
                    maxF = max(Int(0.080 * rate), prime + 32)
                case .network:
                    prime = self.perUserPrimeFrames
                    maxF = self.perUserMaxFrames
                case .localMedia:
                    // Deeper buffer + high ceiling: the decoder can deliver in bursts
                    // and run slightly off the device clock without dropping/glitching.
                    prime = max(Int(0.090 * rate), 64)
                    maxF = max(Int(0.500 * rate), prime + 64)
                }
                source = PerUserMixSource(
                    channels: channels,
                    primeFrames: prime,
                    maxFrames: maxF,
                    settings: self.defaultUserSettings[userID] ?? OutputUserMixSettings()
                )
                self.userSources[userID] = source
            }

            if abs(sampleRate - self.deviceSampleRate) < 0.5 {
                source.append(pcm)
            } else {
                let result = AudioPCMResampler.resampleInterleaved(
                    pcm, frameCount: frames, channels: channels,
                    inputRate: sampleRate, outputRate: self.deviceSampleRate
                )
                source.append(result.samples)
            }
        }
    }

    // MARK: - Mixer (serial queue): top the ring up to target by summing users

    private func pumpMix() {
        guard let ring, isRunning else { return }

        let fillFrames = ring.fillCount() / mixChannels
        var produce = targetFillFrames - fillFrames
        if produce <= 0 {
            if primedCell.pointee == 0, fillFrames >= targetFillFrames { primedCell.pointee = 1 }
            return
        }
        // Cap a single pump (only the initial fill is large; steady-state tops up ~one tick).
        produce = min(produce, targetFillFrames)

        let needed = produce * mixChannels
        if mixScratch.count < needed {
            mixScratch = [Int16](repeating: 0, count: needed)
        }
        if accScratch.count < needed {
            accScratch = [Int32](repeating: 0, count: needed)
        }

        // Only mix sources that are primed (have buffered past their jitter target);
        // this gate also drops a source mid-tick once it underruns. The per-sample
        // summing/clamping runs in the C hot loops so it holds up in -Onone builds.
        let active = userSources.values.filter { $0.prepareForMix() }
        accScratch.withUnsafeMutableBufferPointer { accBuf in
            guard let acc = accBuf.baseAddress else { return }
            ttac_mix_clear(acc, Int32(needed))
            for src in active {
                let (lg, rg) = Self.panGains(volume: src.settings.volume, pan: src.settings.pan)
                // A stereo sender panned off center is downmixed to mono first, so
                // the pan repositions the sound instead of just fading one channel's
                // content ("lopsided stereo"). Centered stereo stays true stereo.
                let collapse = src.channels >= 2 && abs(src.settings.pan) > 0.0001
                _ = src.mixInto(acc, frames: produce, leftGain: lg, rightGain: rg, collapseToMono: collapse)
            }
            mixScratch.withUnsafeMutableBufferPointer { out in
                guard let outBase = out.baseAddress else { return }
                ttac_mix_clamp(outBase, acc, Int32(needed))
                ring.write(outBase, count: needed)
            }
        }

        if primedCell.pointee == 0, ring.fillCount() / mixChannels >= targetFillFrames {
            primedCell.pointee = 1
        }

        reportMixHealthIfDue()
    }

    /// Every ~5 s, log per-source stats — but only when a source actually
    /// underran or hit its catch-up ceiling, so a healthy session stays silent.
    /// This is what distinguishes "blocks arrive gappy" (delivery/network/server)
    /// from "blocks arrive fine but we mishandle them" (buffer tuning) in the field.
    private func reportMixHealthIfDue() {
        ticksSinceMixReport += 1
        guard ticksSinceMixReport >= mixReportEveryTicks else { return }
        ticksSinceMixReport = 0
        guard deviceSampleRate > 0, userSources.isEmpty == false else { return }

        let msPerFrame = 1000.0 / deviceSampleRate
        var troubled: [String] = []
        for (key, src) in userSources {
            if src.statUnderruns > 0 || src.statCeilingDrops > 0 {
                troubled.append(String(
                    format: "key=%d blocks=%d maxBlock=%.0fms avail=%.0fms underruns=%d drops=%d dropped=%.0fms",
                    key, src.statBlocksIn, Double(src.maxBlockFrames) * msPerFrame,
                    Double(src.availableFrames) * msPerFrame,
                    src.statUnderruns, src.statCeilingDrops,
                    Double(src.statDroppedFrames) * msPerFrame
                ))
            }
            src.statBlocksIn = 0
            src.statUnderruns = 0
            src.statCeilingDrops = 0
            src.statDroppedFrames = 0
        }
        if troubled.isEmpty == false {
            AudioLogger.log("mix diag: %d sources, troubled: %@", userSources.count, troubled.joined(separator: " | "))
        }
    }

    /// Constant-ish balance pan. Returns (leftGain, rightGain) including volume.
    private static func panGains(volume: Float, pan: Float) -> (Float, Float) {
        let p = max(-1, min(1, pan))
        let left = p <= 0 ? 1 : (1 - p)
        let right = p >= 0 ? 1 : (1 + p)
        return (volume * left, volume * right)
    }

    // MARK: - Real-time render

    fileprivate func render(
        _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
        _ inBusNumber: UInt32,
        _ inNumberFrames: UInt32,
        _ ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let ioData else { return noErr }
        // Acquire the RT render state published by startImpl's release fence before
        // reading rtDeviceChannels / rtPlanesC / rtPullCapacity / rtPull / currentGain.
        ttac_atomic_fence_acquire()
        let abl = UnsafeMutableAudioBufferListPointer(ioData)
        let devCh = rtDeviceChannels
        let frameCount = Int(inNumberFrames)
        let srcCh = mixChannels
        guard devCh > 0, frameCount > 0, devCh <= rtPlanesCapacity, let planes = rtPlanesC else { return noErr }

        var allPlanesValid = true
        var ch = 0
        while ch < devCh {
            abl[ch].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
            let p = abl[ch].mData?.assumingMemoryBound(to: Float.self)
            planes[ch] = p
            if p == nil { allPlanesValid = false }
            ch += 1
        }

        let ready = primedCell.pointee != 0
            && frameCount * srcCh <= rtPullCapacity
            && ring != nil
            && rtPull != nil

        guard ready, allPlanesValid, let ring, let pull = rtPull else {
            ch = 0
            while ch < devCh {
                if let plane = planes[ch] { plane.update(repeating: 0, count: frameCount) }
                ch += 1
            }
            return noErr
        }

        let pulled = ring.read(into: pull, maxSamples: frameCount * srcCh)
        let framesAvailable = pulled / srcCh
        if framesAvailable < frameCount { underflowCount += 1 }

        // Per-frame conversion + gain smoothing in the C hot loop (RT-safe in
        // every build configuration; -Onone Swift measurably missed deadlines).
        let target: Float = (muteCell.pointee != 0) ? 0 : gainCell.pointee
        currentGain = ttac_render_planes(
            planes, Int32(devCh), pull,
            Int32(framesAvailable), Int32(frameCount),
            currentGain, target, gainSmoothCoeff
        )

        return noErr
    }
}

enum OutputAudioRenderEngineError: LocalizedError {
    case deviceUnavailable
    case startFailed

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable, .startFailed:
            return L10n.text("connectedServer.audio.error.outputStartFailed")
        }
    }
}

// MARK: - AUHAL C render callback

private func outputRenderCallback(
    _ inRefCon: UnsafeMutableRawPointer,
    _ ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
    _ inBusNumber: UInt32,
    _ inNumberFrames: UInt32,
    _ ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<OutputAudioRenderEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    return engine.render(ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData)
}
