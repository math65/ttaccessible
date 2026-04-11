//
//  AudioLogger.swift
//  ttaccessible
//

import Foundation

enum AudioLogger {
    private static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TTAccessible", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("audio.log")
    }()

    private static let queue = DispatchQueue(label: "com.ttaccessible.audiologger")

    static func log(_ message: String) {
        // Capture timestamp as raw values on the calling thread (no DateFormatter,
        // which is not thread-safe). Format the string on the serial queue.
        let date = Date()
        queue.async {
            let ts = Self.timestamp(date)
            let line = "[\(ts)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: logURL, options: .atomic)
                }
            }
        }
    }

    static func log(_ format: String, _ args: CVarArg...) {
        let message = String(format: format, arguments: args)
        log(message)
    }

    /// Clear the log file (call at app launch).
    static func clear() {
        queue.async {
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    // Thread-safe timestamp without DateFormatter.
    private static func timestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let ms = (c.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }
}
