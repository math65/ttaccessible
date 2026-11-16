//
//  StreamURLWebPageTests.swift
//  ttaccessibleTests
//
//  Stream URL looks a web page up through yt-dlp before streaming it, but an address that is
//  already a stream by its extension or scheme goes through untouched, as fast as it always
//  did. An address with no extension is looked up; when yt-dlp only hands it back, it is a
//  plain stream and keeps its old name. These pin which is which.
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

    private func media(extractor: String, url: String, title: String = "mp3-128") -> EmbeddedPython.ResolvedMedia {
        let json = #"{"title":"\#(title)","url":"\#(url)","protocol":"http","headers":{},"is_live":true,"extractor":"\#(extractor)","duration":null}"#
        return try! JSONDecoder().decode(EmbeddedPython.ResolvedMedia.self, from: Data(json.utf8))
    }

    func testARadioYtDlpOnlyHandsBackIsAPlainStream() {
        let typed = URL(string: "https://stream.radioparadise.com/mp3-128")!
        XCTAssertTrue(AppDelegate.isPlainStream(media(extractor: "Generic", url: typed.absoluteString), typed: typed))
    }

    func testAPageWithMediaBehindItIsNotAPlainStream() {
        let page = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
        XCTAssertFalse(AppDelegate.isPlainStream(
            media(extractor: "Youtube", url: "https://rr1.googlevideo.com/videoplayback?x=1", title: "Me at the zoo"), typed: page))
        // Generic, but it found a different link on the page: that one is the media.
        let other = URL(string: "https://example.com/player")!
        XCTAssertFalse(AppDelegate.isPlainStream(media(extractor: "Generic", url: "https://cdn.example.com/a.mp3"), typed: other))
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
