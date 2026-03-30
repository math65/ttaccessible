//
//  InputAudioDeviceInfo.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

struct InputAudioDeviceInfo: Equatable {
    let uid: String
    let name: String
    let inputChannels: Int
    let nominalSampleRate: Double
}
