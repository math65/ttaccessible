//
//  VoiceOverAppleScriptAnnouncementService.swift
//  ttaccessible
//

import Foundation

@MainActor
final class VoiceOverAppleScriptAnnouncementService {
    private let voiceOverApplicationName = "VoiceOver"

    func announce(_ message: String) {
        guard message.isEmpty == false else {
            return
        }

        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source = """
        tell application "\(voiceOverApplicationName)"
            output "\(escaped)"
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            NSLog("TTAccessible: unable to create VoiceOver AppleScript")
            return
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("TTAccessible: VoiceOver AppleScript announcement failed: %@", errorInfo)
        }
    }
}
