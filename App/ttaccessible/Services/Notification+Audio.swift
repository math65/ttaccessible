//
//  Notification+Audio.swift
//  ttaccessible
//

import Foundation

extension Notification.Name {
    /// Posted before starting transmit capture so Preferences preview releases the mic.
    static let stopAdvancedMicrophonePreview = Notification.Name("com.ttaccessible.stopAdvancedMicrophonePreview")
}
