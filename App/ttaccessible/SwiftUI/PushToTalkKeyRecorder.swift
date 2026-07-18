//
//  PushToTalkKeyRecorder.swift
//  ttaccessible
//
//  An accessible push-to-talk key field. Captures the next key press into a
//  HotkeyBinding — a single key, a key+modifier combo, or a pure-modifier chord
//  (e.g. ⌘⌃ pressed and released on its own). Presents as a plain button, so
//  VoiceOver announces "button" rather than the "search field" the old
//  KeyboardShortcuts recorder produced.
//

import AppKit
import Combine
import SwiftUI

/// Captures one key press / modifier chord while active. Uses a local event
/// monitor, which is all that's needed since recording only happens while the
/// Settings window is focused (no Input Monitoring permission required).
final class KeyCaptureSession: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var peakModifiers: NSEvent.ModifierFlags = []
    private var onCommit: ((HotkeyBinding?) -> Void)?

    // Carbon virtual key codes handled specially during capture.
    private let escapeKeyCode = 53
    private let tabKeyCode = 48
    private let deleteKeyCode = 51
    private let forwardDeleteKeyCode = 117

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func begin(onCommit: @escaping (HotkeyBinding?) -> Void) {
        guard isRecording == false else { return }
        self.onCommit = onCommit
        peakModifiers = []
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancel() {
        finish()
    }

    /// A modifier-only chord that is just VoiceOver's activation modifiers
    /// (Control and/or Option, the default VO modifier). When VoiceOver is on,
    /// pressing VO-Space to activate the recorder leaks these — so we ignore them
    /// as a pure-modifier hotkey rather than committing them. Real chords include
    /// Command or Shift (e.g. ⌘⌃), so they still record. This never blocks a
    /// useful binding: Control/Option-only chords conflict with VoiceOver anyway.
    private func isVoiceOverActivationNoise(_ mods: NSEvent.ModifierFlags) -> Bool {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return false }
        return mods.isSubset(of: [.control, .option])
    }

    /// Returns `true` when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock])

        switch event.type {
        case .flagsChanged:
            if mods.isEmpty {
                // All modifiers released with no regular key pressed. Commit the
                // peak chord (e.g. ⌘⌃) unless it's just VoiceOver's activation
                // modifiers leaking in.
                let peak = peakModifiers
                peakModifiers = []
                if peak.isEmpty == false, isVoiceOverActivationNoise(peak) == false {
                    commit(HotkeyBinding(keyCode: nil, modifiers: peak, keyLabel: nil))
                }
            } else {
                peakModifiers.formUnion(mods)
            }
            return true

        case .keyDown:
            let keyCode = Int(event.keyCode)
            if keyCode == escapeKeyCode, mods.isEmpty {
                cancel()
                return true
            }
            if keyCode == tabKeyCode, mods.isEmpty {
                cancel()
                return false  // let focus move to the next control
            }
            if (keyCode == deleteKeyCode || keyCode == forwardDeleteKeyCode), mods.isEmpty {
                commit(nil)  // clear the binding
                return true
            }
            if let binding = HotkeyBinding.fromKeyEvent(event) {
                commit(binding)
            }
            return true

        default:
            return false
        }
    }

    private func commit(_ binding: HotkeyBinding?) {
        onCommit?(binding)
        finish()
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        peakModifiers = []
        onCommit = nil
        isRecording = false
    }
}

struct PushToTalkKeyRecorder: View {
    @ObservedObject var store: AudioPreferencesStore
    @StateObject private var session = KeyCaptureSession()

    var body: some View {
        Button {
            if session.isRecording {
                session.cancel()
            } else {
                session.begin { binding in
                    store.updatePushToTalkKey(binding)
                }
            }
        } label: {
            Text(buttonTitle)
                .frame(minWidth: 140)
        }
        .accessibilityLabel(L10n.text("preferences.audio.pushToTalk.key.label"))
        .accessibilityValue(valueText)
        .accessibilityHint(L10n.text("preferences.audio.pushToTalk.key.recordHint"))
        .onDisappear {
            session.cancel()
        }
    }

    private var buttonTitle: String {
        session.isRecording ? L10n.text("preferences.audio.pushToTalk.key.recording") : valueText
    }

    private var valueText: String {
        if let key = store.state.pushToTalkKey, key.isValid {
            return key.displayString
        }
        return L10n.text("preferences.audio.pushToTalk.key.notSet")
    }
}
