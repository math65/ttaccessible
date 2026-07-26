//
//  TeamTalkConnectionController+MediaStreaming.swift
//  ttaccessible
//

import Foundation

extension TeamTalkConnectionController {

    func startStreamingMediaFile(at url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let didAccess = url.startAccessingSecurityScopedResource()
        startStreamingMedia(
            path: url.path,
            displayName: url.lastPathComponent,
            securityScopedURL: didAccess ? url : nil,
            sourceURL: url,
            completion: completion
        )
    }

    func startStreamingMediaURL(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        startStreamingMedia(
            path: url.absoluteString,
            displayName: url.host ?? url.absoluteString,
            securityScopedURL: nil,
            sourceURL: nil,
            completion: completion
        )
    }

    private func startStreamingMedia(
        path: String,
        displayName: String,
        securityScopedURL: URL?,
        sourceURL: URL?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let fileURL = sourceURL ?? URL(fileURLWithPath: path)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                securityScopedURL?.stopAccessingSecurityScopedResource()
                return
            }

            let preflightMessage = fileURL.isFileURL
                ? MediaStreamCompatibility.preflightUnsupportedMessage(sourceURL: fileURL)
                : nil

            self.queue.async { [weak self] in
                guard let self else {
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                    return
                }

                guard let instance = self.instance, let record = self.connectedRecord else {
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                    self.healStaleSessionIfNeededLocked()
                    self.finishOnMain(.failure(self.sessionUnavailableErrorLocked()), completion: completion)
                    return
                }

                if let preflightMessage {
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                    self.finishOnMain(
                        .failure(TeamTalkConnectionError.internalError(preflightMessage)),
                        completion: completion
                    )
                    return
                }

                if self.mediaStreamingActive {
                    self.stopStreamingMediaFileLocked(instance: instance)
                }

                do {
                    let resolved = try self.resolveStreamingPathLocked(originalPath: path, sourceURL: sourceURL)
                self.mediaStreamingPaused = false
                self.mediaStreamingBroadcastGainLevel = INT32(SOUND_GAIN_DEFAULT.rawValue)
                self.mediaStreamingHasVideo = resolved.probe.hasVideo

                var playback = self.makeMediaFilePlaybackLocked(offsetMSec: 0)
                var videoCodec = self.makeVideoCodecLocked(from: resolved.probe)
                self.mediaStreamingActiveVideoCodec = videoCodec

                let started = resolved.path.withCString { cPath -> Bool in
                    TT_StartStreamingMediaFileToChannelEx(instance, cPath, &playback, &videoCodec) != 0
                }

                guard started else {
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                    self.finishOnMain(
                        .failure(TeamTalkConnectionError.internalError(L10n.text("mediaStream.error.startFailed"))),
                        completion: completion
                    )
                    return
                }

                if resolved.probe.durationMSec > 0 {
                    self.mediaStreamingDurationMSec = resolved.probe.durationMSec
                }

                self.mediaStreamingActive = true
                // Subscribe to our own media stream so we hear what we broadcast.
                self.refreshLocalMediaAudioEventLocked(instance: instance)
                self.mediaStreamingPath = resolved.path
                self.mediaStreamingStartedHistoryLogged = false
                self.mediaStreamingSeekedWhilePaused = false
                self.mediaStreamingFileName = displayName
                self.mediaStreamingSecurityScopedURL = securityScopedURL
                self.mediaStreamingElapsedMSec = 0
                self.mediaStreamingElapsedSampleAt = Date()

                let myID = TT_GetMyUserID(instance)
                if resolved.probe.hasVideo, myID > 0 {
                    self.activeVideoDisplayUserID = myID
                }

                self.publishSessionLocked(instance: instance, record: record, invalidation: .audio)
                self.publishMediaStreamingProgressLocked()
                self.publishVideoDisplayStateLocked()
                    self.finishOnMain(.success(()), completion: completion)
                } catch {
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                    self.finishOnMain(.failure(error), completion: completion)
                }
            }
        }
    }

    /// Stream a live audio input device to the channel. The device is captured
    /// locally and served as an endless WAV on a loopback URL, which the SDK
    /// broadcasts exactly like a URL stream — the source paces itself and pads
    /// silence, so a quiet or unplugged device never ends the broadcast.
    func startStreamingAudioDevice(
        deviceUID: String,
        monitorEnabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Enumerate + open the capture device OFF the controller queue. Device
        // enumeration and the loopback server's readiness wait (up to 5s) must
        // not block the SDK's serial event loop.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            guard let device = InputAudioDeviceResolver.availableInputDevices()
                .first(where: { $0.uid == deviceUID }) else {
                self.finishOnMain(
                    .failure(TeamTalkConnectionError.internalError(L10n.text("mediaStream.device.error.deviceUnavailable"))),
                    completion: completion
                )
                return
            }

            let source = AudioDeviceStreamSource(device: device)
            let url: URL
            do {
                url = try source.start()
            } catch {
                self.finishOnMain(
                    .failure(TeamTalkConnectionError.internalError(L10n.text("mediaStream.device.error.startFailed"))),
                    completion: completion
                )
                return
            }

            self.queue.async { [weak self] in
                guard let self else { source.stop(); return }
                guard let instance = self.instance, let record = self.connectedRecord else {
                    source.stop()
                    self.healStaleSessionIfNeededLocked()
                    self.finishOnMain(.failure(self.sessionUnavailableErrorLocked()), completion: completion)
                    return
                }

                if self.mediaStreamingActive {
                    self.stopStreamingMediaFileLocked(instance: instance)
                }

                self.mediaStreamingPaused = false
                self.mediaStreamingBroadcastGainLevel = INT32(SOUND_GAIN_DEFAULT.rawValue)
                self.mediaStreamingHasVideo = false

                var playback = self.makeMediaFilePlaybackLocked(offsetMSec: 0)
                var videoCodec = self.makeVideoCodecLocked(includeVideo: false)
                self.mediaStreamingActiveVideoCodec = videoCodec

                let started = url.absoluteString.withCString { cPath -> Bool in
                    TT_StartStreamingMediaFileToChannelEx(instance, cPath, &playback, &videoCodec) != 0
                }
                guard started else {
                    source.stop()
                    self.finishOnMain(
                        .failure(TeamTalkConnectionError.internalError(L10n.text("mediaStream.device.error.startFailed"))),
                        completion: completion
                    )
                    return
                }

                self.deviceStreamSource = source
            self.deviceStreamMonitorEnabled = monitorEnabled
            self.mediaStreamingActive = true
            // Subscribe to our own media stream only if the user opted in.
            self.refreshLocalMediaAudioEventLocked(instance: instance)
            self.mediaStreamingPath = url.absoluteString
            self.mediaStreamingStartedHistoryLogged = false
            self.mediaStreamingSeekedWhilePaused = false
            self.mediaStreamingFileName = device.name
            self.mediaStreamingSecurityScopedURL = nil
            // Endless live stream: duration stays 0 so the seek UI remains inert.
            self.mediaStreamingDurationMSec = 0
            self.mediaStreamingElapsedMSec = 0
            self.mediaStreamingElapsedSampleAt = Date()

            self.publishSessionLocked(instance: instance, record: record, invalidation: .audio)
            self.publishMediaStreamingProgressLocked()
            self.finishOnMain(.success(()), completion: completion)
            }
        }
    }

    private struct ResolvedStreamingPath {
        let path: String
        let probe: MediaFileProbe
    }

    private func resolveStreamingPathLocked(originalPath: String, sourceURL: URL?) throws -> ResolvedStreamingPath {
        let probe = probeMediaFileLocked(path: originalPath)

        if let message = MediaStreamCompatibility.unsupportedMessageAfterSDKProbe(probe: probe) {
            throw TeamTalkConnectionError.internalError(message)
        }

        return ResolvedStreamingPath(path: originalPath, probe: probe)
    }

    func stopStreamingMediaFile() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            self.stopStreamingMediaFileLocked(instance: instance)
        }
    }

    func stopStreamingMediaFileLocked(instance: UnsafeMutableRawPointer) {
        guard mediaStreamingActive else { return }
        _ = TT_StopStreamingMediaFileToChannel(instance)
        finalizeMediaStreamingLocked(instance: instance, reason: .userStopped)
    }

    enum MediaStreamingFinalizeReason {
        case userStopped
        case finished
        case error
    }

    func finalizeMediaStreamingLocked(instance: UnsafeMutableRawPointer, reason: MediaStreamingFinalizeReason) {
        deviceStreamSource?.stop()
        deviceStreamSource = nil
        deviceStreamMonitorEnabled = false
        mediaStreamingSecurityScopedURL?.stopAccessingSecurityScopedResource()
        mediaStreamingSecurityScopedURL = nil
        mediaStreamingActive = false
        // Drop our own media subscription now that we're no longer broadcasting.
        refreshLocalMediaAudioEventLocked(instance: instance)
        mediaStreamingPath = nil
        mediaStreamingStartedHistoryLogged = false
        mediaStreamingSeekedWhilePaused = false
        mediaStreamingFileName = nil
        mediaStreamingRestartInFlight = false
        mediaStreamingUserPauseIntent = false
        mediaStreamingPaused = false
        mediaStreamingDurationMSec = 0
        mediaStreamingElapsedMSec = 0
        mediaStreamingElapsedSampleAt = nil
        mediaStreamingHasVideo = false
        mediaStreamingActiveVideoCodec = VideoCodec()
        mediaStreamingFinalizeSuppressedUntil = nil
        mediaStreamingResumeAnchorMSec = nil
        mediaStreamingResumeAnchorUntil = nil
        let myID = TT_GetMyUserID(instance)
        if myID > 0, activeVideoDisplayUserID == myID {
            activeVideoDisplayUserID = 0
            publishVideoDisplayStateLocked(clearFrame: true)
        }

        switch reason {
        case .finished:
            appendHistoryLocked(
                kind: .mediaStreamingFinished,
                message: L10n.text("history.mediaStreamingFinished")
            )
        case .error, .userStopped:
            break
        }

        if let record = connectedRecord {
            publishSessionLocked(instance: instance, record: record, invalidation: [.audio, .history])
        }
        publishMediaStreamingProgressLocked()
    }

    func appendMediaStreamingStartedHistoryLocked(fileName: String) {
        appendHistoryLocked(
            kind: .mediaStreamingStarted,
            message: L10n.format("history.mediaStreamingStarted", fileName)
        )
    }

    // MARK: - Update operations (pause / seek / gain / local volume)

    func toggleMediaStreamingPaused() {
        queue.async { [weak self] in
            guard let self else { return }
            self.setMediaStreamingPausedLocked(!self.mediaStreamingPaused)
        }
    }

    func setMediaStreamingPaused(_ paused: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.setMediaStreamingPausedLocked(paused)
        }
    }

    private func setMediaStreamingPausedLocked(_ paused: Bool) {
        guard let instance = self.instance, self.mediaStreamingActive else { return }
        if self.mediaStreamingPaused == paused { return }

        // Live device streams can't be SDK-paused: the loopback keeps producing,
        // so TT_UpdateStreamingMediaFileToChannel(bPaused) desyncs it and resume
        // breaks. Instead mute the capture — the loopback keeps feeding the SDK
        // real-time silence, so there's no discontinuity.
        if let deviceStreamSource {
            mediaStreamingPaused = paused
            mediaStreamingUserPauseIntent = paused
            mediaStreamingElapsedSampleAt = paused ? nil : Date()
            deviceStreamSource.setMuted(paused)
            publishMediaStreamingProgressLocked()
            return
        }

        let offsetMSec = currentMediaStreamingElapsedMSecLocked()
        let previousPaused = mediaStreamingPaused
        let previousPauseIntent = mediaStreamingUserPauseIntent
        let previousElapsedMSec = mediaStreamingElapsedMSec
        let previousElapsedSampleAt = mediaStreamingElapsedSampleAt

        mediaStreamingPaused = paused
        mediaStreamingElapsedMSec = offsetMSec
        mediaStreamingElapsedSampleAt = paused ? nil : Date()
        mediaStreamingUserPauseIntent = paused

        if !paused, mediaStreamingSeekedWhilePaused {
            mediaStreamingSeekedWhilePaused = false
            guard restartMediaStreamLocked(instance: instance, offsetMSec: offsetMSec, paused: false) else {
                mediaStreamingPaused = previousPaused
                mediaStreamingUserPauseIntent = previousPauseIntent
                mediaStreamingElapsedMSec = previousElapsedMSec
                mediaStreamingElapsedSampleAt = previousElapsedSampleAt
                AudioLogger.log("Media stream: resume-after-seek restart failed at %u ms", offsetMSec)
                return
            }
            publishMediaStreamingProgressLocked()
            return
        }

        var playback = makeMediaFilePlaybackLocked(offsetMSec: UInt32(TT_MEDIAPLAYBACK_OFFSET_IGNORE))
        guard applyMediaStreamingUpdateLocked(instance: instance, playback: &playback) else {
            mediaStreamingPaused = previousPaused
            mediaStreamingUserPauseIntent = previousPauseIntent
            mediaStreamingElapsedMSec = previousElapsedMSec
            mediaStreamingElapsedSampleAt = previousElapsedSampleAt
            AudioLogger.log("Media stream: pause/resume update failed paused=%d", paused ? 1 : 0)
            return
        }
        publishMediaStreamingProgressLocked()
    }

    func seekMediaStreaming(toMSec offsetMSec: UInt32) {
        // Coalesce: each seek stops and restarts the SDK stream, so a key-repeat
        // flood would otherwise queue restarts that keep seeking after release.
        guard mediaStreamingSeekRequest.submit(offsetMSec) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let requestedMSec = self.mediaStreamingSeekRequest.take() else { return }
            guard let instance = self.instance, self.mediaStreamingActive else { return }
            let clamped = self.clampedMediaStreamOffsetMSec(requestedMSec)
            guard self.restartMediaStreamLocked(instance: instance, offsetMSec: clamped, paused: self.mediaStreamingPaused) else {
                AudioLogger.log("Media stream: seek restart failed at %u ms", clamped)
                self.publishMediaStreamingProgressLocked()
                return
            }
            self.mediaStreamingSeekedWhilePaused = self.mediaStreamingPaused
            self.mediaStreamingFinalizeSuppressedUntil = Date().addingTimeInterval(1.0)
            self.publishMediaStreamingProgressLocked()
        }
    }

    func setMediaStreamingBroadcastGainPercent(_ percent: Int) {
        // Coalesce: the SDK update is slow enough on some machines that
        // key-repeat floods queue a backlog which keeps stepping the gain
        // after the key is released — only the newest value matters.
        guard mediaStreamingGainRequest.submit(percent) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let requestedPercent = self.mediaStreamingGainRequest.take() else { return }
            guard let instance = self.instance, self.mediaStreamingActive else { return }
            self.mediaStreamingBroadcastGainLevel = Self.userVolumeFromPercent(Double(requestedPercent))
            var playback = self.makeMediaFilePlaybackLocked(offsetMSec: UInt32(TT_MEDIAPLAYBACK_OFFSET_IGNORE))
            guard self.applyMediaStreamingUpdateLocked(instance: instance, playback: &playback) else {
                AudioLogger.log("Media stream: broadcast gain update failed")
                return
            }
            self.publishMediaStreamingProgressLocked()
        }
    }

    private func clampedMediaStreamOffsetMSec(_ offsetMSec: UInt32) -> UInt32 {
        guard mediaStreamingDurationMSec > 1 else { return offsetMSec }
        return min(offsetMSec, mediaStreamingDurationMSec - 1)
    }

    func shouldIgnoreMediaStreamingFinalizeLocked(info: MediaFileInfo) -> Bool {
        if mediaStreamingRestartInFlight { return true }
        guard let until = mediaStreamingFinalizeSuppressedUntil, Date() < until else {
            return false
        }
        guard mediaStreamingDurationMSec > 0 else { return true }
        // Ignore spurious finish/abort right after a seek while still far from the end.
        return info.uElapsedMSec + 2_000 < mediaStreamingDurationMSec
    }

    /// Re-point an active media stream at the newly-joined channel. The SDK
    /// streams to whatever channel you're in, so a channel switch requires a
    /// stop + restart — otherwise the broadcast keeps going to the old channel
    /// (or stops), which is the "device stream breaks on channel switch" bug.
    func restartMediaStreamForChannelChangeLocked(instance: UnsafeMutableRawPointer) {
        guard mediaStreamingActive, mediaStreamingPath != nil else { return }
        if deviceStreamSource != nil {
            // Live device stream: restart to the new channel, never SDK-paused —
            // the mute/pause state lives in the capture source and persists across
            // the restart (same AudioDeviceStreamSource, same loopback URL). The
            // restart resets mediaStreamingPaused, so restore it to match the
            // source's still-muted state.
            let wasPaused = mediaStreamingPaused
            _ = restartMediaStreamLocked(instance: instance, offsetMSec: 0, paused: false)
            mediaStreamingPaused = wasPaused
        } else {
            let offset = currentMediaStreamingElapsedMSecLocked()
            _ = restartMediaStreamLocked(instance: instance, offsetMSec: offset, paused: mediaStreamingPaused)
        }
    }

    /// Stop and restart channel media streaming (TT_Update seek/resume is unreliable for media files).
    @discardableResult
    private func restartMediaStreamLocked(
        instance: UnsafeMutableRawPointer,
        offsetMSec: UInt32,
        paused: Bool
    ) -> Bool {
        guard let path = mediaStreamingPath else { return false }

        mediaStreamingRestartInFlight = true
        defer { mediaStreamingRestartInFlight = false }

        _ = TT_StopStreamingMediaFileToChannel(instance)

        var playback = makeMediaFilePlaybackLocked(offsetMSec: offsetMSec)
        playback.bPaused = paused ? 1 : 0
        var videoCodec = mediaStreamingActiveVideoCodec

        let started = path.withCString { cPath -> Bool in
            TT_StartStreamingMediaFileToChannelEx(instance, cPath, &playback, &videoCodec) != 0
        }
        guard started else { return false }

        mediaStreamingElapsedMSec = offsetMSec
        mediaStreamingPaused = paused
        mediaStreamingElapsedSampleAt = paused ? nil : Date()
        mediaStreamingFinalizeSuppressedUntil = Date().addingTimeInterval(1.0)
        if !paused {
            mediaStreamingResumeAnchorMSec = offsetMSec
            mediaStreamingResumeAnchorUntil = Date().addingTimeInterval(2.0)
        }
        return true
    }

    @discardableResult
    private func applyMediaStreamingUpdateLocked(
        instance: UnsafeMutableRawPointer,
        playback: inout MediaFilePlayback
    ) -> Bool {
        // Audio-only updates: pass NULL video codec per SDK (do not re-send WEBM_VP8 on update).
        TT_UpdateStreamingMediaFileToChannel(instance, &playback, nil) != 0
    }

    // MARK: - Internals

    func makeMediaFilePlaybackLocked(offsetMSec: UInt32) -> MediaFilePlayback {
        var playback = MediaFilePlayback()
        playback.uOffsetMSec = offsetMSec
        playback.bPaused = mediaStreamingPaused ? 1 : 0
        playback.audioPreprocessor.nPreprocessor = TEAMTALK_AUDIOPREPROCESSOR
        playback.audioPreprocessor.ttpreprocessor.nGainLevel = mediaStreamingBroadcastGainLevel
        playback.audioPreprocessor.ttpreprocessor.bMuteLeftSpeaker = 0
        playback.audioPreprocessor.ttpreprocessor.bMuteRightSpeaker = 0
        return playback
    }

    /// Returns the best-effort current elapsed time in milliseconds:
    /// interpolates from the last sample using wall-clock when playing,
    /// returns the sample as-is when paused.
    func currentMediaStreamingElapsedMSecLocked() -> UInt32 {
        guard mediaStreamingActive else { return 0 }
        guard let sampledAt = mediaStreamingElapsedSampleAt, !mediaStreamingPaused else {
            return mediaStreamingElapsedMSec
        }
        let delta = Date().timeIntervalSince(sampledAt) * 1000
        let projected = Double(mediaStreamingElapsedMSec) + max(0, delta)
        let capped = mediaStreamingDurationMSec > 0
            ? min(projected, Double(mediaStreamingDurationMSec))
            : projected
        return UInt32(capped)
    }

    func updateMediaStreamingProgressLocked(elapsedMSec: UInt32, durationMSec: UInt32) {
        if mediaStreamingSeekedWhilePaused, mediaStreamingPaused {
            if durationMSec > 0 {
                mediaStreamingDurationMSec = durationMSec
            }
            publishMediaStreamingProgressLocked()
            return
        }
        if let anchorMSec = mediaStreamingResumeAnchorMSec,
           let anchorUntil = mediaStreamingResumeAnchorUntil,
           Date() < anchorUntil,
           elapsedMSec + 2_000 < anchorMSec {
            if durationMSec > 0 {
                mediaStreamingDurationMSec = durationMSec
            }
            publishMediaStreamingProgressLocked()
            return
        }
        if let anchorMSec = mediaStreamingResumeAnchorMSec,
           elapsedMSec + 500 >= anchorMSec {
            mediaStreamingResumeAnchorMSec = nil
            mediaStreamingResumeAnchorUntil = nil
        }
        mediaStreamingElapsedMSec = elapsedMSec
        mediaStreamingElapsedSampleAt = Date()
        // Device streams are endless: whatever duration FFmpeg guesses from the
        // WAV header must not enable the seek UI.
        if durationMSec > 0, deviceStreamSource == nil {
            mediaStreamingDurationMSec = durationMSec
        }
        publishMediaStreamingProgressLocked()
        if mediaStreamingHasVideo, let instance, activeVideoDisplayUserID == TT_GetMyUserID(instance) {
            tryAcquireMediaVideoFrameLocked(userID: activeVideoDisplayUserID)
        }
    }

    func publishMediaStreamingProgressLocked() {
        let progress = MediaStreamingProgress(
            isActive: mediaStreamingActive,
            isPaused: mediaStreamingPaused,
            fileName: mediaStreamingFileName,
            elapsedMSec: currentMediaStreamingElapsedMSecLocked(),
            elapsedSampleAt: mediaStreamingElapsedSampleAt,
            durationMSec: mediaStreamingDurationMSec,
            broadcastGainPercent: Self.percentFromUserVolume(mediaStreamingBroadcastGainLevel)
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.teamTalkConnectionController(self, didUpdateMediaStreamingProgress: progress)
        }
    }
}

struct MediaStreamingProgress: Equatable {
    let isActive: Bool
    let isPaused: Bool
    let fileName: String?
    let elapsedMSec: UInt32
    let elapsedSampleAt: Date?
    let durationMSec: UInt32
    let broadcastGainPercent: Int

    static let inactive = MediaStreamingProgress(
        isActive: false,
        isPaused: false,
        fileName: nil,
        elapsedMSec: 0,
        elapsedSampleAt: nil,
        durationMSec: 0,
        broadcastGainPercent: 50
    )
}
