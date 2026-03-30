//
//  AdvancedInputAudioPreferences.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

enum DynamicProcessorMode: String, Codable, CaseIterable, Hashable {
    case gate
    case expander

    nonisolated var localizationKey: String {
        switch self {
        case .gate:
            return "preferences.audio.advanced.dynamic.mode.gate"
        case .expander:
            return "preferences.audio.advanced.dynamic.mode.expander"
        }
    }
}

enum LimiterControlMode: String, Codable, CaseIterable, Hashable {
    case preset
    case manual

    nonisolated var localizationKey: String {
        switch self {
        case .preset:
            return "preferences.audio.advanced.limiter.mode.preset"
        case .manual:
            return "preferences.audio.advanced.limiter.mode.manual"
        }
    }
}

enum LimiterPreset: String, Codable, CaseIterable, Hashable {
    case minus1dB
    case minus3dB
    case minus6dB

    nonisolated var localizationKey: String {
        switch self {
        case .minus1dB:
            return "preferences.audio.advanced.limiter.preset.minus1dB"
        case .minus3dB:
            return "preferences.audio.advanced.limiter.preset.minus3dB"
        case .minus6dB:
            return "preferences.audio.advanced.limiter.preset.minus6dB"
        }
    }

    nonisolated var thresholdDB: Double {
        switch self {
        case .minus1dB:
            return -1
        case .minus3dB:
            return -3
        case .minus6dB:
            return -6
        }
    }

