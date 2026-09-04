//
//  MixerLevelMoveTests.swift
//  ttaccessibleTests
//
//  MixerLevelMove is the one place that says how far a key moves a mixer level:
//  the arrows by one, Page Up/Down by ten, Home/End to the ends. Every volume the
//  mixer's keyboard controller touches goes through it, so its arithmetic and its
//  clamping are worth pinning.
//

import XCTest
@testable import ttaccessible

final class MixerLevelMoveTests: XCTestCase {

    func testArrowMovesByOne() {
        XCTAssertEqual(MixerLevelMove.step(up: true).apply(to: 50), 51)
        XCTAssertEqual(MixerLevelMove.step(up: false).apply(to: 50), 49)
    }

    func testPageMovesByTen() {
        XCTAssertEqual(MixerLevelMove.page(up: true).apply(to: 50), 60)
        XCTAssertEqual(MixerLevelMove.page(up: false).apply(to: 50), 40)
    }

    func testHomeAndEndJumpToTheEnds() {
        XCTAssertEqual(MixerLevelMove.toMax.apply(to: 37), 100)
        XCTAssertEqual(MixerLevelMove.toMin.apply(to: 37), 0)
    }

    func testMovesClampToTheRange() {
        XCTAssertEqual(MixerLevelMove.step(up: true).apply(to: 100), 100)
        XCTAssertEqual(MixerLevelMove.step(up: false).apply(to: 0), 0)
        XCTAssertEqual(MixerLevelMove.page(up: true).apply(to: 95), 100)
        XCTAssertEqual(MixerLevelMove.page(up: false).apply(to: 5), 0)
    }

    func testMixerKeysMapToTheirMoves() {
        XCTAssertEqual(MixerKey.up.levelMove, .step(up: true))
        XCTAssertEqual(MixerKey.down.levelMove, .step(up: false))
        XCTAssertEqual(MixerKey.pageUp.levelMove, .page(up: true))
        XCTAssertEqual(MixerKey.pageDown.levelMove, .page(up: false))
        XCTAssertEqual(MixerKey.home.levelMove, .toMax)
        XCTAssertEqual(MixerKey.end.levelMove, .toMin)
        XCTAssertNil(MixerKey.left.levelMove)
        XCTAssertNil(MixerKey.right.levelMove)
    }

    /// Off a mixer strip, Command-Home and Command-End must reach the ends of the list
    /// under the cursor, not the ends of the master volume. Only the arrows are the
    /// mixer's to claim window-wide.
    func testOnlyTheArrowsAreFreeOfListMeaning() {
        for key in [MixerKey.home, .end, .pageUp, .pageDown] {
            XCTAssertTrue(key.hasListMeaning, "\(key)")
        }
        for key in [MixerKey.up, .down, .left, .right] {
            XCTAssertFalse(key.hasListMeaning, "\(key)")
        }
    }

    func testOnlyHomeAndEndDoNotRepeat() {
        XCTAssertFalse(MixerKey.home.repeats)
        XCTAssertFalse(MixerKey.end.repeats)
        for key in [MixerKey.up, .down, .left, .right, .pageUp, .pageDown] {
            XCTAssertTrue(key.repeats, "\(key)")
        }
    }
}
