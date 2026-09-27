//
//  Notification+Audio.swift
//  ttaccessible
//

import Foundation

extension Notification.Name {
    /// Posted before starting transmit capture so Preferences preview releases the mic.
    static let stopAdvancedMicrophonePreview = Notification.Name("com.ttaccessible.stopAdvancedMicrophonePreview")
    /// Posted after the live microphone engine stops (mute, leaving a channel, a device
    /// restart), so a running Preferences preview can open its own capture instead.
    static let liveMicrophoneInputStopped = Notification.Name("com.ttaccessible.liveMicrophoneInputStopped")
}
