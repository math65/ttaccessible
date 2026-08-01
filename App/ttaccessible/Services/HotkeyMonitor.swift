//
//  HotkeyMonitor.swift
//  ttaccessible
//
//  Watches for a HotkeyBinding and reports press/release. Replaces the
//  KeyboardShortcuts library for push-to-talk so we can support single keys,
//  key+modifier combos, AND pure-modifier chords (⌘⌃), each either app-focused
//  or global.
//
//  Global scope routes by the shape of the binding:
//
//  - Anything with a key code registers through Carbon RegisterEventHotKey. No
//    permission is needed and the chord IS swallowed: the WindowServer takes it
//    before the frontmost app sees it. Bare keys work, and a held key delivers
//    one press/release pair with no autorepeat. Measured on a sandboxed build
//    with physical keypresses, then reproduced on a second machine — see issue
//    #41. (The earlier note here claiming the opposite described the
//    KeyboardShortcuts library, not a measurement.)
//  - A pure-modifier chord (⌘⌃) has no key code, and RegisterEventHotKey
//    requires one — 0 is a real key — so it stays on a listen-only CGEventTap
//    (.cgSessionEventTap, .listenOnly) gated by Input Monitoring. That tap
//    DETECTS the chord system-wide but cannot SWALLOW it: a consuming
//    (.defaultTap) tap needs Accessibility, which the App Sandbox blocks.
//
//  Known limit: secure input (a password field) suspends a Carbon hotkey. It
//  resumes on its own once the field is gone.
//
//  App-focused (local) scope uses an NSEvent local monitor (no permission), and
//  CAN swallow the matched key — local monitors consume events destined for our
//  own app, so the key won't type into a field while focused.
//

import AppKit
import Carbon.HIToolbox
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

/// Process-wide registry for Carbon hotkeys.
///
/// `RegisterEventHotKey` needs no permission and — measured, not assumed — the
/// WindowServer intercepts the chord before any app sees it, including our own:
/// with ⌘⇧A registered here AND carried by a main-menu item, the Carbon handler
/// fires and the menu item never does. That is what makes it strictly better
/// than the listen-only tap, which is stuck asking for Input Monitoring and
/// still lets the key through.
///
/// One handler per process (Carbon delivers every hotkey to every installed
/// handler), so registrations are multiplexed by `EventHotKeyID.id`.
private final class CarbonHotKeyCenter {
    static let shared = CarbonHotKeyCenter()

    /// `true` = pressed, `false` = released.
    private var handlers: [UInt32: (Bool) -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    /// Registers `binding` and returns the id to unregister with, or nil when
    /// the system refuses it.
    ///
    /// Measured: macOS refuses ONLY a duplicate within the same process
    /// (`eventHotKeyExistsErr`, -9878). A chord another process already holds is
    /// granted — both registrants then receive it — and so are the system ones
    /// (⌘Space, ⌘Tab, ⌃↑). So a refusal here means one thing only: our own two
    /// hotkeys carry the same chord.
    func register(_ binding: HotkeyBinding, onEvent: @escaping (Bool) -> Void) -> UInt32? {
        guard let keyCode = binding.keyCode else { return nil }
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(binding.modifiers),
            EventHotKeyID(signature: OSType(0x54544131), id: id),  // 'TTA1'
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            AudioLogger.log("[Hotkey] RegisterEventHotKey FAILED status=%d for %@",
                            Int(status), binding.displayString)
            return nil
        }
        refs[id] = ref
        handlers[id] = onEvent
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    /// Whether the system would hand us this chord — asked by registering it and
    /// letting it go straight away.
    ///
    /// In practice this only ever catches OUR OWN collision: push-to-talk and
    /// the mic toggle carrying the same chord, where the second registration is
    /// refused and that hotkey silently never runs. A chord held by another app
    /// is granted (see `register`), and a chord an app handles internally — a
    /// menu item, a DAW's key map — is invisible to every API: we simply take
    /// the key from it, which is what a global hotkey is for.
    ///
    /// Callers must exclude the binding we ourselves currently hold, or it reads
    /// as taken because of us.
    func isAvailable(_ binding: HotkeyBinding) -> Bool {
        guard let keyCode = binding.keyCode else { return false }
        var ref: EventHotKeyRef?
        let probeID = UInt32.max  // never collides with a real registration
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(binding.modifiers),
            EventHotKeyID(signature: OSType(0x54544150), id: probeID),  // 'TTAP'
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref { UnregisterEventHotKey(ref) }
        return status == noErr
    }

    private func installHandlerIfNeeded() {
        guard handlerInstalled == false else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return noErr }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            CarbonHotKeyCenter.shared.handlers[id.id]?(pressed)
            return noErr
        }, 2, &specs, nil, nil)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}

final class HotkeyMonitor {
    enum Scope {
        case local   // app-focused only
        case global  // system-wide
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Called when the hotkey can't run — with what is wrong, or nil once it
    /// runs again. Called on the thread that configures the monitor: the main one.
    var onUnavailabilityChange: ((Unavailability?) -> Void)?

