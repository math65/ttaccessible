//
//  MixerOverlayAccessibilityTests.swift
//  ttaccessibleTests
//
//  The mixer VoiceOver reads is an overlay laid over a hidden SwiftUI rendering. In a
//  channel with nobody else in it the rendering says so, but VoiceOver never sees it:
//  Command-5 read only "Mixer, area". The overlay says it itself.
//

import AppKit
import XCTest
@testable import ttaccessible

@MainActor
final class MixerOverlayAccessibilityTests: XCTestCase {

    func testAnEmptyMixerSaysNobodyElseIsHere() {
        let overlay = A11yVirtualGridOverlayView(frame: .zero)
        overlay.configure(areaLabel: "Mixer", areaRoleDescription: "area", provider: { [] })
        XCTAssertEqual(overlay.accessibilityLabel(), "Mixer, \(L10n.text("mixer.empty"))")
        XCTAssertNil(overlay.accessibilityChildren())
    }
}
