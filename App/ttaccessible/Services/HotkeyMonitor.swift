//
//  HotkeyMonitor.swift
//  ttaccessible
//
//  Watches for a HotkeyBinding and reports press/release. Replaces the
//  KeyboardShortcuts library for push-to-talk so we can support single keys,
//  key+modifier combos, AND pure-modifier chords (⌘⌃), each either app-focused
//  or global.
//
//  Global scope uses a CGEventTap (.cgSessionEventTap). With the Accessibility
//  privilege granted the tap is CONSUMING (.defaultTap): a matched hotkey is
//  swallowed system-wide, so it never double-fires in the frontmost app
//  (Accessibility is grantable now that the app is not sandboxed — the App
//  Sandbox used to block it, which forced a listen-only tap that could detect
//  but not swallow). Until the user grants Accessibility, the tap falls back
//  to listen-only via Input Monitoring: the hotkey works but still reaches
//  the frontmost app. Pure-modifier chords are never consumed — suppressing
//  flagsChanged would corrupt modifier state everywhere. (Carbon
//  RegisterEventHotKey was tried and rejected — it doesn't swallow either,
//  and can't do bare keys / modifier-only chords.)
//
//  App-focused (local) scope uses an NSEvent local monitor (no permission), and
//  CAN swallow the matched key — local monitors consume events destined for our
//  own app, so the key won't type into a field while focused.
//

import AppKit
import CoreGraphics

/// Whether the app currently has (or can request) the Input Monitoring privilege
/// needed for a global CGEventTap. Sandbox-safe.
enum InputMonitoringPermission {
    static var isGranted: Bool { CGPreflightListenEventAccess() }

    /// Prompts once (macOS shows the Input Monitoring pane). Returns the current
    /// grant state; the prompt result is asynchronous, so a `false` here just
    /// means "not yet — reconfigure after the user grants it".
    @discardableResult
    static func request() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        return CGRequestListenEventAccess()
    }
}

final class HotkeyMonitor {
    enum Scope {
        case local   // app-focused only
        case global  // system-wide
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var binding: HotkeyBinding?
    private var scope: Scope = .local
    /// When true, the global tap ignores events while the app is frontmost — used
    /// for the mute chord, whose focused case is handled by the menu shortcut.
    private var globalOnlyWhenInactive = false
    private var wantsReleaseEvents = true

    private var localMonitor: Any?
    private var resignActiveObserver: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    /// Whether the installed global tap is consuming (.defaultTap under
    /// Accessibility) rather than listen-only.
    private(set) var installedConsuming = false
    /// Whether we consumed the matching keyDown — its keyUp must then be
    /// consumed too (and passed through when the down was passed through).
    private var consumedDown = false

    /// Set when the global tap couldn't be created because Input Monitoring is
    /// not yet granted — the caller reconfigures after a grant.
    private(set) var isAwaitingGlobalPermission = false

    /// True when a listen-only global tap could be upgraded to a consuming one
    /// (the user granted Accessibility after it was installed) — the caller
    /// reconfigures to pick the grant up.
    var canUpgradeToConsuming: Bool {
        scope == .global && eventTap != nil && installedConsuming == false && AXIsProcessTrusted()
    }

