//
//  StreamURLWebPageTests.swift
//  ttaccessibleTests
//
//  Stream URL looks a web page up through yt-dlp before streaming it, but an address that is
//  already a stream must go through untouched, so a web radio starts as fast as it always did.
//  These pin which is which.
//

import XCTest
@testable import ttaccessible

@MainActor
final class StreamURLWebPageTests: XCTestCase {

    private func check(_ address: String) -> Bool {
        AppDelegate.looksLikeWebPage(URL(string: address)!)
    }

    func testVideoPagesAreLookedUp() {
        XCTAssertTrue(check("https://www.youtube.com/watch?v=jNQXAC9IVRw"))
        XCTAssertTrue(check("https://youtu.be/jNQXAC9IVRw"))
        XCTAssertTrue(check("https://soundcloud.com/artist/track"))
    }

    func testAnAddressWithoutAnExtensionIsLookedUp() {
        // Could be a page or a bare stream; yt-dlp tells which, and a stream it doesn't
        // recognise still goes through as typed.
        XCTAssertTrue(check("http://radio.example.com/live"))
    }

    func testAudioFilesAndPlaylistsGoThroughUntouched() {
        XCTAssertFalse(check("https://radio.example.com/stream.mp3"))
        XCTAssertFalse(check("https://example.com/live/index.m3u8"))
        XCTAssertFalse(check("http://example.com/listen.pls"))
        XCTAssertFalse(check("https://example.com/show.OGG"))
    }

    func testOtherStreamingSchemesGoThroughUntouched() {
        XCTAssertFalse(check("rtmp://example.com/live/stream"))
        XCTAssertFalse(check("rtsp://example.com/stream"))
        XCTAssertFalse(check("mms://example.com/stream"))
    }
}
