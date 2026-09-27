//
//  AudioRoutingSnapshot.swift
//  ttaccessible
//

import Foundation

/// Captures the audio routing state that matters for live TeamTalk sessions.
/// Used to ignore benign CoreAudio device-list churn (e.g. Continuity devices)
/// while still reacting to real route changes (AirPods, unplugged hardware, defaults).
struct AudioRoutingSnapshot: Equatable {
    var resolvedInputUID: String?
    var defaultInputUID: String?
    var defaultOutputUID: String?
    var preferredOutputPersistentID: String?
    /// Whether the chosen output device is plugged in, read from CoreAudio every time.
    /// True for the system default and for no output, which have no device to miss.
    var chosenOutputPresent: Bool
    var activeInputSampleRate: Double
    /// CoreAudio object ID of the resolved input device. A device keeps its UID when
    /// it is unplugged and replugged or when coreaudiod restarts, but comes back under
    /// a new object ID, and the stream opened on the old one is dead.
    var inputDeviceObjectID: UInt32?
    /// The device the output render engine binds to (the preference, or the system
    /// default when the preferred device is missing), by UID and object ID. Nil when
    /// the preference is no output.
    var outputEngineDeviceUID: String?
    var outputEngineDeviceObjectID: UInt32?
}
