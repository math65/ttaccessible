//
//  HotkeyMonitor.swift
//  ttaccessible
//
//  Watches for a HotkeyBinding and reports press/release. Replaces the
//  KeyboardShortcuts library for push-to-talk so we can support single keys,
//  key+modifier combos, AND pure-modifier chords (⌘⌃), each either app-focused
//  or global.
//
//  Global scope uses a listen-only CGEventTap (.cgSessionEventTap, .listenOnly)
//  gated by Input Monitoring — available to sandboxed / App Store apps. It
//  DETECTS the hotkey system-wide but cannot SWALLOW it: a consuming (.defaultTap)
//  tap needs Accessibility, which the App Sandbox blocks. So a global hotkey is
//  seen by the app AND still reaches the frontmost app. (Carbon RegisterEventHotKey
//  was tried and rejected — it doesn't swallow either, and can't do bare keys /
//  modifier-only chords.) True global swallowing would require un-sandboxing.
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
    /// When true, the global tap defers to the main menu while the app is
    /// frontmost — but only for a chord the menu actually carries. A menu key
    /// equivalent is delivered to the focused app whatever the (listen-only) tap
    /// does, so acting on it here too would double-fire; a chord no menu item
    /// owns has no other handler, so the tap stays the one that answers it.
    private var deferToMainMenuWhenActive = false
    private var wantsReleaseEvents = true

    private var localMonitor: Any?
    private var resignActiveObserver: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    /// Set when the global tap couldn't be created because Input Monitoring is
    /// not yet granted — the caller reconfigures after a grant.
    private(set) var isAwaitingGlobalPermission = false

    func configure(
        binding: HotkeyBinding?,
        scope: Scope,
        deferToMainMenuWhenActive: Bool = false,
        wantsReleaseEvents: Bool = true
    ) {
        stop()
        self.binding = binding
        self.scope = scope
        self.deferToMainMenuWhenActive = deferToMainMenuWhenActive
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
            monitor.handleTapEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)  // observe; can't consume while sandboxed
        }

        // Listen-only: a consuming (.defaultTap) tap needs Accessibility, which
        // the App Sandbox blocks. Input Monitoring only grants observation, so a
        // global hotkey is detected but still reaches the frontmost app.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            AudioLogger.log("[Hotkey] CGEvent.tapCreate FAILED for %@ — global pending", binding.displayString)
            isAwaitingGlobalPermission = true
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AudioLogger.log("[Hotkey] global tap ACTIVE for %@", binding.displayString)
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        guard let binding else { return }
        // The defer-to-menu guard suppresses PRESSES only. Releases always run —
        // if the app becomes active between down and up, eating the keyUp
        // would leave isPressed stuck and silently swallow the next toggle.
        // Evaluated only once the chord has already matched, so the menu walk
        // never runs on ordinary typing.
        let menuOwnsPress = { self.deferToMainMenuWhenActive && NSApp.isActive && Self.mainMenuOwns(event) }

        let mods = Self.modifierFlags(from: event.flags)
        if binding.isModifierOnly {
            let chordActive = mods == binding.modifiers
            // A pure-modifier chord can't be a menu key equivalent, so the menu
            // never owns it and there is nothing to defer to.
            setPressed(chordActive)
            return
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard keyCode == binding.keyCode, mods == binding.modifiers, menuOwnsPress() == false else { return }
            if autorepeat == false { setPressed(true) }
        case .keyUp:
            guard keyCode == binding.keyCode else { return }
            setPressed(false)
        default:
            break
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

    /// True when a main-menu item carries this exact key equivalent. AppKit
    /// delivers it to the focused app regardless of our listen-only tap, so the
    /// menu is the handler and the tap must not act on top of it. Compares what
    /// AppKit itself compares — `charactersIgnoringModifiers` against
    /// `keyEquivalent` — so letters, punctuation and F-keys all match by the
    /// same rule.
    private static func mainMenuOwns(_ event: CGEvent) -> Bool {
        guard let mainMenu = NSApp.mainMenu,
              let nsEvent = NSEvent(cgEvent: event),
              let characters = nsEvent.charactersIgnoringModifiers?.lowercased(),
              characters.isEmpty == false else { return false }
        return menu(mainMenu, carries: characters, modifiers: comparableModifiers(nsEvent.modifierFlags))
    }

    /// Menu key equivalents are declared without the layout/hardware-only flags,
    /// so both sides are reduced to the same set before comparing.
    static func comparableModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
    }

    static func menu(
        _ menu: NSMenu,
        carries characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        for item in menu.items {
            if item.keyEquivalent.isEmpty == false,
               item.keyEquivalent.lowercased() == characters,
               comparableModifiers(item.keyEquivalentModifierMask) == modifiers {
                return true
            }
            if let submenu = item.submenu,
               self.menu(submenu, carries: characters, modifiers: modifiers) {
                return true
            }
        }
        return false
    }
}
