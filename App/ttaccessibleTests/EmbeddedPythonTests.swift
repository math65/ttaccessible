//
//  EmbeddedPythonTests.swift
//  ttaccessibleTests
//
//  Stream URL plays web pages through yt-dlp, run by a Python embedded in the app. The tests run
//  in the test host — the app itself, sandboxed and hardened — so they prove the runtime starts
//  where it will really run, and reaches a page over HTTPS with its own CA bundle. The resolve
//  test needs the network.
//

import XCTest
@testable import ttaccessible

final class EmbeddedPythonTests: XCTestCase {

    func testYtDlpLoadsInsideTheApp() async throws {
        let version = await EmbeddedPython.shared.ytdlpVersion()
        XCTAssertNotNil(version, "Python or yt-dlp didn't start inside the app")
        // The bundled copy, unless the app has already updated itself on this Mac.
        XCTAssertTrue([EmbeddedPython.bundledYtDlpVersion, YtDlpUpdater.currentVersion()].contains(version))
    }

    func testAYouTubePageResolvesToItsAudio() async throws {
        let media: EmbeddedPython.ResolvedMedia
        do {
            media = try await EmbeddedPython.shared.resolve(
                URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!)
        } catch EmbeddedPython.Failure.unresolved(let message) {
            // Offline, or YouTube changed under this yt-dlp, which is what the updater is
            // for: not a fault of the app. A runtime that won't start still fails.
            throw XCTSkip("YouTube didn't resolve: \(message)")
        }
        XCTAssertEqual(media.title, "Me at the zoo")
        XCTAssertTrue(media.url.hasPrefix("https://"), media.url)
        XCTAssertEqual(media.extractor, "Youtube")
    }
}
