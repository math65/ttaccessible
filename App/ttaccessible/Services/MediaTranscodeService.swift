//
//  MediaTranscodeService.swift
//  ttaccessible
//

import Foundation

enum MediaTranscodeError: LocalizedError {
    case ffmpegUnavailable
    case transcodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            return L10n.text("mediaStream.error.ffmpegUnavailable")
        case .transcodeFailed(let detail):
            return L10n.format("mediaStream.error.transcodeFailed", detail)
        }
    }
}

enum MediaTranscodeService {
    private static let ffmpegCandidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    static var isAvailable: Bool {
        resolveFFmpegPath() != nil
    }

    static func transcodeForTeamTalk(sourceURL: URL) throws -> URL {
        guard let ffmpeg = resolveFFmpegPath() else {
            throw MediaTranscodeError.ffmpegUnavailable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ttaccessible-transcode-\(UUID().uuidString).mp4")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y",
            "-i", sourceURL.path,
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            outputURL.path
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .suffix(3)
                .joined(separator: " ") ?? ""
            throw MediaTranscodeError.transcodeFailed(message.isEmpty ? "ffmpeg exit \(process.terminationStatus)" : message)
        }

        return outputURL
    }

    private static func resolveFFmpegPath() -> String? {
        for path in ffmpegCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
