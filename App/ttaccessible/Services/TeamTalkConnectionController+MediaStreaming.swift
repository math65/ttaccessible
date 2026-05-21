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
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                securityScopedURL?.stopAccessingSecurityScopedResource()
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
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
                    self.removeTranscodedMediaFileLocked()
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                    DispatchQueue.main.async {
                        completion(.failure(TeamTalkConnectionError.internalError(L10n.text("mediaStream.error.startFailed"))))
                    }
                    return
                }

                if resolved.probe.durationMSec > 0 {
                    self.mediaStreamingDurationMSec = resolved.probe.durationMSec
                }

                self.mediaStreamingActive = true
                self.mediaStreamingPath = resolved.path
                self.mediaStreamingFileName = displayName
                self.mediaStreamingSecurityScopedURL = securityScopedURL
                self.mediaStreamingElapsedMSec = 0
                self.mediaStreamingElapsedSampleAt = nil

                let myID = TT_GetMyUserID(instance)
                if resolved.probe.hasVideo, myID > 0 {
                    self.activeVideoDisplayUserID = myID
                }

                self.publishSessionLocked(instance: instance, record: record, invalidation: .audio)
                self.publishMediaStreamingProgressLocked()
                self.publishVideoDisplayStateLocked()
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                securityScopedURL?.stopAccessingSecurityScopedResource()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private struct ResolvedStreamingPath {
        let path: String
        let probe: MediaFileProbe
    }

    private func resolveStreamingPathLocked(originalPath: String, sourceURL: URL?) throws -> ResolvedStreamingPath {
        removeTranscodedMediaFileLocked()

        var probe = probeMediaFileLocked(path: originalPath)
        if probe.sdkSupported {
            return ResolvedStreamingPath(path: originalPath, probe: probe)
        }

        let fileURL = sourceURL ?? URL(fileURLWithPath: originalPath)
        guard fileURL.isFileURL else {
            throw TeamTalkConnectionError.internalError(L10n.text("mediaStream.error.unsupportedFormat"))
        }

        let transcoded = try MediaTranscodeService.transcodeForTeamTalk(sourceURL: fileURL)
        mediaStreamingTranscodedURL = transcoded
        probe = probeMediaFileLocked(path: transcoded.path)
        guard probe.sdkSupported else {
            removeTranscodedMediaFileLocked()
            throw TeamTalkConnectionError.internalError(L10n.text("mediaStream.error.unsupportedFormat"))
        }
        return ResolvedStreamingPath(path: transcoded.path, probe: probe)
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
        mediaStreamingSecurityScopedURL?.stopAccessingSecurityScopedResource()
        mediaStreamingSecurityScopedURL = nil
        mediaStreamingActive = false
        mediaStreamingPath = nil
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
        removeTranscodedMediaFileLocked()
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

        let offsetMSec = currentMediaStreamingElapsedMSecLocked()
        let previousPaused = mediaStreamingPaused
        let previousPauseIntent = mediaStreamingUserPauseIntent

        mediaStreamingPaused = paused
        mediaStreamingElapsedMSec = offsetMSec
        mediaStreamingElapsedSampleAt = paused ? nil : Date()
        mediaStreamingUserPauseIntent = paused

        var playback = makeMediaFilePlaybackLocked(offsetMSec: UInt32(TT_MEDIAPLAYBACK_OFFSET_IGNORE))
        guard applyMediaStreamingUpdateLocked(instance: instance, playback: &playback) else {
            mediaStreamingPaused = previousPaused
            mediaStreamingUserPauseIntent = previousPauseIntent
            mediaStreamingElapsedSampleAt = previousPaused ? nil : Date()
            AudioLogger.log("Media stream: pause/resume update failed paused=%d", paused ? 1 : 0)
            return
        }
        publishMediaStreamingProgressLocked()
    }

    func seekMediaStreaming(toMSec offsetMSec: UInt32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, self.mediaStreamingActive else { return }
            let clamped = self.clampedMediaStreamOffsetMSec(offsetMSec)
            if self.mediaStreamingHasVideo {
                guard self.restartMediaStreamLocked(instance: instance, offsetMSec: clamped, paused: self.mediaStreamingPaused) else {
                    AudioLogger.log("Media stream: seek restart failed at %u ms", clamped)
                    self.publishMediaStreamingProgressLocked()
                    return
                }
            } else {
                var playback = self.makeMediaFilePlaybackLocked(offsetMSec: clamped)
                guard self.applyMediaStreamingUpdateLocked(instance: instance, playback: &playback) else {
                    AudioLogger.log("Media stream: seek update failed at %u ms", clamped)
                    self.publishMediaStreamingProgressLocked()
                    return
                }
                self.mediaStreamingElapsedMSec = clamped
                self.mediaStreamingElapsedSampleAt = self.mediaStreamingPaused ? nil : Date()
            }
            self.mediaStreamingFinalizeSuppressedUntil = Date().addingTimeInterval(1.0)
            self.publishMediaStreamingProgressLocked()
        }
    }

    func setMediaStreamingBroadcastGainPercent(_ percent: Int) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, self.mediaStreamingActive else { return }
            self.mediaStreamingBroadcastGainLevel = Self.userVolumeFromPercent(Double(percent))
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

    /// Stop and restart channel media streaming (used for seek on video files where TT_Update is unreliable).
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
        mediaStreamingElapsedMSec = elapsedMSec
        mediaStreamingElapsedSampleAt = Date()
        if durationMSec > 0 {
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
