//
//  AccessibleSlider.swift
//  ttaccessible
//

import AppKit

/// NSSlider subclass with accessible keyboard navigation:
/// - Home jumps to the minimum, End jumps to the maximum.
/// - Page Up / Page Down move by `pageStep` (defaults to 10% of the range).
///
/// Arrow keys keep their native NSSlider behavior (single step).
final class AccessibleSlider: NSSlider {
    /// Step applied by Page Up / Page Down. When nil, falls back to
    /// `(maxValue - minValue) / 10`, with a floor of 1.
    var pageStep: Double?

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlain = modifiers.isDisjoint(with: [.command, .option, .control, .shift])

        guard isPlain else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 115: // Home
            setValueAndFire(minValue)
        case 119: // End
            setValueAndFire(maxValue)
        case 116: // Page Up
            setValueAndFire(doubleValue + effectivePageStep)
        case 121: // Page Down
            setValueAndFire(doubleValue - effectivePageStep)
        default:
            super.keyDown(with: event)
        }
    }

    private var effectivePageStep: Double {
        if let pageStep, pageStep > 0 {
            return pageStep
        }
        return max(1, (maxValue - minValue) / 10)
    }

    private func setValueAndFire(_ newValue: Double) {
        let clamped = min(max(newValue, minValue), maxValue)
        guard clamped != doubleValue else { return }
        doubleValue = clamped
        sendAction(action, to: target)
    }
}
