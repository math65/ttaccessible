//
//  PressActionTextFieldTests.swift
//  ttaccessibleTests
//
//  The channel tree sets each row's tooltip to its full accessibility label, so a
//  truncated row can be read with the mouse. VoiceOver reads a tooltip as help, so
//  every row was spoken twice — a long channel topic most noticeably. Tree rows now
//  keep the tooltip for the eye and drop it for VoiceOver; everything else that uses
//  the field keeps the default.
//

import XCTest
@testable import ttaccessible

@MainActor
final class PressActionTextFieldTests: XCTestCase {

    private let rowText = "The lazy Lounge (3/3), current channel, Topic: come in and relax"

    /// Proves the override sits on the path VoiceOver uses: by default the tooltip
    /// really does come back as help. If this ever fails, the fix below is inert.
    func testATooltipIsSpokenAsHelpByDefault() {
        let field = PressActionTextField(labelWithString: "Lounge")
        field.toolTip = rowText
        XCTAssertEqual(field.accessibilityHelp(), rowText)
    }

    func testATreeRowIsNotSpokenTwice() {
        let field = PressActionTextField(labelWithString: "Lounge")
        field.toolTip = rowText
        field.speaksToolTipAsHelp = false
        field.setAccessibilityLabel(rowText)
        XCTAssertNil(field.accessibilityHelp())
        XCTAssertEqual(field.accessibilityLabel(), rowText)
    }

    func testTheMouseKeepsItsTooltip() {
        let field = PressActionTextField(labelWithString: "Lounge")
        field.toolTip = rowText
        field.speaksToolTipAsHelp = false
        XCTAssertEqual(field.toolTip, rowText)
    }

    // A channel with a topic shows it on a second line, so the text on screen is not the
    // label. VoiceOver read both: "Lounge (3/3), current channel", the topic, then the
    // whole label again. Measured on the live tree: every topic row differed, every user
    // row (text identical to label) did not, and only the topic rows were read twice.

    private let shownText = "The lazy Lounge (3/3), current channel\ncome in and relax"

    /// Proves the override sits on the path VoiceOver uses: by default the value is the
    /// text on screen, which is what differed from the label.
    func testTheValueIsTheShownTextByDefault() {
        let field = PressActionTextField(labelWithString: shownText)
        field.setAccessibilityLabel(rowText)
        XCTAssertEqual(field.accessibilityValue(), shownText)
    }

    func testATopicRowReadsItsLabelOnce() {
        let field = PressActionTextField(labelWithString: shownText)
        field.readsLabelAsValue = true
        field.setAccessibilityLabel(rowText)
        XCTAssertEqual(field.accessibilityValue(), rowText)
        XCTAssertEqual(field.accessibilityLabel(), rowText)
    }

    func testTheScreenKeepsBothLines() {
        let field = PressActionTextField(labelWithString: shownText)
        field.readsLabelAsValue = true
        field.setAccessibilityLabel(rowText)
        XCTAssertEqual(field.stringValue, shownText)
    }

    // Matching the value was not enough: VoiceOver also fetches the text by character
    // range, which still gave the two shown lines, so topic rows were read twice still.
    // Measured on the live tree: AXStringForRange differed from the label on every topic
    // row and on no other row.

    /// What VoiceOver gets when it asks for the text by range. The element it talks to
    /// is the field's cell, through the attribute API, so ask exactly that.
    private func rangeText(of field: PressActionTextField, _ range: NSRange) -> String? {
        let cell = field.cell as NSObject?
        return cell?.accessibilityAttributeValue(.stringForRange, forParameter: NSValue(range: range)) as? String
    }

    private func characterCount(of field: PressActionTextField) -> Int? {
        (field.cell as NSObject?)?.accessibilityAttributeValue(.numberOfCharacters) as? Int
    }

    /// Proves the override sits on the path VoiceOver uses: by default the range text is
    /// the text on screen.
    func testTheRangeTextIsTheShownTextByDefault() {
        let field = PressActionTextField(labelWithString: shownText)
        field.setAccessibilityLabel(rowText)
        XCTAssertEqual(rangeText(of: field, NSRange(location: 0, length: (shownText as NSString).length)), shownText)
    }

    func testATopicRowsRangeTextIsItsLabel() {
        let field = PressActionTextField(labelWithString: shownText)
        field.readsLabelAsValue = true
        field.setAccessibilityLabel(rowText)
        let length = (rowText as NSString).length
        XCTAssertEqual(characterCount(of: field), length)
        XCTAssertEqual(rangeText(of: field, NSRange(location: 0, length: length)), rowText)
    }

    func testARangePastTheEndIsClipped() {
        let field = PressActionTextField(labelWithString: shownText)
        field.readsLabelAsValue = true
        field.setAccessibilityLabel(rowText)
        XCTAssertEqual(rangeText(of: field, NSRange(location: 4, length: 10_000)),
                       (rowText as NSString).substring(from: 4))
    }
}
