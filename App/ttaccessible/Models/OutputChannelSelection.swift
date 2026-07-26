//
//  OutputChannelSelection.swift
//  ttaccessible
//
//  Which physical channels of the selected output device the mix is played to.
//  The symmetric counterpart of InputChannelPreset: on an interface with more
//  than two outputs (a 32-channel mixer, an aggregate rig) TeamTalk audio does
//  not have to land on outputs 1/2 — it can be sent to 5/6, or to a single
//  mono feed on output 11.
//
//  Stored per output-device UID (AppPreferences.outputChannelSelections), like
//  the per-device microphone profiles, so each interface keeps its own routing.
//

import Foundation

enum OutputChannelSelection: Codable, Hashable {
    /// The device's first stereo pair (or its single channel on a mono device) —
    /// the behavior that shipped before this setting existed.
    case auto
    /// Sum the mix to mono and play it on one physical channel (1-based).
    case mono(channel: Int)
    /// Play left/right on two physical channels (1-based).
    case stereoPair(first: Int, second: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case first
        case second
    }

    private enum Kind: String, Codable {
        case auto
        case mono
        case stereoPair
    }

    var identifier: String {
        switch self {
        case .auto:
            return "auto"
        case .mono(let channel):
            return "mono:\(channel)"
        case .stereoPair(let first, let second):
            return "stereo:\(first):\(second)"
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
        }
    }

    /// Zero-based plane indices for the render callback. `right == nil` means the
    /// mix is summed to mono onto `left`. Clamped to the device's channel count;
    /// a selection that no longer fits (device swapped for a smaller one) falls
    /// back to the first pair rather than playing nothing.
    func planeIndices(deviceChannels: Int) -> (left: Int, right: Int?) {
        guard deviceChannels > 0 else { return (0, nil) }
        switch self {
        case .auto:
            return deviceChannels >= 2 ? (0, 1) : (0, nil)
        case .mono(let channel):
            let index = channel - 1
            guard (0..<deviceChannels).contains(index) else {
                return deviceChannels >= 2 ? (0, 1) : (0, nil)
            }
            return (index, nil)
        case .stereoPair(let first, let second):
            let leftIndex = first - 1
            let rightIndex = second - 1
            guard (0..<deviceChannels).contains(leftIndex),
                  (0..<deviceChannels).contains(rightIndex) else {
                return deviceChannels >= 2 ? (0, 1) : (0, nil)
            }
            return (leftIndex, rightIndex)
        }
    }
}

struct OutputChannelSelectionOption: Identifiable, Equatable {
    let selection: OutputChannelSelection
    let title: String

    var id: String {
        selection.identifier
    }
}
