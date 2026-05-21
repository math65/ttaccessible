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
            completion: completion
        )
    }

    func startStreamingMediaURL(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        startStreamingMedia(
            path: url.absoluteString,
            displayName: url.host ?? url.absoluteString,
            securityScopedURL: nil,
            completion: completion
        )
    }

    private func startStreamingMedia(
        path: String,
        displayName: String,
        securityScopedURL: URL?,
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

            self.mediaStreamingPaused = false
            self.mediaStreamingBroadcastGainLevel = INT32(SOUND_GAIN_DEFAULT.rawValue)

            var playback = self.makeMediaFilePlaybackLocked(offsetMSec: 0)
            var videoCodec = VideoCodec()
            videoCodec.nCodec = NO_CODEC

            let started = path.withCString { cPath -> Bool in
                TT_StartStreamingMediaFileToChannelEx(instance, cPath, &playback, &videoCodec) != 0
            }

            guard started else {
                securityScopedURL?.stopAccessingSecurityScopedResource()
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("mediaStream.error.startFailed"))))
                }
                return
            }

            self.mediaStreamingActive = true
            self.mediaStreamingFileName = displayName
            self.mediaStreamingSecurityScopedURL = securityScopedURL
            self.mediaStreamingDurationMSec = 0
            self.mediaStreamingElapsedMSec = 0
            self.mediaStreamingElapsedSampleAt = nil
            self.publishSessionLocked(instance: instance, record: record, invalidation: .audio)
            self.publishMediaStreamingProgressLocked()
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
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
        mediaStreamingFileName = nil
        mediaStreamingPaused = false
        mediaStreamingDurationMSec = 0
        mediaStreamingElapsedMSec = 0
        mediaStreamingElapsedSampleAt = nil

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
        if paused {
            self.mediaStreamingElapsedMSec = self.currentMediaStreamingElapsedMSecLocked()
        }
        self.mediaStreamingPaused = paused
        self.mediaStreamingElapsedSampleAt = Date()
        var playback = self.makeMediaFilePlaybackLocked(offsetMSec: UInt32(TT_MEDIAPLAYBACK_OFFSET_IGNORE))
        var videoCodec = VideoCodec()
        videoCodec.nCodec = NO_CODEC
        _ = TT_UpdateStreamingMediaFileToChannel(instance, &playback, &videoCodec)
        self.publishMediaStreamingProgressLocked()
    }

    func seekMediaStreaming(toMSec offsetMSec: UInt32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, self.mediaStreamingActive else { return }
            let clamped: UInt32
            if self.mediaStreamingDurationMSec > 0 {
                clamped = min(offsetMSec, self.mediaStreamingDurationMSec - 1)
            } else {
                clamped = offsetMSec
            }
            self.mediaStreamingElapsedMSec = clamped
            self.mediaStreamingElapsedSampleAt = Date()
            var playback = self.makeMediaFilePlaybackLocked(offsetMSec: clamped)
            var videoCodec = VideoCodec()
            videoCodec.nCodec = NO_CODEC
            _ = TT_UpdateStreamingMediaFileToChannel(instance, &playback, &videoCodec)
            self.publishMediaStreamingProgressLocked()
        }
    }

    func setMediaStreamingBroadcastGainPercent(_ percent: Int) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, self.mediaStreamingActive else { return }
            self.mediaStreamingBroadcastGainLevel = Self.userVolumeFromPercent(Double(percent))
            var playback = self.makeMediaFilePlaybackLocked(offsetMSec: UInt32(TT_MEDIAPLAYBACK_OFFSET_IGNORE))
            var videoCodec = VideoCodec()
            videoCodec.nCodec = NO_CODEC
            _ = TT_UpdateStreamingMediaFileToChannel(instance, &playback, &videoCodec)
            self.publishMediaStreamingProgressLocked()
        }
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
    }

    func publishMediaStreamingProgressLocked() {
        let progress = MediaStreamingProgress(
            isActive: mediaStreamingActive,
            isPaused: mediaStreamingPaused,
            fileName: mediaStreamingFileName,
            elapsedMSec: mediaStreamingElapsedMSec,
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
