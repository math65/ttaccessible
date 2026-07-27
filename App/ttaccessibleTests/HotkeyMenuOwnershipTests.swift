//
//  HotkeyMenuOwnershipTests.swift
//  ttaccessibleTests
//
//  The global mute tap defers to the main menu only for a chord the menu
//  actually carries. Getting that predicate wrong is invisible in a build and
//  fails in opposite directions — too eager and a rebound hotkey does nothing
//  while the app is focused, too lax and a binding that collides with an in-app
//  shortcut fires both actions at once.
//
//  Menu construction only; no window, no run loop.
//

import XCTest
import AppKit
@testable import ttaccessible

final class HotkeyMenuOwnershipTests: XCTestCase {

    /// Mirrors the real shape: shortcuts live on items inside submenus.
    private func makeMenu() -> NSMenu {
        let root = NSMenu()

        let userItem = NSMenuItem()
        let userMenu = NSMenu(title: "User")
        userMenu.addItem(withTitle: "Microphone", action: nil, keyEquivalent: "a")
            .keyEquivalentModifierMask = [.command, .shift]
        userMenu.addItem(withTitle: "Master mute", action: nil, keyEquivalent: "m")
            .keyEquivalentModifierMask = [.command]
        userItem.submenu = userMenu
        root.addItem(userItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Mixer", action: nil,
                           keyEquivalent: String(UnicodeScalar(UInt32(NSF5FunctionKey))!))
            .keyEquivalentModifierMask = []
        windowMenu.addItem(withTitle: "No shortcut", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        root.addItem(windowItem)

        return root
    }

    func testDefaultMuteChordIsOwnedByTheMenu() {
        // ⌘⇧A must keep going to the menu item — the tap acting on it too would
        // toggle the mic twice.
        XCTAssertTrue(HotkeyMonitor.menu(makeMenu(), carries: "a", modifiers: [.command, .shift]))
    }

    func testRe_boundChordIsNotOwnedByTheMenu() {
        // ⌥⌘M matches nothing, so the tap is the only handler and must act.
        XCTAssertFalse(HotkeyMonitor.menu(makeMenu(), carries: "m", modifiers: [.command, .option]))
    }

    func testSameKeyDifferentModifiersIsNotOwned() {
        XCTAssertFalse(HotkeyMonitor.menu(makeMenu(), carries: "a", modifiers: [.command]))
    }

    func testCollidingChordInAnotherSubmenuIsOwned() {
        // ⌘M already opens/closes a window — a mute binding on it must defer,
        // not fire both actions.
        XCTAssertTrue(HotkeyMonitor.menu(makeMenu(), carries: "m", modifiers: [.command]))
    }

    func testFunctionKeyEquivalentIsMatched() {
        // F13–F19 are the recommended global bindings, so F-keys must compare
        // by the same rule as letters rather than silently never matching.
        let f5 = String(UnicodeScalar(UInt32(NSF5FunctionKey))!)
        XCTAssertTrue(HotkeyMonitor.menu(makeMenu(), carries: f5, modifiers: []))
    }

    func testUnboundKeyIsNotOwned() {
        XCTAssertFalse(HotkeyMonitor.menu(makeMenu(), carries: "z", modifiers: [.command, .control]))
    }

    // MARK: - Binding -> menu key equivalent

    func testLetterBindingBecomesALowercaseKeyEquivalent() {
        // The shift in ⌘⇧A belongs in the modifier mask, not in the character —
        // an uppercase "A" would need ⇧ declared twice and match nothing.
        let binding = HotkeyBinding.defaultMuteHotkey()
        let equivalent = binding.menuKeyEquivalent
        XCTAssertEqual(equivalent?.characters, "a")
        XCTAssertEqual(equivalent?.modifiers, [.command, .shift])
    }

    func testFunctionKeyBindingBecomesItsUnicodeScalar() {
        // keyCode 96 is F5; AppKit expects the scalar, not the string "F5".
        let binding = HotkeyBinding(keyCode: 96, modifiers: [], keyLabel: "F5")
        XCTAssertEqual(binding.menuKeyEquivalent?.characters,
                       String(UnicodeScalar(UInt32(NSF5FunctionKey))!))
    }

    func testModifierOnlyChordHasNoMenuKeyEquivalent() {
        // Nothing is typed, so no menu item can carry it — the tap owns it in
        // every focus state instead.
        let binding = HotkeyBinding(keyCode: nil, modifiers: [.command, .control], keyLabel: nil)
        XCTAssertNil(binding.menuKeyEquivalent)
    }

    func testUnnameableKeyHasNoMenuKeyEquivalent() {
        // keyCode 105 is F13, which the label tables don't name and no layout
        // types — it must degrade to "the tap handles it", not to a bogus title.
        let binding = HotkeyBinding(keyCode: 105, modifiers: [.command], keyLabel: nil)
        XCTAssertNil(binding.menuKeyEquivalent)
    }

    func testSpaceBindingBecomesASpaceCharacter() {
        let binding = HotkeyBinding(keyCode: 49, modifiers: [.option], keyLabel: "Space")
        XCTAssertEqual(binding.menuKeyEquivalent?.characters, " ")
        XCTAssertEqual(binding.menuKeyEquivalent?.modifiers, [.option])
    }

    func testMenuEquivalentRoundTripsThroughTheOwnershipCheck() {
        // The two halves have to agree: whatever we put on the item must be what
        // the tap then recognises as menu-owned, or the chord fires twice.
        let binding = HotkeyBinding(keyCode: 46, modifiers: [.command, .option], keyLabel: "M")
        guard let equivalent = binding.menuKeyEquivalent else {
            return XCTFail("⌥⌘M must have a menu key equivalent")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Microphone", action: nil, keyEquivalent: equivalent.characters)
            .keyEquivalentModifierMask = equivalent.modifiers
        XCTAssertTrue(HotkeyMonitor.menu(menu,
                                         carries: equivalent.characters.lowercased(),
                                         modifiers: equivalent.modifiers))
    }

    func testComparableModifiersDropsHardwareOnlyFlags() {
        // An F-key press carries .function and a keypad key .numericPad, neither
        // of which a menu declares — left in, nothing would ever match.
        let raw: NSEvent.ModifierFlags = [.command, .shift, .function, .capsLock, .numericPad]
        XCTAssertEqual(HotkeyMonitor.comparableModifiers(raw), [.command, .shift])
    }
}
