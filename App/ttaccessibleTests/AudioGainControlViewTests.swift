//
//  AudioGainControlViewTests.swift
//  ttaccessibleTests
//
//  The window's global level sliders — output, input, sound effects, media — move
//  through the same MixerLevelMove table the mixer's own keys use, so a level travels
//  the same distance whichever route reaches it. Before that, this view's keyDown had
//  Home going to 0 % and End to 100 %, the opposite of the mixer, and nothing caught it.
//

import XCTest
@testable import ttaccessible

@MainActor
final class AudioGainControlViewTests: XCTestCase {

    private func makeControl() -> AudioGainControlView {
        AudioGainControlView(title: "Output", accessibilityLabel: "Output") { _ in }
    }

    private func key(_ functionKey: Int) -> NSEvent {
        let character = String(Character(UnicodeScalar(UInt32(functionKey))!))
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function],
                                timestamp: 0, windowNumber: 0, context: nil,
                                characters: character, charactersIgnoringModifiers: character,
                                isARepeat: false, keyCode: 0)!
    }

    /// The readout in the test host's language: "50%", "50 %" in French.
    private func percent(_ value: Int) -> String {
        L10n.format("mixer.value.percent", value)
    }

    func testHomeGoesToTheTopAndEndToTheBottom() {
        // The keys themselves, through the same table the mixer reads.
        XCTAssertEqual(AudioGainControlView.levelMove(for: key(NSHomeFunctionKey)), .toMax)
        XCTAssertEqual(AudioGainControlView.levelMove(for: key(NSEndFunctionKey)), .toMin)
        XCTAssertEqual(AudioGainControlView.levelMove(for: key(NSLeftArrowFunctionKey)), .step(up: false))
        XCTAssertEqual(AudioGainControlView.levelMove(for: key(NSRightArrowFunctionKey)), .step(up: true))
        XCTAssertEqual(AudioGainControlView.levelMove(for: key(NSPageUpFunctionKey)), .page(up: true))
        let control = makeControl()
        XCTAssertEqual(control.apply(.toMax), percent(100))
        XCTAssertEqual(control.apply(.toMin), percent(0))
    }

    func testArrowMovesOnePercentAndPageMovesTen() {
        let control = makeControl()
        control.setValue(0)                       // unity == 50 %
        XCTAssertEqual(control.apply(.step(up: true)), percent(51))
        XCTAssertEqual(control.apply(.step(up: false)), percent(50))
        XCTAssertEqual(control.apply(.page(up: true)), percent(60))
        XCTAssertEqual(control.apply(.page(up: false)), percent(50))
    }

    func testMovesClampAtTheEnds() {
        let control = makeControl()
        control.apply(.toMax)
        XCTAssertEqual(control.apply(.step(up: true)), percent(100))
        control.apply(.toMin)
        XCTAssertEqual(control.apply(.step(up: false)), percent(0))
    }

    func testTheChangeHandlerSeesEveryMove() {
        var seen: [Double] = []
        let control = AudioGainControlView(title: "Output", accessibilityLabel: "Output") { seen.append($0) }
        control.apply(.toMax)
        control.apply(.toMin)
        XCTAssertEqual(seen, [24, -24])           // the ends of the -24…+24 dB scale
    }

    /// Tab stops once on a level, on the view VoiceOver reads by name — not first on the
    /// slider inside it, which VoiceOver read as "50%, slider" with no name.
    func testTabStopsOnceOnEachLevel() {
        let first = makeControl()
        let second = makeControl()
        let stack = NSStackView(views: [first, second])
        stack.orientation = .vertical
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = stack
        window.recalculateKeyViewLoop()

        XCTAssertFalse(first.slider.acceptsFirstResponder)
        XCTAssertTrue(first.acceptsFirstResponder)

        window.makeFirstResponder(first)
        window.selectNextKeyView(nil)
        XCTAssertTrue(window.firstResponder === second,
                      "Tab from one level went to \(String(describing: window.firstResponder)), not the next level")
    }
}
