//
//  EmbeddedPython.swift
//  ttaccessible
//
//  Swift's side of the embedded Python runtime (see PythonShim): finds it inside the app,
//  starts it on first use on a queue of its own, and asks yt-dlp — running in-process, inside
//  the app — to turn a web page into something the media streamer can open. Nothing here
//  launches a program or needs anything installed on the Mac.
//

import Foundation

nonisolated final class EmbeddedPython: @unchecked Sendable {

    static let shared = EmbeddedPython()

    /// What yt-dlp found behind a page: the link the streamer opens, and the name to show.
    struct ResolvedMedia: Decodable, Equatable, Sendable {
        let title: String
        let url: String
        let streamProtocol: String
        let headers: [String: String]
        let isLive: Bool
        let extractor: String
        let duration: Double?

        enum CodingKeys: String, CodingKey {
            case title, url, headers, extractor, duration
            case streamProtocol = "protocol"
            case isLive = "is_live"
        }
    }

    enum Failure: Error, Equatable {
        /// The runtime isn't in this build, or wouldn't start (Python's own message).
        case unavailable(String)
        /// yt-dlp found nothing it could play on the page (yt-dlp's own message).
        case unresolved(String)
    }

    /// Startup and every call run here: starting loads the standard library, which takes a
    /// moment, and must never hold up the main thread.
    private let queue = DispatchQueue(label: "com.ttaccessible.embedded-python", qos: .userInitiated)
    /// Guarded by `queue`.
    private var started = false

    /// The standard library's prefix, inside the embedded framework.
    static var pythonHome: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("Python.framework/Versions/Current")
    }

    /// yt-dlp, its version file and the CA bundle, copied in from Vendor/Python/PythonSupport.
    static var supportDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("PythonSupport")
    }

    /// The yt-dlp the app shipped with.
    static var bundledYtDlp: URL? {
        supportDirectory?.appendingPathComponent("yt-dlp.zip")
    }

    static var bundledYtDlpVersion: String? {
        guard let file = supportDirectory?.appendingPathComponent("yt-dlp.version"),
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves a web page — YouTube, or any site yt-dlp knows — to its media.
    func resolve(_ page: URL, timeoutSeconds: Int = 20) async throws -> ResolvedMedia {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.startIfNeeded()
                    var error: UnsafeMutablePointer<CChar>?
                    guard let json = ttac_py_resolve(page.absoluteString, Int32(timeoutSeconds), &error) else {
                        throw Failure.unresolved(Self.take(error) ?? "yt-dlp found nothing to play")
                    }
                    let text = String(cString: json)
                    ttac_py_free(json)
                    let media = try JSONDecoder().decode(ResolvedMedia.self, from: Data(text.utf8))
                    continuation.resume(returning: media)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The version of the yt-dlp in use, starting Python if needed; nil if it can't start.
    func ytdlpVersion() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            queue.async {
                guard (try? self.startIfNeeded()) != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.take(ttac_py_ytdlp_version()))
            }
        }
    }

    /// Runs on `queue`.
    private func startIfNeeded() throws {
        guard started == false else { return }
        guard let home = Self.pythonHome,
              let support = Self.supportDirectory,
              let ytdlp = Self.bundledYtDlp,
              FileManager.default.fileExists(atPath: home.path),
              FileManager.default.fileExists(atPath: ytdlp.path) else {
            throw Failure.unavailable("the Python runtime is not part of this build")
        }
        let caFile = support.appendingPathComponent("cacert.pem")
        var error: UnsafeMutablePointer<CChar>?
        guard ttac_py_start(home.path, caFile.path, ytdlp.path, &error) == 0 else {
            let message = Self.take(error) ?? "Python failed to start"
            AudioLogger.log("embedded python: failed to start — %@", message)
            throw Failure.unavailable(message)
        }
        started = true
        AudioLogger.log("embedded python: started, yt-dlp %@", Self.take(ttac_py_ytdlp_version()) ?? "?")
    }

    /// A C string from the shim as a Swift String, freeing it.
    private static func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { ttac_py_free(pointer) }
        return String(cString: pointer)
    }
}