    func configure(
        binding: HotkeyBinding?,
        scope: Scope,
        globalOnlyWhenInactive: Bool = false,
        wantsReleaseEvents: Bool = true
    ) {
        stop()
        self.binding = binding
        self.scope = scope
        self.globalOnlyWhenInactive = globalOnlyWhenInactive
        self.wantsReleaseEvents = wantsReleaseEvents

        guard let binding, binding.isValid else { return }
        switch scope {
        case .local:
            installLocalMonitor(binding)
        case .global:
            installEventTap(binding)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            // tapEnable(false) + dropping the reference doesn't release the
            // mach port's receive right — invalidate explicitly so repeated
            // reconfigure cycles don't leak ports.
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        isAwaitingGlobalPermission = false
        installedConsuming = false
        consumedDown = false
        if isPressed {
            isPressed = false
            onRelease?()
        }
    }

    // MARK: - Global via consuming CGEventTap

    private func installEventTap(_ binding: HotkeyBinding) {
        AudioLogger.log("[Hotkey] installEventTap binding=%@ modifierOnly=%d preflight=%d",
                        binding.displayString, binding.isModifierOnly ? 1 : 0,
                        CGPreflightListenEventAccess() ? 1 : 0)
        guard InputMonitoringPermission.request() else {
            AudioLogger.log("[Hotkey] Input Monitoring not granted — global pending for %@", binding.displayString)
            isAwaitingGlobalPermission = true
            return
        }

        let mask: CGEventMask = binding.isModifierOnly
            ? (1 << CGEventType.flagsChanged.rawValue)
            : (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            let consumed = monitor.handleTapEvent(type: type, event: event)
            // Returning nil swallows the event (no-op on a listen-only tap).
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        // Consuming tap when Accessibility is granted (swallows the hotkey
        // system-wide); listen-only via Input Monitoring otherwise — detected,
        // but the frontmost app still receives the keystroke.
        let canConsume = AXIsProcessTrusted()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: canConsume ? .defaultTap : .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AudioLogger.log("[Hotkey] CGEvent.tapCreate FAILED for %@ — global pending", binding.displayString)
            isAwaitingGlobalPermission = true
            return
        }

        installedConsuming = canConsume
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AudioLogger.log("[Hotkey] global tap ACTIVE for %@ (%@)",
                        binding.displayString, canConsume ? "consuming" : "listen-only")
    }

    /// Returns true when the event should be CONSUMED (matched key on a
    /// consuming tap — swallowed system-wide so it can't double-fire in the
    /// frontmost app). Pure-modifier chords are never consumed.
    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        guard let binding else { return false }
        // The inactive-only guard (mute chord: the in-app menu shortcut owns
        // the focused case) suppresses PRESSES only. Releases always run —
        // if the app becomes active between down and up, eating the keyUp
        // would leave isPressed stuck and silently swallow the next toggle.
        let suppressPress = globalOnlyWhenInactive && NSApp.isActive

        let mods = Self.modifierFlags(from: event.flags)
        if binding.isModifierOnly {
            let chordActive = mods == binding.modifiers
            if chordActive, suppressPress { return false }
            setPressed(chordActive)
            return false
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard keyCode == binding.keyCode, mods == binding.modifiers, suppressPress == false else { return false }
            if autorepeat == false { setPressed(true) }
            consumedDown = installedConsuming
            return installedConsuming  // swallow repeats of the held hotkey too
        case .keyUp:
            guard keyCode == binding.keyCode else { return false }
            setPressed(false)
            // Mirror the down: a consumed press must not leak a stray keyUp,
            // a passed-through press keeps its keyUp.
            let consume = consumedDown
            consumedDown = false
            return consume
        default:
            return false
        }
    }

    // MARK: - Local (app-focused) via NSEvent

    private func installLocalMonitor(_ binding: HotkeyBinding) {
        let mask: NSEvent.EventTypeMask = binding.isModifierOnly ? [.flagsChanged] : [.keyDown, .keyUp]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            // Swallow a matched key locally too, so it doesn't type into a field.
            return self.handleNSEvent(event) ? nil : event
        }
        // A local monitor can't see the keyUp once the app deactivates
        // (Cmd-Tab mid-hold) — the release would be lost and the mic would
        // keep transmitting. Treat losing active status as a release.
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setPressed(false)
        }
        AudioLogger.log("[Hotkey] app-focused monitor active for %@", binding.displayString)
    }

    /// Returns `true` if the event was a match that should be swallowed.
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        guard let binding else { return false }
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .capsLock, .numericPad])
        if binding.isModifierOnly {
            updateChord(active: mods, target: binding.modifiers)
            return false
        }
        switch event.type {
        case .keyDown:
            guard Int(event.keyCode) == binding.keyCode, mods == binding.modifiers else { return false }
            // A bare printable key (no modifiers) must keep typing into a
            // focused text field — the field wins over push-to-talk there.
            if binding.modifiers.isEmpty, Self.isPrintable(event), Self.isTextInputFocused() {
                return false
            }
            if event.isARepeat == false { setPressed(true) }
            return true
        case .keyUp:
            // Only swallow the keyUp of a press WE matched — an unmatched
            // down (typed into a field, different modifiers) keeps its up.
            guard Int(event.keyCode) == binding.keyCode, isPressed else { return false }
            setPressed(false)
            return true
        default:
            return false
        }
    }

    /// Whether the event would insert a visible character if left alone
    /// (excludes function/navigation keys, which map into the F700 range).
    private static func isPrintable(_ event: NSEvent) -> Bool {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value != 0x7F
            && (scalar.value < 0xF700 || scalar.value > 0xF8FF)
    }

    private static func isTextInputFocused() -> Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    // MARK: - Shared

    private func updateChord(active: NSEvent.ModifierFlags, target: NSEvent.ModifierFlags) {
        setPressed(active == target)
    }

    private func setPressed(_ pressed: Bool) {
        if pressed {
            guard isPressed == false else { return }
            isPressed = true
            AudioLogger.log("[Hotkey] press %@", binding?.displayString ?? "?")
            onPress?()
        } else {
            guard isPressed else { return }
            isPressed = false
            if wantsReleaseEvents {
                AudioLogger.log("[Hotkey] release %@", binding?.displayString ?? "?")
                onRelease?()
            }
        }
    }

    static func modifierFlags(from cg: CGEventFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if cg.contains(.maskCommand) { flags.insert(.command) }
        if cg.contains(.maskControl) { flags.insert(.control) }
        if cg.contains(.maskAlternate) { flags.insert(.option) }
        if cg.contains(.maskShift) { flags.insert(.shift) }
        return flags
    }
}
