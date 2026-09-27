//
//  KeyCommandHandlerTests.swift
//  ttaccessibleTests
//
//  KeyCommandHandler tells the mixer's v/p/m/s single tap (announce) from its double tap
//  (reset, center, toggle). A double tap must run ONLY its own action: when the single
//  tap fired on the first press, every double tap read the old value before the new one.
//  A short window keeps these fast; the logic doesn't depend on its length.
//

import XCTest
@testable import ttaccessible

@MainActor
final class KeyCommandHandlerTests: XCTestCase {

    private let window: TimeInterval = 0.1
    private var singles: [String] = []
    private var doubles: [String] = []

    override func setUp() {
        super.setUp()
        singles = []
        doubles = []
    }

    private func press(_ handler: KeyCommandHandler, _ key: String) {
        handler.handle(key: key,
                       onSingle: { [unowned self] in singles.append(key) },
                       onDouble: { [unowned self] in doubles.append(key) })
    }

    /// Lets the main queue run past the double-tap window, so any deferred single fires.
    private func waitOutWindow() {
        let done = expectation(description: "window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + window * 3) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func testDoubleTapRunsOnlyTheDouble() {
        let handler = KeyCommandHandler(doubleTapInterval: window)
        press(handler, "v")
        press(handler, "v")
        waitOutWindow()
        XCTAssertEqual(doubles, ["v"])
        XCTAssertEqual(singles, [], "the single's announcement must not precede the double's")
    }

    func testSingleTapWaitsOutTheWindow() {
        let handler = KeyCommandHandler(doubleTapInterval: window)
        press(handler, "m")
        XCTAssertEqual(singles, [], "a single tap can't speak before it knows no second tap follows")
        waitOutWindow()
        XCTAssertEqual(singles, ["m"])
        XCTAssertEqual(doubles, [])
    }

    func testDifferentKeysDontPairUp() {
        let handler = KeyCommandHandler(doubleTapInterval: window)
        press(handler, "v")
        press(handler, "p")
        waitOutWindow()
        XCTAssertEqual(singles.sorted(), ["p", "v"])
        XCTAssertEqual(doubles, [])
    }

    func testThirdPressStartsAFreshSingle() {
        let handler = KeyCommandHandler(doubleTapInterval: window)
        press(handler, "s")
        press(handler, "s")
        press(handler, "s")
        waitOutWindow()
        XCTAssertEqual(doubles, ["s"])
        XCTAssertEqual(singles, ["s"])
    }
}
