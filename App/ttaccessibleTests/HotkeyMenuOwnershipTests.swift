//
//  HotkeyMenuOwnershipTests.swift
//  ttaccessibleTests
//
//  What the mic-toggle binding declares to the main menu, and which keys a
//  focused text field would swallow. Both are invisible in a build and fail
//  quietly: a menu item can display a shortcut it never answers, and a binding
//  that types can toggle the mic mid-sentence.
//
//  The ownership predicate the tap used to consult (HotkeyMonitor.menu) is
//  gone with the tap's key-code path — a Carbon hotkey is served before the
//  menu, so the double-fire it guarded against can no longer happen.
//
//  Menu construction only; no window, no run loop.
//

import XCTest
import AppKit
@testable import ttaccessible

final class HotkeyMenuOwnershipTests: XCTestCase {








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

    func testPrintabilityCoversTheCharacterHalfOfTheRule() {
        // `typesIntoTextFields` is the one predicate the menu, the recorder and
        // the local monitor all consult; this is the character half of it. The keys
        // that type nothing but a field still uses are covered by key code above.
        XCTAssertTrue(HotkeyBinding.isPrintable(UnicodeScalar("m")))
        XCTAssertTrue(HotkeyBinding.isPrintable(UnicodeScalar(" ")))
        XCTAssertFalse(HotkeyBinding.isPrintable(UnicodeScalar(UInt32(NSF13FunctionKey))!))
        XCTAssertFalse(HotkeyBinding.isPrintable(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!))
        XCTAssertFalse(HotkeyBinding.isPrintable(UnicodeScalar(0x7F)))
    }

}
