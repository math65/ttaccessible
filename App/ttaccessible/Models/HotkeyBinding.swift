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

struct HotkeyBinding: Codable, Equatable {
    /// Carbon/AppKit virtual key code. `nil` means a pure-modifier chord.
    var keyCode: Int?
    /// Raw value of the device-independent modifier subset.
    var modifiersRawValue: UInt
    /// Human-readable label for the key portion, captured at record time
    /// (e.g. "Space", "A", "F5"). `nil` for a pure-modifier chord.
    var keyLabel: String?

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue).intersection(.deviceIndependentFlagsMask)
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

    /// Builds a binding from a captured key event, or a pure-modifier chord when
    /// `event` carries no usable key (caller decides which path via the event
    /// type). Returns `nil` if the event yields neither.
    static func fromKeyEvent(_ event: NSEvent) -> HotkeyBinding? {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock])
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

    // MARK: - Key labels

    private static let specialKeyLabels: [Int: String] = [
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
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
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
