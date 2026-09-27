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

    func testTheBundledYtDlpLoadsInsideTheApp() async throws {
        let version = await EmbeddedPython.shared.ytdlpVersion()
        XCTAssertNotNil(version, "Python or yt-dlp didn't start inside the app")
        XCTAssertEqual(version, EmbeddedPython.bundledYtDlpVersion)
    }

    func testAYouTubePageResolvesToItsAudio() async throws {
        let media = try await EmbeddedPython.shared.resolve(
            URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!)
        XCTAssertEqual(media.title, "Me at the zoo")
        XCTAssertTrue(media.url.hasPrefix("https://"), media.url)
        XCTAssertEqual(media.extractor, "Youtube")
    }
}
