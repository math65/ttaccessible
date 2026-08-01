//
//  HotkeyBinding.swift
//  ttaccessible
//
//  A user-configurable hotkey used for push-to-talk. Unlike the KeyboardShortcuts
//  library this replaces, a binding can be:
//    • a regular key, optionally with modifiers (e.g. Space, ⌥Space, F5)
//    • a pure-modifier chord with no key (e.g. ⌘⌃ held down)
//  The pure-modifier case is impossible to express as a keyDown event, so it is
//  detected from `flagsChanged` by HotkeyMonitor instead.
//

import AppKit
import Carbon.HIToolbox

struct HotkeyBinding: Codable, Equatable {
    /// Carbon/AppKit virtual key code. `nil` means a pure-modifier chord.
    var keyCode: Int?
    /// Raw value of the device-independent modifier subset.
    var modifiersRawValue: UInt
    /// Human-readable label for the key portion, captured at record time
    /// (e.g. "Space", "A", "F5"). `nil` for a pure-modifier chord.
    var keyLabel: String?

    /// The chord's matchable modifiers. `.numericPad`/`.function`/`.capsLock`
    /// are stripped here (not just at record time, so stored bindings are
    /// covered too): arrow/keypad keys carry `.numericPad` in NSEvents but the
    /// CGEventTap flag conversion never produces it — leaving it in would make
    /// such a key match locally yet never match globally.
    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
    }

    /// A chord with no key code — matched via modifier state rather than keyDown.
    var isModifierOnly: Bool { keyCode == nil }

    var isValid: Bool {
        if keyCode != nil { return true }
        return !modifiers.isEmpty
    }

    init(keyCode: Int?, modifiers: NSEvent.ModifierFlags, keyLabel: String?) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
        self.keyLabel = keyLabel
    }

    /// The default global mic-toggle chord: ⌘⇧ + the key that TYPES "a" on
    /// the current layout (key codes are positional — a hardcoded 0 is Q on
    /// AZERTY).
    static func defaultMuteHotkey() -> HotkeyBinding {
        let keyCode = KeyCodeResolver.keyCode(for: "a") ?? 0
        return HotkeyBinding(
            keyCode: keyCode,
            modifiers: [.command, .shift],
            keyLabel: KeyCodeResolver.label(forKeyCode: keyCode)
        )
    }

    /// Builds a binding from a captured key event, or a pure-modifier chord when
    /// `event` carries no usable key (caller decides which path via the event
    /// type). Returns `nil` if the event yields neither.
    static func fromKeyEvent(_ event: NSEvent) -> HotkeyBinding? {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock, .numericPad])
        let label = Self.keyLabel(for: event)
        return HotkeyBinding(keyCode: Int(event.keyCode), modifiers: mods, keyLabel: label)
    }

    /// The ⌃⌥⇧⌘ prefix in the canonical macOS display order.
    private var modifierSymbols: String {
        var result = ""
        if modifiers.contains(.control) { result += "\u{2303}" }  // ⌃
        if modifiers.contains(.option) { result += "\u{2325}" }   // ⌥
        if modifiers.contains(.shift) { result += "\u{21E7}" }    // ⇧
        if modifiers.contains(.command) { result += "\u{2318}" }  // ⌘
        return result
    }

    /// Human-readable rendering, e.g. "⌥Space", "F5", or "⌘⌃".
    var displayString: String {
        let symbols = modifierSymbols
        guard let keyLabel, keyLabel.isEmpty == false else {
            return symbols
        }
        return symbols + keyLabel
    }

    // MARK: - Menu key equivalents

    /// Virtual key codes AppKit expresses as a function-key unicode scalar
    /// rather than a typed character. Anything a layout can type is resolved
    /// through `KeyCodeResolver` instead, so this covers only the keys that
    /// type nothing.
    private static let menuFunctionKeyScalars: [Int: Int] = [
        122: NSF1FunctionKey, 120: NSF2FunctionKey, 99: NSF3FunctionKey,
        118: NSF4FunctionKey, 96: NSF5FunctionKey, 97: NSF6FunctionKey,
        98: NSF7FunctionKey, 100: NSF8FunctionKey, 101: NSF9FunctionKey,
        109: NSF10FunctionKey, 103: NSF11FunctionKey, 111: NSF12FunctionKey,
        105: NSF13FunctionKey, 107: NSF14FunctionKey, 113: NSF15FunctionKey,
        106: NSF16FunctionKey, 64: NSF17FunctionKey, 79: NSF18FunctionKey,
        80: NSF19FunctionKey, 90: NSF20FunctionKey,
        123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey,
        125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey,
        115: NSHomeFunctionKey, 119: NSEndFunctionKey,
        116: NSPageUpFunctionKey, 121: NSPageDownFunctionKey,
        117: NSDeleteFunctionKey
    ]

    /// Keys AppKit matches by a plain control character.
    private static let menuControlCharacters: [Int: String] = [
        49: " ",         // Space
        48: "\t",        // Tab
        36: "\r",        // Return
        76: "\u{3}",     // Enter
        53: "\u{1B}",    // Esc
        51: "\u{8}"      // Delete
    ]

    /// What a main-menu item must carry to answer this binding, or nil when the
    /// chord cannot be a menu key equivalent — a pure-modifier chord types
    /// nothing for AppKit to match, and an exotic key that neither the layout
    /// nor the tables above can name has no representation either. Callers fall
    /// back to the global tap in that case, which matches by key code and needs
    /// no character at all.
    var menuKeyEquivalent: (characters: String, modifiers: NSEvent.ModifierFlags)? {
        guard let keyCode else { return nil }
        return rawMenuKeyEquivalent(for: keyCode)
    }

    /// What may safely be installed on a main-menu item for this binding, or nil
    /// when the item must carry no shortcut at all. A binding that types into a
    /// focused field is withheld from the menu: an item carrying a bare
    /// `keyEquivalent` answers it before the field sees it, so the mic would
    /// toggle mid-sentence. The tap declines the same bindings while a field is
    /// focused (`HotkeyMonitor.handleTapEvent`) — both halves have to withhold or
    /// the problem just moves from one to the other.
    var safeMenuKeyEquivalent: (characters: String, modifiers: NSEvent.ModifierFlags)? {
        typesIntoTextFields ? nil : menuKeyEquivalent
    }

    /// Key codes a focused text field consumes even though they insert no
    /// visible character: Return and Enter insert a newline or send, Tab moves
    /// focus, Delete edits, and the arrows / Home / End / Page keys move the
    /// caret. "Would the field use this key" is the real question — "is it
    /// printable" only answers part of it.
    ///
    /// F1–F20 are deliberately absent. They do nothing in a text field, which is
    /// exactly what makes them the one family safe to bind bare.
    private static let textEditingKeyCodes: Set<Int> = [
        36,   // Return
        76,   // Enter
        48,   // Tab
        51,   // Delete
        117,  // Forward Delete
        123, 124, 125, 126,  // ← → ↓ ↑
        115, 119,            // Home, End
        116, 121             // Page Up, Page Down
    ]

    /// True when pressing this binding with a text field focused would type into
    /// it or move around inside it. ⇧ is not protective — ⇧K still types "K", and
    /// ⇧Tab still moves focus; only ⌘, ⌃ or ⌥ put a chord out of reach of
    /// ordinary editing.
    var typesIntoTextFields: Bool {
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        guard let keyCode else { return false }  // a pure-modifier chord types nothing
        if Self.textEditingKeyCodes.contains(keyCode) { return true }
        guard let scalar = menuKeyEquivalent?.characters.unicodeScalars.first else { return false }
        return Self.isPrintable(scalar)
    }

    /// Whether a scalar would insert a visible character if left alone. Function
    /// and navigation keys map into the F700–F8FF private-use range and type
    /// nothing; the navigation half of that range is caught by
    /// `textEditingKeyCodes` above instead.
    static func isPrintable(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 0x20 && scalar.value != 0x7F
            && (scalar.value < 0xF700 || scalar.value > 0xF8FF)
    }

    private func rawMenuKeyEquivalent(
        for keyCode: Int
    ) -> (characters: String, modifiers: NSEvent.ModifierFlags)? {
        if let scalarValue = Self.menuFunctionKeyScalars[keyCode],
           let scalar = UnicodeScalar(UInt32(scalarValue)) {
            return (String(Character(scalar)), modifiers)
        }
        if let control = Self.menuControlCharacters[keyCode] {
            return (control, modifiers)
        }
        // AppKit matches a key equivalent against `charactersIgnoringModifiers`,
        // which applies Shift — so a ⌘⇧ chord on the key that types "&" has to be
        // declared as "1", the character the press actually produces. Taking the
        // unshifted character left the item carrying "&", which no press ever
        // matched: the shortcut showed in the menu and never fired (the tap
        // answered it instead), and the recorder displayed a different chord than
        // the menu did.
        //
        // Case is the exception the mask still owns: equivalents are declared in
        // lower case, so ⌘⇧A stays "a" rather than needing ⇧ declared twice.
        // An untypable key yields nil, and the tap — which matches by key code —
        // handles it instead.
        guard let typed = KeyCodeResolver.character(
            forKeyCode: keyCode,
            shifted: modifiers.contains(.shift)
        )?.lowercased(), typed.count == 1 else { return nil }
        return (typed, modifiers)
    }

    // MARK: - Key labels

    static let specialKeyLabels: [Int: String] = [
        49: "Space",
        48: "Tab",
        36: "Return",
        76: "Enter",
        53: "Esc",
        51: "Delete",
        117: "Fwd Delete",
        123: "\u{2190}",   // ←
        124: "\u{2192}",   // →
        125: "\u{2193}",   // ↓
        126: "\u{2191}",   // ↑
        115: "Home",
        119: "End",
        116: "Page Up",
        121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        // F13–F20 type nothing and carry no system function, which makes them
        // the one genuinely safe global binding — they were showing as
        // "Key 105" because the table stopped at F12.
        105: "F13", 107: "F14", 113: "F15", 106: "F16",
        64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    private static func keyLabel(for event: NSEvent) -> String {
        let keyCode = Int(event.keyCode)
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let chars = event.charactersIgnoringModifiers, chars.isEmpty == false {
            let scalar = chars.unicodeScalars.first!
            // Printable characters render uppercased; control chars fall through.
            if scalar.value >= 0x20, scalar.value != 0x7F {
                return chars.uppercased()
            }
        }
        return "Key \(keyCode)"
    }
}

