//
//  TeamTalkConnectionController+Video.swift
//  ttaccessible
//

import Foundation

struct MediaFileProbe: Equatable {
    let hasAudio: Bool
    let hasVideo: Bool
    let durationMSec: UInt32
    let sdkSupported: Bool
}

extension TeamTalkConnectionController {

    // MARK: - Media probe / codec

    func probeMediaFileLocked(path: String) -> MediaFileProbe {
        var info = MediaFileInfo()
        let supported = path.withCString { cPath -> Bool in
            TT_GetMediaFileInfo(cPath, &info) != 0
        }
        let hasVideo = info.videoFmt.nWidth > 0 && info.videoFmt.nHeight > 0
        let hasAudio = info.audioFmt.nSampleRate > 0
        return MediaFileProbe(
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            durationMSec: info.uDurationMSec,
            sdkSupported: supported
        )
    }

    func makeVideoCodecLocked(includeVideo: Bool, bitrateKbps: UInt32 = 512) -> VideoCodec {
        var codec = VideoCodec()
        guard includeVideo else {
            codec.nCodec = NO_CODEC
            return codec
        }
        codec.nCodec = WEBM_VP8_CODEC
        codec.webm_vp8.rc_target_bitrate = max(64, bitrateKbps)
        codec.webm_vp8.nEncodeDeadline = UInt32(WEBM_VPX_DL_REALTIME)
        return codec
    }

    func makeVideoCodecLocked(from probe: MediaFileProbe) -> VideoCodec {
        makeVideoCodecLocked(includeVideo: probe.hasVideo)
    }

    // MARK: - Display target

    func setActiveVideoDisplayUserID(_ userID: Int32) {
        queue.async { [weak self] in
            guard let self else { return }
            self.activeVideoDisplayUserID = userID
            self.publishVideoDisplayStateLocked()
            self.tryAcquireDisplayedFrameLocked()
        }
    }

    func setActiveVideoDisplayFromSelection(userID: Int32, hasMediaVideo: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if userID <= 0 {
                self.activeVideoDisplayUserID = 0
                self.publishVideoDisplayStateLocked(clearFrame: true)
                return
            }
            let showsLocalPreview = self.mediaStreamingActive
                && self.instance.map { userID == TT_GetMyUserID($0) } == true
                && self.mediaStreamingHasVideo
            guard hasMediaVideo || showsLocalPreview else {
                self.activeVideoDisplayUserID = 0
                self.publishVideoDisplayStateLocked(clearFrame: true)
                return
            }
            self.activeVideoDisplayUserID = userID
            self.publishVideoDisplayStateLocked()
            self.tryAcquireDisplayedFrameLocked()
        }
    }

    func handleUserMediaFileVideoEventLocked(userID: Int32) {
        usersWithPendingMediaVideoFrame.insert(userID)
        if userID == activeVideoDisplayUserID || shouldAutoDisplayLocalMediaPreviewLocked(userID: userID) {
            if shouldAutoDisplayLocalMediaPreviewLocked(userID: userID) {
                activeVideoDisplayUserID = userID
            }
            tryAcquireMediaVideoFrameLocked(userID: userID)
        }
    }

    private func shouldAutoDisplayLocalMediaPreviewLocked(userID: Int32) -> Bool {
        guard mediaStreamingActive, mediaStreamingHasVideo, let instance else { return false }
        return activeVideoDisplayUserID == 0 && userID == TT_GetMyUserID(instance)
    }

    func tryAcquireDisplayedFrameLocked() {
        guard activeVideoDisplayUserID > 0 else { return }
        tryAcquireMediaVideoFrameLocked(userID: activeVideoDisplayUserID)
    }

    func tryAcquireMediaVideoFrameLocked(userID: Int32) {
        guard let instance else { return }
        guard let framePtr = TT_AcquireUserMediaVideoFrame(instance, userID) else { return }
        defer { TT_ReleaseUserMediaVideoFrame(instance, framePtr) }
        usersWithPendingMediaVideoFrame.remove(userID)
        guard userID == activeVideoDisplayUserID else { return }
        publishVideoFrameLocked(userID: userID, framePtr: framePtr)
    }

    func publishVideoFrameLocked(userID: Int32, framePtr: UnsafePointer<VideoFrame>) {
        let frame = framePtr.pointee
        let payload = copyVideoFramePayload(from: frame)
        let displayName = displayNameForVideoUserLocked(userID: userID)
        let state = VideoDisplayState(
            userID: userID,
            displayName: displayName,
            frame: payload
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.teamTalkConnectionController(self, didUpdateVideoDisplay: state)
        }
    }

    func publishVideoDisplayStateLocked(clearFrame: Bool = false) {
        let userID = activeVideoDisplayUserID
        guard userID > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.teamTalkConnectionController(self, didUpdateVideoDisplay: .empty)
            }
            return
        }
        let state = VideoDisplayState(
            userID: userID,
            displayName: displayNameForVideoUserLocked(userID: userID),
            frame: clearFrame ? nil : nil
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.teamTalkConnectionController(self, didUpdateVideoDisplay: state)
        }
    }

    func displayNameForVideoUserLocked(userID: Int32) -> String {
        guard let instance else { return "" }
        var user = User()
        guard TT_GetUser(instance, userID, &user) != 0 else { return "" }
        return displayName(for: user)
    }

    func copyVideoFramePayload(from frame: VideoFrame) -> VideoFramePayload? {
        let width = Int(frame.nWidth)
        let height = Int(frame.nHeight)
        let size = Int(frame.nFrameBufferSize)
        guard width > 0, height > 0, size > 0, let buffer = frame.frameBuffer else { return nil }
        let data = Data(bytes: buffer, count: size)
        return VideoFramePayload(width: width, height: height, pixels: data)
    }

    func cleanupVideoLocked() {
        mediaStreamingHasVideo = false
        removeTranscodedMediaFileLocked()
        activeVideoDisplayUserID = 0
        usersWithPendingMediaVideoFrame.removeAll()
        publishVideoDisplayStateLocked(clearFrame: true)
    }

    func removeTranscodedMediaFileLocked() {
        if let url = mediaStreamingTranscodedURL {
            try? FileManager.default.removeItem(at: url)
        }
        mediaStreamingTranscodedURL = nil
    }
}
