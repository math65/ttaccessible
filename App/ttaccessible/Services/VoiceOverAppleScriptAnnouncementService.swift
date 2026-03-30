//
//  VoiceOverAppleScriptAnnouncementService.swift
//  ttaccessible
//

import Foundation

@MainActor
final class VoiceOverAppleScriptAnnouncementService {
    private let voiceOverApplicationName = "VoiceOver"
    private let logger = AudioDiagnosticsLogger.shared

    func announce(_ message: String) {
        guard message.isEmpty == false else {
            return
        }

        logger.log("voiceover-applescript", "announce requested text=\(message)")

        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source = """
        tell application "\(voiceOverApplicationName)"
            output "\(escaped)"
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            logger.log("voiceover-applescript", "failed to create NSAppleScript instance")
            NSLog("TTAccessible: unable to create VoiceOver AppleScript")
            return
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            logger.log("voiceover-applescript", "AppleScript execution failed: \(errorInfo)")
            NSLog("TTAccessible: VoiceOver AppleScript announcement failed: %@", errorInfo)
        } else {
            logger.log("voiceover-applescript", "AppleScript execution succeeded")
        }
    }
}
