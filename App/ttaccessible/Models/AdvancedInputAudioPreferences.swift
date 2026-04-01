//
//  AdvancedInputAudioPreferences.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

enum InputChannelPreset: Codable, Hashable {
    case auto
    case mono(channel: Int)
    case stereoPair(first: Int, second: Int)
    case monoMix(first: Int, second: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case first
        case second
    }

    private enum Kind: String, Codable {
        case auto
        case mono
        case stereoPair
        case monoMix
    }

    var identifier: String {
        switch self {
        case .auto:
            return "auto"
        case .mono(let channel):
            return "mono:\(channel)"
        case .stereoPair(let first, let second):
            return "stereo:\(first):\(second)"
        case .monoMix(let first, let second):
            return "mix:\(first):\(second)"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .auto:
            self = .auto
        case .mono:
            self = .mono(channel: try container.decode(Int.self, forKey: .first))
        case .stereoPair:
            self = .stereoPair(
                first: try container.decode(Int.self, forKey: .first),
                second: try container.decode(Int.self, forKey: .second)
            )
        case .monoMix:
            self = .monoMix(
                first: try container.decode(Int.self, forKey: .first),
                second: try container.decode(Int.self, forKey: .second)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto:
            try container.encode(Kind.auto, forKey: .kind)
        case .mono(let channel):
            try container.encode(Kind.mono, forKey: .kind)
            try container.encode(channel, forKey: .first)
        case .stereoPair(let first, let second):
            try container.encode(Kind.stereoPair, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case .monoMix(let first, let second):
            try container.encode(Kind.monoMix, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }
}

struct AdvancedInputAudioPreferences: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case preset
        case echoCancellationEnabled
        // Legacy keys decoded for backward compatibility but not re-encoded.
        case isEnabled
    }

    var preset: InputChannelPreset
    var echoCancellationEnabled: Bool

    init(
        preset: InputChannelPreset = .auto,
        echoCancellationEnabled: Bool = false
    ) {
        self.preset = preset
        self.echoCancellationEnabled = echoCancellationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decodeIfPresent(InputChannelPreset.self, forKey: .preset) ?? .auto
        let echoCancellationEnabled = try container.decodeIfPresent(Bool.self, forKey: .echoCancellationEnabled) ?? false
        self.init(preset: preset, echoCancellationEnabled: echoCancellationEnabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(echoCancellationEnabled, forKey: .echoCancellationEnabled)
    }
}

struct InputChannelPresetOption: Identifiable, Equatable {
    let preset: InputChannelPreset
    let title: String

    var id: String {
        preset.identifier
    }
}