    /// Why a configured hotkey isn't running. Both are surfaced in Preferences:
    /// silence at that point reads as "the app is broken".
    enum Unavailability: Equatable {
        /// Our two hotkeys carry the same chord; macOS registers it once, so the
        /// second one silently never fires.
        case collidesWithOurOtherHotkey(HotkeyBinding)
        /// A key the chat field needs, bound globally. Carbon takes it before
        /// any app sees it — there is no giving it back to the field the way the
        /// local monitor and the menu do, so it would block typing everywhere.
        /// The recorder refuses these; this catches settings that predate it.
        case wouldBlockTyping(HotkeyBinding)
    }

    private var binding: HotkeyBinding?
    private var scope: Scope = .local
    private var wantsReleaseEvents = true

    private var localMonitor: Any?
    private var resignActiveObserver: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var carbonHotKeyID: UInt32?
    private var isPressed = false

    /// Set when the global tap couldn't be created because Input Monitoring is
    /// not yet granted — the caller reconfigures after a grant.
    private(set) var isAwaitingGlobalPermission = false

    private(set) var unavailability: Unavailability? {
        didSet {
            guard oldValue != unavailability else { return }
            onUnavailabilityChange?(unavailability)
        }
    }

    func configure(
        binding: HotkeyBinding?,
        scope: Scope,
        wantsReleaseEvents: Bool = true
    ) {
        stop()
        self.binding = binding
        self.scope = scope
        self.wantsReleaseEvents = wantsReleaseEvents

        guard let binding, binding.isValid else { return }
        switch scope {
        case .local:
            installLocalMonitor(binding)
        case .global:
            // Route by the shape of the binding. Anything with a key code goes
            // to Carbon: no permission, and the chord is genuinely swallowed.
            // A pure-modifier chord has no key code to register, so it is the
            // one form still worth paying Input Monitoring for.
            if binding.isModifierOnly {
                installEventTap(binding)
            } else if binding.typesIntoTextFields {
                // Swallowed globally means swallowed HERE too, including in the
                // chat field. Refuse rather than take the key away everywhere.
                unavailability = .wouldBlockTyping(binding)
                AudioLogger.log("[Hotkey] %@ types into text fields — refused as a global hotkey",
                                binding.displayString)
            } else {
                installCarbonHotKey(binding)
            }
        }
    }

    /// A refusal here means our other hotkey already carries this chord (the
    /// only case macOS refuses — see `CarbonHotKeyCenter.register`). We do NOT
    /// fall back to the tap: it would ask for Input Monitoring out of nowhere,
    /// and the chord would still be answered twice. Better to leave this one
    /// plainly inactive and say so in Preferences. The recorder rejects the
    /// collision up front, so this is the config that predates that check.
    private func installCarbonHotKey(_ binding: HotkeyBinding) {
        guard let id = CarbonHotKeyCenter.shared.register(binding, onEvent: { [weak self] pressed in
            self?.setPressed(pressed)
        }) else {
            unavailability = .collidesWithOurOtherHotkey(binding)
            AudioLogger.log("[Hotkey] %@ is already registered by our other hotkey — this one inactive",
                            binding.displayString)
            return
        }
        carbonHotKeyID = id
        AudioLogger.log("[Hotkey] Carbon hotkey ACTIVE for %@ (no permission needed)",
                        binding.displayString)
    }

    /// Whether the system would grant `binding` to us right now. `current` is the
    /// binding this monitor already holds, if any — it is available by definition,
    /// and would otherwise read as taken because we are the ones holding it.
    static func isChordAvailable(_ binding: HotkeyBinding, current: HotkeyBinding?) -> Bool {
        if let current, current == binding { return true }
        return CarbonHotKeyCenter.shared.isAvailable(binding)
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
        if let carbonHotKeyID {
            CarbonHotKeyCenter.shared.unregister(carbonHotKeyID)
            self.carbonHotKeyID = nil
        }
        isAwaitingGlobalPermission = false
        unavailability = nil
        if isPressed {
            isPressed = false
            onRelease?()
        }
    }

    // MARK: - Global, pure-modifier chords only, via a listen-only CGEventTap

    /// Only ever installed for a pure-modifier chord — everything with a key
    /// code goes through Carbon now. So the tap watches `flagsChanged` alone,
    /// and never has to decide whether a menu item or a focused text field
    /// should answer the key first: a chord of modifiers types nothing and can't
    /// be a menu key equivalent.
    private func installEventTap(_ binding: HotkeyBinding) {
        AudioLogger.log("[Hotkey] installEventTap binding=%@ preflight=%d",
                        binding.displayString,
                        CGPreflightListenEventAccess() ? 1 : 0)
        guard InputMonitoringPermission.request() else {
            AudioLogger.log("[Hotkey] Input Monitoring not granted — global pending for %@", binding.displayString)
            isAwaitingGlobalPermission = true
            return
        }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

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
        guard let binding, binding.isModifierOnly else { return }
        let mods = Self.modifierFlags(from: event.flags)
        setPressed(mods == binding.modifiers)
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
            // A binding the focused field would use — a printable key, Return,
            // Tab, an arrow — must keep reaching it: the field wins over
            // push-to-talk there. Same predicate as the global tap and the menu.
            if binding.typesIntoTextFields, Self.isTextInputFocused() {
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
