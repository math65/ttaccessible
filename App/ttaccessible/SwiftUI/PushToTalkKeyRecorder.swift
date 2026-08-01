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
    /// Set when the last press was refused. Shown on the button so the refusal
    /// isn't silent for a sighted user; VoiceOver gets the full explanation as
    /// an announcement.
    @Published private(set) var rejectionTitleKey: String?

    /// The binding this field currently holds. A chord reads as taken when we
    /// are the ones holding it, so re-recording the same one must not be
    /// refused.
    var currentBinding: HotkeyBinding?

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
                // A binding a focused text field would consume can't be honoured
                // there: the menu withholds its shortcut and both hotkey paths
                // stand down while you are writing (HotkeyBinding
                // .typesIntoTextFields). Recording it would produce a shortcut
                // that works everywhere except the chat field — refuse it while
                // the user is still here to pick another key, rather than let
                // them discover the hole mid-conversation.
                guard binding.typesIntoTextFields == false else {
                    reject("preferences.audio.hotkey.rejected.typing",
                           announcement: "preferences.audio.hotkey.rejected.announcement")
                    return true
                }
                // Catches the one collision macOS reports: our OWN other hotkey
                // already carrying this chord, where the second registration is
                // refused and that hotkey silently never runs. A chord another
                // app uses is granted to us — deliberately, that is what a
                // global hotkey is for — so it is not tested here.
                guard HotkeyMonitor.isChordAvailable(binding, current: currentBinding) else {
                    reject("preferences.audio.hotkey.rejected.taken",
                           announcement: "preferences.audio.hotkey.rejected.taken.announcement")
                    return true
                }
                commit(binding)
            }
            return true

        default:
            return false
        }
    }

    /// Stays in recording mode: the user keeps the field and can try another key
    /// straight away, which is what the announcement tells them to do.
    private func reject(_ titleKey: String, announcement: String) {
        rejectionTitleKey = titleKey
        NSAccessibility.post(
            element: NSApp.accessibilityWindow() ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: L10n.text(announcement),
                NSAccessibility.NotificationUserInfoKey.priority:
                    NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
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
        rejectionTitleKey = nil
    }
}

/// Generic accessible hotkey field: presents as a plain button, records the
/// next key press / modifier chord into a HotkeyBinding. Used for both the
/// push-to-talk key and the global mic-toggle binding.
struct HotkeyRecorderButton: View {
    let value: HotkeyBinding?
    /// Localization key for the field's accessibility label.
    let accessibilityLabelKey: String
    /// Shown when no binding is set (e.g. "Not set", or the default chord).
    let emptyValueText: String
    let onCommit: (HotkeyBinding?) -> Void

    @StateObject private var session = KeyCaptureSession()

    var body: some View {
        Button {
            if session.isRecording {
                session.cancel()
            } else {
                // The field's own binding is available by definition — without
                // this, re-recording the same chord reads as taken by us.
                session.currentBinding = value
                session.begin { binding in
                    onCommit(binding)
                }
            }
        } label: {
            Text(buttonTitle)
                .frame(minWidth: 140)
        }
        .accessibilityLabel(L10n.text(accessibilityLabelKey))
        .accessibilityValue(valueText)
        .accessibilityHint(L10n.text("preferences.audio.pushToTalk.key.recordHint"))
        .onDisappear {
            session.cancel()
        }
    }

    private var buttonTitle: String {
        guard session.isRecording else { return valueText }
        if let rejectionTitleKey = session.rejectionTitleKey {
            return L10n.text(rejectionTitleKey)
        }
        return L10n.text("preferences.audio.pushToTalk.key.recording")
    }

    private var valueText: String {
        if let value, value.isValid {
            return value.displayString
        }
        return emptyValueText
    }
}

struct PushToTalkKeyRecorder: View {
    @ObservedObject var store: AudioPreferencesStore

    var body: some View {
        HotkeyRecorderButton(
            value: store.state.pushToTalkKey,
            accessibilityLabelKey: "preferences.audio.pushToTalk.key.label",
            emptyValueText: L10n.text("preferences.audio.pushToTalk.key.notSet")
        ) { binding in
            store.updatePushToTalkKey(binding)
        }
    }
}
