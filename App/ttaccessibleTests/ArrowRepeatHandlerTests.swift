//
//  ArrowRepeatHandlerTests.swift
//  ttaccessibleTests
//
//  The mixer's arrow repeat must never run on by itself. A lost keyUp once left the pan
//  timer stepping and announcing "left" forever with the pan pinned hard left. Each tick
//  now checks that the key is still down, and a tick that changes nothing ends the repeat.
//  The timer is not exercised here: `tick` is driven directly.
//

import AppKit
import XCTest
@testable import ttaccessible

@MainActor
final class ArrowRepeatHandlerTests: XCTestCase {

    private var spoken: [String] = []
    private var keyDown = true

    private func makeHandler() -> ArrowRepeatHandler {
        let handler = ArrowRepeatHandler(initialDelay: 60, repeatInterval: 60)
        handler.announce = { [weak self] in self?.spoken.append($0) }
        handler.isKeyDown = { [weak self] _ in self?.keyDown ?? false }
        return handler
    }

    func testTheFirstPressStepsAndSpeaksOnce() {
        let handler = makeHandler()
        var pan = 0
        handler.start(key: .left, keyCode: 123) { pan -= 5; return "left \(-pan)" }
        XCTAssertEqual(pan, -5)
        XCTAssertEqual(spoken, ["left 5"])
        XCTAssertTrue(handler.isRepeating)
    }

    func testATickWithTheKeyUpStopsWithoutStepping() {
        let handler = makeHandler()
        var pan = 0
        let step: () -> String? = { pan -= 5; return "left \(-pan)" }
        handler.start(key: .left, keyCode: 123, step: step)
        keyDown = false                 // the keyUp went to another app
        handler.tick(keyCode: 123, step: step)
        XCTAssertEqual(pan, -5)
        XCTAssertEqual(spoken, ["left 5"])
        XCTAssertFalse(handler.isRepeating)
    }

    func testTheRepeatEndsSilentlyAtTheEndOfTheRange() {
        let handler = makeHandler()
        var pan = -95
        let step: () -> String? = { pan = max(-100, pan - 5); return "left \(-pan)" }
        handler.start(key: .left, keyCode: 123, step: step)
        handler.tick(keyCode: 123, step: step)      // already at -100: nothing changed
        handler.tick(keyCode: 123, step: step)
        XCTAssertEqual(spoken, ["left 100"])
        XCTAssertFalse(handler.isRepeating)
    }

    func testTheHeldKeyStaysClaimedAfterTheEnd() {
        let handler = makeHandler()
        var steps = 0
        let step: () -> String? = { steps += 1; return "left 100" }
        handler.start(key: .left, keyCode: 123, step: step)
        handler.tick(keyCode: 123, step: step)
        // The system's own auto-repeat keyDowns must not start it again.
        handler.start(key: .left, keyCode: 123, step: step)
        XCTAssertEqual(steps, 2)
        handler.stop(key: .left)
        handler.start(key: .left, keyCode: 123, step: step)
        XCTAssertEqual(steps, 3)
    }

    func testTheOppositeArrowTakesOver() {
        let handler = makeHandler()
        var pan = 0
        handler.start(key: .left, keyCode: 123) { pan -= 5; return "pan \(pan)" }
        handler.start(key: .right, keyCode: 124) { pan += 5; return "pan \(pan)" }
        XCTAssertEqual(pan, 0)
        XCTAssertEqual(spoken, ["pan -5", "pan 0"])
    }
}