    nonisolated var releaseMilliseconds: Double {
        switch self {
        case .minus1dB:
            return 80
        case .minus3dB:
            return 140
        case .minus6dB:
            return 220
        }
    }
}

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
    struct Gate: Codable, Equatable {
        var enabled: Bool
        var thresholdDB: Double
        var attackMilliseconds: Double
        var holdMilliseconds: Double
        var releaseMilliseconds: Double

        init(
            enabled: Bool = false,
            thresholdDB: Double = -42,
            attackMilliseconds: Double = 10,
            holdMilliseconds: Double = 120,
            releaseMilliseconds: Double = 180
        ) {
            self.enabled = enabled
            self.thresholdDB = AdvancedInputAudioPreferences.clampNoiseGateThresholdDB(thresholdDB)
            self.attackMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateAttackMilliseconds(attackMilliseconds)
            self.holdMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateHoldMilliseconds(holdMilliseconds)
            self.releaseMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateReleaseMilliseconds(releaseMilliseconds)
        }
    }

    struct Expander: Codable, Equatable {
        var thresholdDB: Double
        var ratio: Double
        var attackMilliseconds: Double
        var releaseMilliseconds: Double

        init(
            thresholdDB: Double = -42,
            ratio: Double = 2.5,
            attackMilliseconds: Double = 10,
            releaseMilliseconds: Double = 180
        ) {
            self.thresholdDB = AdvancedInputAudioPreferences.clampNoiseGateThresholdDB(thresholdDB)
            self.ratio = AdvancedInputAudioPreferences.clampExpanderRatio(ratio)
            self.attackMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateAttackMilliseconds(attackMilliseconds)
            self.releaseMilliseconds = AdvancedInputAudioPreferences.clampNoiseGateReleaseMilliseconds(releaseMilliseconds)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case preset
        case dynamicProcessorEnabled
        case dynamicProcessorMode
        case gate
        case expander
        case noiseGate
        case limiterEnabled
        case limiterMode
        case limiterPreset
        case limiterThresholdDB
        case limiterReleaseMilliseconds
        case limiterIntensity
    }

    private enum LegacyLimiterIntensity: String, Codable {
        case low
        case medium
        case high
    }

    nonisolated static let manualThresholdRange: ClosedRange<Double> = -18...0
    nonisolated static let manualReleaseRange: ClosedRange<Double> = 20...400
    nonisolated static let noiseGateThresholdRange: ClosedRange<Double> = -72 ... -12
    nonisolated static let noiseGateAttackRange: ClosedRange<Double> = 0 ... 100
    nonisolated static let noiseGateHoldRange: ClosedRange<Double> = 0 ... 500
    nonisolated static let noiseGateReleaseRange: ClosedRange<Double> = 20 ... 1000
    nonisolated static let expanderRatioRange: ClosedRange<Double> = 1.5 ... 6.0

    var isEnabled: Bool
    var preset: InputChannelPreset
    var dynamicProcessorEnabled: Bool
    var dynamicProcessorMode: DynamicProcessorMode
    var gate: Gate
    var expander: Expander
    var limiterEnabled: Bool
    var limiterMode: LimiterControlMode
    var limiterPreset: LimiterPreset
    var limiterThresholdDB: Double
    var limiterReleaseMilliseconds: Double

    init(
        isEnabled: Bool = false,
        preset: InputChannelPreset = .auto,
        dynamicProcessorEnabled: Bool = false,
        dynamicProcessorMode: DynamicProcessorMode = .gate,
        gate: Gate = Gate(),
        expander: Expander = Expander(),
        limiterEnabled: Bool = false,
        limiterMode: LimiterControlMode = .preset,
        limiterPreset: LimiterPreset = .minus3dB,
        limiterThresholdDB: Double = -3,
        limiterReleaseMilliseconds: Double = 140
    ) {
        self.isEnabled = isEnabled
        self.preset = preset
        self.dynamicProcessorEnabled = dynamicProcessorEnabled
        self.dynamicProcessorMode = dynamicProcessorMode
        self.gate = gate
        self.expander = expander
        self.limiterEnabled = limiterEnabled
        self.limiterMode = limiterMode
        self.limiterPreset = limiterPreset
        self.limiterThresholdDB = Self.clampThresholdDB(limiterThresholdDB)
        self.limiterReleaseMilliseconds = Self.clampReleaseMilliseconds(limiterReleaseMilliseconds)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let preset = try container.decodeIfPresent(InputChannelPreset.self, forKey: .preset) ?? .auto
        let legacyGate = try container.decodeIfPresent(Gate.self, forKey: .noiseGate) ?? Gate()
        let gate = try container.decodeIfPresent(Gate.self, forKey: .gate) ?? legacyGate
        let dynamicProcessorEnabled = try container.decodeIfPresent(Bool.self, forKey: .dynamicProcessorEnabled) ?? legacyGate.enabled
        let dynamicProcessorMode = try container.decodeIfPresent(DynamicProcessorMode.self, forKey: .dynamicProcessorMode) ?? .gate
        let expander = try container.decodeIfPresent(Expander.self, forKey: .expander) ?? Expander(
            thresholdDB: gate.thresholdDB,
            ratio: 2.5,
            attackMilliseconds: gate.attackMilliseconds,
            releaseMilliseconds: gate.releaseMilliseconds
        )
        let limiterEnabled = try container.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? false

        if let limiterMode = try container.decodeIfPresent(LimiterControlMode.self, forKey: .limiterMode) {
            let limiterPreset = try container.decodeIfPresent(LimiterPreset.self, forKey: .limiterPreset) ?? .minus3dB
            let limiterThresholdDB = try container.decodeIfPresent(Double.self, forKey: .limiterThresholdDB) ?? limiterPreset.thresholdDB
            let limiterReleaseMilliseconds = try container.decodeIfPresent(Double.self, forKey: .limiterReleaseMilliseconds) ?? limiterPreset.releaseMilliseconds
            self.init(
                isEnabled: isEnabled,
                preset: preset,
                dynamicProcessorEnabled: dynamicProcessorEnabled,
                dynamicProcessorMode: dynamicProcessorMode,
                gate: gate,
                expander: expander,
                limiterEnabled: limiterEnabled,
                limiterMode: limiterMode,
                limiterPreset: limiterPreset,
                limiterThresholdDB: limiterThresholdDB,
                limiterReleaseMilliseconds: limiterReleaseMilliseconds
            )
            return
        }

        let legacyPreset: LimiterPreset
        switch try container.decodeIfPresent(LegacyLimiterIntensity.self, forKey: .limiterIntensity) ?? .medium {
        case .low:
            legacyPreset = .minus1dB
        case .medium:
            legacyPreset = .minus3dB
        case .high:
            legacyPreset = .minus6dB
        }

        self.init(
            isEnabled: isEnabled,
            preset: preset,
            dynamicProcessorEnabled: dynamicProcessorEnabled,
            dynamicProcessorMode: dynamicProcessorMode,
            gate: gate,
            expander: expander,
            limiterEnabled: limiterEnabled,
            limiterMode: .preset,
            limiterPreset: legacyPreset,
            limiterThresholdDB: legacyPreset.thresholdDB,
            limiterReleaseMilliseconds: legacyPreset.releaseMilliseconds
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(preset, forKey: .preset)
        try container.encode(dynamicProcessorEnabled, forKey: .dynamicProcessorEnabled)
        try container.encode(dynamicProcessorMode, forKey: .dynamicProcessorMode)
        try container.encode(gate, forKey: .gate)
        try container.encode(expander, forKey: .expander)
        try container.encode(limiterEnabled, forKey: .limiterEnabled)
        try container.encode(limiterMode, forKey: .limiterMode)
        try container.encode(limiterPreset, forKey: .limiterPreset)
        try container.encode(Self.clampThresholdDB(limiterThresholdDB), forKey: .limiterThresholdDB)
        try container.encode(Self.clampReleaseMilliseconds(limiterReleaseMilliseconds), forKey: .limiterReleaseMilliseconds)
    }

    nonisolated var effectiveLimiterThresholdDB: Double {
        switch limiterMode {
        case .preset:
            return limiterPreset.thresholdDB
        case .manual:
            return Self.clampThresholdDB(limiterThresholdDB)
        }
    }

    nonisolated var effectiveLimiterReleaseMilliseconds: Double {
        switch limiterMode {
        case .preset:
            return limiterPreset.releaseMilliseconds
        case .manual:
            return Self.clampReleaseMilliseconds(limiterReleaseMilliseconds)
        }
    }

    nonisolated func normalized() -> AdvancedInputAudioPreferences {
        var normalized = self
        normalized.gate.thresholdDB = Self.clampNoiseGateThresholdDB(gate.thresholdDB)
        normalized.gate.attackMilliseconds = Self.clampNoiseGateAttackMilliseconds(gate.attackMilliseconds)
        normalized.gate.holdMilliseconds = Self.clampNoiseGateHoldMilliseconds(gate.holdMilliseconds)
        normalized.gate.releaseMilliseconds = Self.clampNoiseGateReleaseMilliseconds(gate.releaseMilliseconds)
        normalized.expander.thresholdDB = Self.clampNoiseGateThresholdDB(expander.thresholdDB)
        normalized.expander.ratio = Self.clampExpanderRatio(expander.ratio)
        normalized.expander.attackMilliseconds = Self.clampNoiseGateAttackMilliseconds(expander.attackMilliseconds)
        normalized.expander.releaseMilliseconds = Self.clampNoiseGateReleaseMilliseconds(expander.releaseMilliseconds)
        normalized.limiterThresholdDB = Self.clampThresholdDB(limiterThresholdDB)
        normalized.limiterReleaseMilliseconds = Self.clampReleaseMilliseconds(limiterReleaseMilliseconds)
        return normalized
    }

    nonisolated static func clampNoiseGateThresholdDB(_ value: Double) -> Double {
        min(max(value.rounded(), noiseGateThresholdRange.lowerBound), noiseGateThresholdRange.upperBound)
    }

    nonisolated static func clampNoiseGateAttackMilliseconds(_ value: Double) -> Double {
        min(max(value.rounded(), noiseGateAttackRange.lowerBound), noiseGateAttackRange.upperBound)
    }

    nonisolated static func clampNoiseGateHoldMilliseconds(_ value: Double) -> Double {
        min(max(value.rounded(), noiseGateHoldRange.lowerBound), noiseGateHoldRange.upperBound)
    }

    nonisolated static func clampNoiseGateReleaseMilliseconds(_ value: Double) -> Double {
        min(max(value.rounded(), noiseGateReleaseRange.lowerBound), noiseGateReleaseRange.upperBound)
    }

    nonisolated static func clampExpanderRatio(_ value: Double) -> Double {
        let clamped = min(max(value, expanderRatioRange.lowerBound), expanderRatioRange.upperBound)
        return (clamped * 10).rounded() / 10
    }

    nonisolated static func clampThresholdDB(_ value: Double) -> Double {
        min(max(value, manualThresholdRange.lowerBound), manualThresholdRange.upperBound)
    }

    nonisolated static func clampReleaseMilliseconds(_ value: Double) -> Double {
        min(max(value, manualReleaseRange.lowerBound), manualReleaseRange.upperBound)
    }
}

struct InputChannelPresetOption: Identifiable, Equatable {
    let preset: InputChannelPreset
    let title: String

    var id: String {
        preset.identifier
    }
}
