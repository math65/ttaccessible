//
//  AdvancedInputAudioPreferences.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
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

/// Microphone processing mode. The AEC always implies noise suppression (AEC3
/// convergence degrades without it), so there is no "echo cancellation alone" state.
enum MicrophoneProcessingMode: String, Codable, CaseIterable {
    /// No WebRTC processing — clean passthrough.
    case none
    /// Noise suppression only, without echo cancellation (no reference signal needed).
    case noiseSuppression
    /// Echo cancellation, which always includes noise suppression.
    case echoAndNoise
}

struct AdvancedInputAudioPreferences: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case preset
        case processingMode
        // Legacy keys decoded for backward compatibility but not re-encoded.
        case echoCancellationEnabled
        case isEnabled
    }

    var preset: InputChannelPreset
    var processingMode: MicrophoneProcessingMode

    /// Whether the AEC3 echo canceller should run (and arm the far-end reference).
    var echoCancellationEnabled: Bool { processingMode == .echoAndNoise }

    /// Whether WebRTC noise suppression should run. The AEC always implies it.
    var noiseSuppressionEnabled: Bool {
        processingMode == .noiseSuppression || processingMode == .echoAndNoise
    }

    init(
        preset: InputChannelPreset = .auto,
        processingMode: MicrophoneProcessingMode = .none
    ) {
        self.preset = preset
        self.processingMode = processingMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decodeIfPresent(InputChannelPreset.self, forKey: .preset) ?? .auto
        let processingMode: MicrophoneProcessingMode
        if let mode = try container.decodeIfPresent(MicrophoneProcessingMode.self, forKey: .processingMode) {
            processingMode = mode
        } else {
            // Migrate legacy boolean: AEC on → echo + noise; otherwise no processing.
            let legacyAEC = try container.decodeIfPresent(Bool.self, forKey: .echoCancellationEnabled) ?? false
            processingMode = legacyAEC ? .echoAndNoise : .none
        }
        self.init(preset: preset, processingMode: processingMode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(processingMode, forKey: .processingMode)
    }
}

struct InputChannelPresetOption: Identifiable, Equatable {
    let preset: InputChannelPreset
    let title: String

    var id: String {
        preset.identifier
    }
}
