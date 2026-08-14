//
//  RecentMediaStreamURLTests.swift
//  ttaccessibleTests
//
//  The recent stream URLs offered back by the URL prompt: ordering, de-duping
//  and the cap. Pure list logic — the prompt itself stays verified by hand.
//

import XCTest
@testable import ttaccessible

final class RecentMediaStreamURLTests: XCTestCase {

    func testKeepsOrderAndDropsBlanks() {
        let urls = AppPreferences.clampRecentMediaStreamURLs([
            "https://a.example/stream",
            "   ",
            "https://b.example/stream",
            "",
        ])
        XCTAssertEqual(urls, ["https://a.example/stream", "https://b.example/stream"])
    }

    func testTrimsSurroundingWhitespace() {
        let urls = AppPreferences.clampRecentMediaStreamURLs(["  https://a.example/stream  "])
        XCTAssertEqual(urls, ["https://a.example/stream"])
    }

    func testDropsDuplicatesKeepingTheFirstOccurrence() {
        let urls = AppPreferences.clampRecentMediaStreamURLs([
            "https://a.example/stream",
            "https://b.example/stream",
            "https://a.example/stream",
        ])
        XCTAssertEqual(urls, ["https://a.example/stream", "https://b.example/stream"])
    }

    func testDuplicateComparisonIgnoresCase() {
        let urls = AppPreferences.clampRecentMediaStreamURLs([
            "https://A.Example/stream",
            "https://a.example/stream",
        ])
        XCTAssertEqual(urls, ["https://A.Example/stream"], "the first spelling is the one kept")
    }

    func testCapsTheList() {
        let many = (1...(AppPreferences.maxRecentMediaStreamURLs + 5)).map { "https://\($0).example/stream" }
        let urls = AppPreferences.clampRecentMediaStreamURLs(many)
        XCTAssertEqual(urls.count, AppPreferences.maxRecentMediaStreamURLs)
        XCTAssertEqual(urls.first, "https://1.example/stream")
    }

    /// What `rememberMediaStreamURL` does: prepend, then clamp. Re-using an
    /// address has to move it back to the top, not leave it where it was.
    func testRememberingAnExistingURLMovesItToTheTop() {
        let existing = ["https://a.example/stream", "https://b.example/stream"]
        let urls = AppPreferences.clampRecentMediaStreamURLs(["https://b.example/stream"] + existing)
        XCTAssertEqual(urls, ["https://b.example/stream", "https://a.example/stream"])
    }

    func testDecodingPreferencesWithoutTheKeyYieldsAnEmptyList() throws {
        let json = Data(#"{"defaultNickname":"tester"}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: json)
        XCTAssertTrue(preferences.mediaStreamRecentURLs.isEmpty)
    }

    func testDecodingSanitizesAStoredList() throws {
        let json = Data(#"""
        {"mediaStreamRecentURLs":["https://a.example/s","https://a.example/s","  "]}
        """#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: json)
        XCTAssertEqual(preferences.mediaStreamRecentURLs, ["https://a.example/s"])
    }
}
