//
//  VideoFramePayload.swift
//  ttaccessible
//

import Foundation

/// RGB32 frame copied from TeamTalk `VideoFrame.frameBuffer`.
struct VideoFramePayload: Equatable {
    let width: Int
    let height: Int
    let pixels: Data

    var isEmpty: Bool {
        width <= 0 || height <= 0 || pixels.isEmpty
    }
}

struct VideoDisplayState: Equatable {
    let userID: Int32
    let displayName: String
    let frame: VideoFramePayload?

    static let empty = VideoDisplayState(userID: 0, displayName: "", frame: nil)
}
