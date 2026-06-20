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
/// mixing. Touched only on the TeamTalk serial queue.
private final class PerUserMixSource {
    private var buffer: ContiguousArray<Int16> = []
    private var head: Int = 0
    let channels: Int
    var settings: OutputUserMixSettings
    private let primeFrames: Int
    private let maxFrames: Int
    private var isPrimed = false

    init(channels: Int, primeFrames: Int, maxFrames: Int, settings: OutputUserMixSettings) {
        self.channels = max(1, channels)
        self.primeFrames = max(primeFrames, 1)
        self.maxFrames = max(maxFrames, primeFrames + 1)
        self.settings = settings
    }

    var availableFrames: Int { (buffer.count - head) / channels }

    func append(_ samples: [Int16]) {
        buffer.append(contentsOf: samples)
        // Catch-up: never let this source get more than `maxFrames` ahead of the
        // device clock — that is pure added latency. If it does (the SDK delivered
        // a burst, or the source clock ran fast), drop the oldest audio down to the
        // `primeFrames` jitter target so latency stays bounded, instead of pinning
        // at the cap forever (which caused ~225 ms backlog + constant dropouts).
        let availFrames = (buffer.count - head) / channels
        if availFrames > maxFrames {
            head += (availFrames - primeFrames) * channels
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
            if availableFrames == 0 { isPrimed = false; return false }
            return true
        }
        if availableFrames >= primeFrames { isPrimed = true; return true }
        return false
    }

    /// Pop the next frame as (left, right) source samples (mono is duplicated).
    /// Returns false if empty.
    func popFrameLR() -> (Int16, Int16)? {
        guard buffer.count - head >= channels else { return nil }
        let base = head
        head += channels
        if channels == 1 {
            let s = buffer[base]
            return (s, s)
        }
        return (buffer[base], buffer[base + 1])
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
    private var mixScratch: [Int16] = []
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
    private var rtPlanePtrs: [UnsafeMutablePointer<Float>?] = []
    private var currentGain: Float = 1
    private var gainSmoothCoeff: Float = 0.01

    private var underflowCount = 0

    /// The engine's own serial plane (see Threading note). Decoupled from the TeamTalk
    /// message loop so the heavy channel-tree rebuild can't stall the mixer pump.
    private let engineQueue = DispatchQueue(label: "com.ttaccessible.mix-engine", qos: .userInteractive)
    /// Fine timer on `engineQueue` that drives `pumpMix` (replaces the 20 ms message-loop tick).
    private var mixTimer: DispatchSourceTimer?
    private let pumpIntervalMS = 5

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
        self.rtPlanePtrs = [UnsafeMutablePointer<Float>?](repeating: nil, count: max(devChannels, 1))
        self.currentGain = gainCell.pointee
        self.gainSmoothCoeff = Float(1.0 - exp(-1.0 / (0.008 * devRate)))
        self.underflowCount = 0
        primedCell.pointee = 0

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
        rtPlanePtrs = []
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
        rtPlanePtrs = []
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
    }

    func removeAllUsers() {
        engineQueue.async { [weak self] in
            self?.userSources.removeAll()
        }
    }

    // MARK: - Producer (engineQueue): feed one remote user's decoded PCM
    //
    // `pcm` is a COPY made by the caller (the SDK audio block is released right after),
    // so we can hop to engineQueue without lifetime concerns. Interleaved, frames*channels.

    func enqueueUser(_ userID: Int32, pcm: [Int16], frames: Int, channels: Int, sampleRate: Double) {
        engineQueue.async { [weak self] in
            guard let self, self.isRunning, frames > 0, channels > 0, self.deviceSampleRate > 0 else { return }

            let source: PerUserMixSource
            if let existing = self.userSources[userID], existing.channels == channels {
                source = existing
            } else {
                // Reserved negative keys (e.g. the local "hear myself" monitor) want
                // minimal buffering for low latency; real users get the normal jitter target.
                let lowLatency = userID < 0
                let prime = lowLatency ? max(Int(0.010 * self.deviceSampleRate), 32) : self.perUserPrimeFrames
                let maxF = lowLatency ? max(Int(0.080 * self.deviceSampleRate), prime + 32) : self.perUserMaxFrames
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

        // Only mix sources that are primed (have buffered past their jitter target);
        // this gate also drops a source mid-tick once it underruns.
        let active = userSources.values.filter { $0.prepareForMix() }
        mixScratch.withUnsafeMutableBufferPointer { out in
            guard let outBase = out.baseAddress else { return }
            for f in 0..<produce {
                var left = 0
                var right = 0
                for src in active {
                    guard let (sl, sr) = src.popFrameLR() else { continue }
                    let (lg, rg) = Self.panGains(volume: src.settings.volume, pan: src.settings.pan)
                    left += Int(Float(sl) * lg)
                    right += Int(Float(sr) * rg)
                }
                outBase[f * 2] = Int16(clamping: left)
                outBase[f * 2 + 1] = Int16(clamping: right)
            }
            ring.write(outBase, count: needed)
        }

        if primedCell.pointee == 0, ring.fillCount() / mixChannels >= targetFillFrames {
            primedCell.pointee = 1
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
        let abl = UnsafeMutableAudioBufferListPointer(ioData)
        let devCh = rtDeviceChannels
        let frameCount = Int(inNumberFrames)
        let srcCh = mixChannels
        guard devCh > 0, frameCount > 0, devCh <= rtPlanePtrs.count else { return noErr }

        for ch in 0..<devCh {
            abl[ch].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
        }

        let ready = primedCell.pointee != 0
            && frameCount * srcCh <= rtPullCapacity
            && ring != nil
            && rtPull != nil

        let target: Float = (muteCell.pointee != 0) ? 0 : gainCell.pointee
        let coeff = gainSmoothCoeff
        let invScale: Float = 1.0 / 32_768.0

        rtPlanePtrs.withUnsafeMutableBufferPointer { planesBuf in
            guard let planes = planesBuf.baseAddress else { return }
            var allPlanesValid = true
            for ch in 0..<devCh {
                let p = abl[ch].mData?.assumingMemoryBound(to: Float.self)
                planes[ch] = p
                if p == nil { allPlanesValid = false }
            }

            guard ready, allPlanesValid, let ring, let pull = rtPull else {
                for ch in 0..<devCh {
                    if let plane = planes[ch] { plane.update(repeating: 0, count: frameCount) }
                }
                return
            }

            let pulled = ring.read(into: pull, maxSamples: frameCount * srcCh)
            let framesAvailable = pulled / srcCh
            if framesAvailable < frameCount { underflowCount += 1 }

            var g = currentGain
            for f in 0..<frameCount {
                g += (target - g) * coeff
                if f < framesAvailable {
                    let base = f * srcCh   // stereo source: [L, R]
                    for ch in 0..<devCh {
                        guard let plane = planes[ch] else { continue }
                        let sample: Int16
                        if devCh == 1 {
                            sample = Int16(clamping: (Int(pull[base]) + Int(pull[base + 1])) / 2)
                        } else if ch <= 1 {
                            sample = pull[base + ch]
                        } else {
                            sample = 0   // extra device channels (>2) get silence
                        }
                        plane[f] = Float(sample) * invScale * g
                    }
                } else {
                    for ch in 0..<devCh {
                        if let plane = planes[ch] { plane[f] = 0 }
                    }
                }
            }
            currentGain = g
        }

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
