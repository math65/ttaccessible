//
//  AudioDiagnosticsLogger.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import Foundation

final class AudioDiagnosticsLogger {
    static let shared = AudioDiagnosticsLogger()

    #if DEBUG
    private let isEnabled = true
    #else
    private let isEnabled = false
    #endif

    private let queue = DispatchQueue(label: "com.math65.ttaccessible.audio-diagnostics")
    private let fileURL: URL
    private let formatter: ISO8601DateFormatter

    private init() {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = baseURL
            .appendingPathComponent("ttaccessible", isDirectory: true)
            .appendingPathComponent("audio-diagnostics.log", isDirectory: false)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    var logURL: URL {
        fileURL
    }

    func startNewSession() {
        guard isEnabled else {
            return
        }
        queue.sync {
            do {
                try prepareDirectory()
                let header = """
                ===== Session \(formatter.string(from: Date())) =====
                Log: \(fileURL.path)

                """
                if FileManager.default.fileExists(atPath: fileURL.path) == false {
                    try header.write(to: fileURL, atomically: true, encoding: .utf8)
                    return
                }

                let handle = try FileHandle(forWritingTo: self.fileURL)
                defer {
                    try? handle.close()
                }
                try handle.seekToEnd()
                if let data = header.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                NSLog("AudioDiagnosticsLogger startNewSession failed: \(error.localizedDescription)")
            }
        }
    }

    func log(_ scope: String, _ message: String) {
        guard isEnabled else {
            return
        }
        queue.async {
            do {
                try self.prepareDirectory()
                let line = "[\(self.formatter.string(from: Date()))] [\(scope)] \(message)\n"
                if FileManager.default.fileExists(atPath: self.fileURL.path) == false {
                    try line.write(to: self.fileURL, atomically: true, encoding: .utf8)
                    return
                }

                let handle = try FileHandle(forWritingTo: self.fileURL)
                defer {
                    try? handle.close()
                }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                NSLog("AudioDiagnosticsLogger append failed: \(error.localizedDescription)")
            }
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
