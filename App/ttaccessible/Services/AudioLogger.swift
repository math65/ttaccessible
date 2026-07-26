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
        // The default profile keeps the historical `audio.log` filename. Other
        // profiles get `audio-<slug>.log` so two instances don't overwrite
        // each other's log on launch (and so the feedback bug-report attaches
        // the right one).
        let profile = ProfileContext.current
        let fileName = profile.isDefault ? "audio.log" : "audio-\(profile.slug).log"
        return dir.appendingPathComponent(fileName)
    }()

    private static let queue = DispatchQueue(label: "com.ttaccessible.audiologger")

    /// Hard cap on the log file size. A user who never quits the app could otherwise
    /// accumulate the periodic diagnostics indefinitely. When the file would exceed
    /// this, it's truncated (recent entries are the useful ones for bug reports).
    private static let maxLogBytes = 5 * 1024 * 1024
    /// Bytes written since the last clear/truncate. Touched only on `queue`.
    private static var bytesWritten = 0

    /// Location of the diagnostics log (attached to feedback bug reports).
    static var fileURL: URL {
        logURL
    }

    static func log(_ message: String) {
        // Capture timestamp as raw values on the calling thread (no DateFormatter,
        // which is not thread-safe). Format the string on the serial queue.
        let date = Date()
        queue.async {
            let ts = Self.timestamp(date)
            let line = "[\(ts)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            // Size guard: truncate before the file would exceed the cap, so a
            // days-long session can't fill the disk. Keeps only recent entries.
            if Self.bytesWritten + data.count > Self.maxLogBytes {
                let marker = Data("[… log truncated at \(Self.maxLogBytes / (1024 * 1024)) MB …]\n".utf8)
                try? marker.write(to: logURL, options: .atomic)
                Self.bytesWritten = marker.count
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
                Self.bytesWritten += data.count
            } else {
                try? data.write(to: logURL, options: .atomic)
                Self.bytesWritten = data.count
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
            Self.bytesWritten = 0
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
