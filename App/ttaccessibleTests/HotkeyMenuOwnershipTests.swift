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

    func testF13IsNamedAndHasAMenuKeyEquivalent() {
        // F13–F19 are the one safe global binding (they type nothing), so they
        // have to be nameable in the recorder and usable as a menu shortcut.
        XCTAssertEqual(KeyCodeResolver.label(forKeyCode: 105), "F13")
        let binding = HotkeyBinding(keyCode: 105, modifiers: [], keyLabel: "F13")
        XCTAssertEqual(binding.menuKeyEquivalent?.characters,
                       String(UnicodeScalar(UInt32(NSF13FunctionKey))!))
    }

    func testShiftedChordDeclaresTheCharacterThePressActuallyTypes() throws {
        // AppKit compares a key equivalent against `charactersIgnoringModifiers`,
        // which keeps Shift applied. Declaring the UNSHIFTED character left the
        // item carrying "&" for a chord that types "1" — the menu shortcut was
        // shown and never fired.
        //
        // Layout-agnostic: find any key whose shifted character differs from its
        // unshifted one (the digit row, on every layout) and assert we declare
        // the shifted form. Case is excluded — that half stays in the mask.
        let keyCode = try XCTUnwrap((0..<128).first { code in
            guard let plain = KeyCodeResolver.character(forKeyCode: code, shifted: false),
                  let shifted = KeyCodeResolver.character(forKeyCode: code, shifted: true) else {
                return false
            }
            return plain.lowercased() != shifted.lowercased()
        }, "no key on this layout types a different character with Shift")

        let shifted = try XCTUnwrap(KeyCodeResolver.character(forKeyCode: keyCode, shifted: true))
        let binding = HotkeyBinding(keyCode: keyCode, modifiers: [.command, .shift], keyLabel: nil)
        XCTAssertEqual(binding.menuKeyEquivalent?.characters, shifted.lowercased())
    }

    func testUnnameableKeyHasNoMenuKeyEquivalent() {
        // A key no table names and no layout types must degrade to "the tap
        // handles it", not to a bogus menu title.
        let binding = HotkeyBinding(keyCode: 200, modifiers: [.command], keyLabel: nil)
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

    // MARK: - Bindings that type must not steal the keystroke

    private func binding(_ keyCode: Int, _ mods: NSEvent.ModifierFlags, _ label: String) -> HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifiers: mods, keyLabel: label)
    }

    func testBarePrintableKeyIsRecognisedAsTyping() {
        // keyCode 46 is M on ANSI. Bound bare, it has to keep typing into the
        // chat field instead of toggling the mic mid-sentence.
        XCTAssertTrue(binding(46, [], "M").typesIntoTextFields)
    }

    func testShiftAloneDoesNotProtectABinding() {
        // ⇧M still types "M" — shift is part of the character, not an escape
        // from the keyboard.
        XCTAssertTrue(binding(46, [.shift], "M").typesIntoTextFields)
    }

    func testCommandControlOrOptionMakeABindingNonTyping() {
        // Each of the three on its own puts the chord out of reach of typing.
        XCTAssertFalse(binding(46, [.command], "M").typesIntoTextFields)
        XCTAssertFalse(binding(46, [.control], "M").typesIntoTextFields)
        XCTAssertFalse(binding(46, [.option], "M").typesIntoTextFields)
    }

    func testBareSpaceIsTyping() {
        // Space is the example the model's own header offers, and it is the one
        // most likely to be bound bare.
        XCTAssertTrue(binding(49, [], "Space").typesIntoTextFields)
    }

    func testBareFunctionKeysAreNotTyping() {
        // F13–F20 type nothing and carry no system function — staying bindable
        // bare is the entire reason commit 3 named them.
        XCTAssertFalse(binding(105, [], "F13").typesIntoTextFields)
        XCTAssertFalse(binding(96, [], "F5").typesIntoTextFields)
    }

    func testReturnAndEnterAreTyping() {
        // Return in the chat field sends the message; bound bare it was toggling
        // the mic instead. It types nothing, so the printable rule alone missed
        // it — the field still consumes it.
        XCTAssertTrue(binding(36, [], "Return").typesIntoTextFields)
        XCTAssertTrue(binding(76, [], "Enter").typesIntoTextFields)
    }

    func testTabAndDeleteAreTyping() {
        // The recorder only reserves these when pressed with NO modifier, so the
        // ⇧ variants are bindable and would otherwise steal focus movement and
        // backspace out of a focused field.
        XCTAssertTrue(binding(48, [.shift], "Tab").typesIntoTextFields)
        XCTAssertTrue(binding(51, [.shift], "Delete").typesIntoTextFields)
        XCTAssertTrue(binding(117, [], "Fwd Delete").typesIntoTextFields)
    }

    func testCaretMovementKeysAreTyping() {
        // Arrows and the Home/End/Page family move the caret — a field in use
        // needs them as much as it needs letters.
        for keyCode in [123, 124, 125, 126, 115, 119, 116, 121] {
            XCTAssertTrue(binding(keyCode, [], "key").typesIntoTextFields,
                          "keyCode \(keyCode) must yield to a focused field")
        }
    }

    func testEditingKeysWithACommandChordAreNotTyping() {
        // ⌘Return / ⌥↑ are out of reach of ordinary editing, so they stay
        // available as bindings and keep their menu shortcut.
        XCTAssertFalse(binding(36, [.command], "Return").typesIntoTextFields)
        XCTAssertFalse(binding(126, [.option], "\u{2191}").typesIntoTextFields)
        XCTAssertNotNil(binding(36, [.command], "Return").safeMenuKeyEquivalent)
    }

    func testModifierOnlyChordIsNotTyping() {
        XCTAssertFalse(HotkeyBinding(keyCode: nil, modifiers: [.command, .control], keyLabel: nil)
            .typesIntoTextFields)
    }

    func testTypingBindingIsWithheldFromTheMenu() {
        // The menu half: no key equivalent is installed at all, so AppKit never
        // answers the key ahead of the focused field.
        XCTAssertNil(binding(46, [], "M").safeMenuKeyEquivalent)
        XCTAssertNil(binding(49, [], "Space").safeMenuKeyEquivalent)
    }

    func testNonTypingBindingStillReachesTheMenu() {
        // Withholding must not cost the safe bindings their menu shortcut —
        // that shortcut is what makes one chord work while the app is focused.
        //
        // The key code comes from the layout rather than a constant: codes are
        // positional, so 46 types "m" on ANSI but "," on AZERTY, and hardcoding
        // it fails the test on a French keyboard for a reason that has nothing
        // to do with what is under test.
        let m = KeyCodeResolver.keyCode(for: "m") ?? 46
        XCTAssertEqual(binding(m, [.command, .option], "M").safeMenuKeyEquivalent?.characters, "m")
        XCTAssertEqual(binding(105, [], "F13").safeMenuKeyEquivalent?.characters,
                       String(UnicodeScalar(UInt32(NSF13FunctionKey))!))
    }

    func testWithheldBindingIsAlsoNotOwnedByTheMenu() {
        // The two halves have to agree in this direction too: since nothing is
        // installed, the ownership check must report the chord as unowned, which
        // is what routes it to the tap — where the focused-field guard then
        // declines it. Both withhold; neither acts while typing.
        let typing = binding(46, [], "M")
        XCTAssertNil(typing.safeMenuKeyEquivalent)
        let menu = NSMenu()
        menu.addItem(withTitle: "Microphone", action: nil, keyEquivalent: "")
        XCTAssertFalse(HotkeyMonitor.menu(menu, carries: "m", modifiers: []))
    }

    func testPrintabilityCoversTheCharacterHalfOfTheRule() {
        // `typesIntoTextFields` is the one predicate the menu, the tap and the
        // local monitor all consult; this is the character half of it. The keys
        // that type nothing but a field still uses are covered by key code above.
        XCTAssertTrue(HotkeyBinding.isPrintable(UnicodeScalar("m")))
        XCTAssertTrue(HotkeyBinding.isPrintable(UnicodeScalar(" ")))
        XCTAssertFalse(HotkeyBinding.isPrintable(UnicodeScalar(UInt32(NSF13FunctionKey))!))
        XCTAssertFalse(HotkeyBinding.isPrintable(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!))
        XCTAssertFalse(HotkeyBinding.isPrintable(UnicodeScalar(0x7F)))
    }

    func testComparableModifiersDropsHardwareOnlyFlags() {
        // An F-key press carries .function and a keypad key .numericPad, neither
        // of which a menu declares — left in, nothing would ever match.
        let raw: NSEvent.ModifierFlags = [.command, .shift, .function, .capsLock, .numericPad]
        XCTAssertEqual(HotkeyMonitor.comparableModifiers(raw), [.command, .shift])
    }
}