/// Layout-aware virtual-key-code lookups (Carbon UCKeyTranslate). Key codes
/// are positional: hardcoding "A = keyCode 0" is ANSI-only — on AZERTY that
/// physical key types Q, so a chord built from a character must resolve the
/// code through the CURRENT keyboard layout.
enum KeyCodeResolver {
    /// The virtual key code whose unmodified press types `character` on the
    /// current layout, or nil when the layout has no such key.
    static func keyCode(for character: Character) -> Int? {
        guard let layoutData = currentLayoutData() else { return nil }
        let target = String(character).lowercased()
        for code in 0..<128 where translate(keyCode: code, layoutData: layoutData)?.lowercased() == target {
            return code
        }
        return nil
    }

    /// A display label for `keyCode` under the current layout (special keys
    /// first, then the typed character, then a raw fallback).
    static func label(forKeyCode keyCode: Int) -> String {
        if let special = HotkeyBinding.specialKeyLabels[keyCode] {
            return special
        }
        if let translated = character(forKeyCode: keyCode, shifted: false) {
            return translated.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// The visible character `keyCode` types under the current layout, with Shift
    /// applied or not, or nil when it types nothing. Shift matters: the same
    /// physical key types "&" alone and "1" with Shift on AZERTY, and a menu key
    /// equivalent has to be declared as the shifted form to ever match.
    static func character(forKeyCode keyCode: Int, shifted: Bool) -> String? {
        guard let layoutData = currentLayoutData(),
              let translated = translate(keyCode: keyCode,
                                         layoutData: layoutData,
                                         shifted: shifted),
              translated.isEmpty == false,
              let scalar = translated.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F else { return nil }
        return translated
    }

    private static func currentLayoutData() -> Data? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return unsafeBitCast(layoutDataRef, to: CFData.self) as Data
    }

    private static func translate(keyCode: Int, layoutData: Data, shifted: Bool = false) -> String? {
        // UCKeyTranslate wants the Carbon modifier bits shifted down a byte.
        let modifierState = shifted ? UInt32(shiftKey >> 8) : 0
        return layoutData.withUnsafeBytes { rawBuffer -> String? in
            guard let layoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
