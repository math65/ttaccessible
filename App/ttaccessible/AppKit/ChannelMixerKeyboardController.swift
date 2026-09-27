//
//  ChannelMixerKeyboardController.swift
//  ttaccessible
//
//  The Channel Mixer's keyboard model, matching Rocco's Mixer app: a local NSEvent
//  monitor that, while VoiceOver is focused on a mixer strip, routes
//    Cmd+Up/Down    -> the focused user's media-file volume (the window's Output volume
//                      slider when the cursor is OUTSIDE the mixer)
//    Up/Down        -> the focused user's voice volume
//    Left/Right     -> the focused user's VOICE pan
//    Cmd+Left/Right -> the focused user's MEDIA pan (on a strip only)
//    v / p / m      -> announce voice volume / voice pan / mute (single tap); reset 50% /
//                      center / toggle mute (double tap)
//    Cmd+p          -> announce media pan (single tap); reset media pan to center (double)
//    Cmd+Shift+Up/Down -> the window's Media volume slider (the media bus: every media
//                      stream at once), from anywhere in the window — the point is to duck
//                      the music without first navigating to the mixer.
//  Page Up/Down, Home, End -> wherever Up/Down move a level, these move it by ten and
//                      jump to 100 % / 0 %; the arrows move by one. They take the same
//                      modifiers as the arrows, but only ON a strip: off one, Cmd+Home
//                      and Cmd+End belong to the list under the cursor.
//                      See MixerLevelMove.
//  Single/double-tap and key-repeat use the ported KeyCommandHandler / ArrowRepeatHandler.
//  Single taps wait out the double-tap window before speaking (see KeyCommandHandler), so a
//  double tap speaks only its own result, never the old value first.
//  The focused user is resolved from VoiceOver's AX cursor (the "channel-strip-<id>"
//  identifier set by the virtual-accessibility tree), so plain arrows are only hijacked
//  while the cursor is inside the mixer — elsewhere they pass through untouched. Cmd+Up/Down
//  is the exception: off a strip it adjusts master output volume.
//

#if os(macOS)
import AppKit

@MainActor
final class ChannelMixerKeyboardController {
    private weak var coordinator: ChannelMixerCoordinator?
    /// Move the master/output volume and return the announcement.
    private let masterVolumeAdjust: (MixerLevelMove) -> String?
    /// Same, for the media bus (Cmd+Shift + a level key).
    private let mediaVolumeAdjust: (MixerLevelMove) -> String?

    private var monitor: Any?
    private let keyHandler = KeyCommandHandler()
    private let keyRepeat = ArrowRepeatHandler()

    init(coordinator: ChannelMixerCoordinator,
         masterVolumeAdjust: @escaping (MixerLevelMove) -> String?,
         mediaVolumeAdjust: @escaping (MixerLevelMove) -> String?) {
        self.coordinator = coordinator
        self.masterVolumeAdjust = masterVolumeAdjust
        self.mediaVolumeAdjust = mediaVolumeAdjust
    }

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        keyRepeat.stop()
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    // MARK: Dispatch

    private func handle(_ event: NSEvent) -> Bool {
        guard NSApp.isActive else { keyRepeat.stop(); return false }
        // Never intercept while typing in a text field.
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }

        let key = mixerKey(from: event)

        if event.type == .keyUp {
            if let key { keyRepeat.stop(key: key) }
            return false
        }
        guard event.type == .keyDown else { return false }

        let mods = event.modifierFlags
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        let plain = !cmd && !shift && !mods.contains(.option) && !mods.contains(.control)
        // What the key does to a level — nil for Left/Right, which pan.
        let move = key?.levelMove

        // Cmd+Shift + a level key -> the media bus. For the ARROWS this is deliberately
        // NOT gated on the mixer: ducking every media stream is the one level you want to
        // reach while reading the channel tree, mid-conversation. Home/End and the page
        // keys ARE gated, because off a strip they belong to the list under the cursor.
        // Resolving the focus costs ~8 AX calls, paid only on those rarer keys.
        if cmd, shift, !mods.contains(.option), !mods.contains(.control),
           let key, let move {
            guard !key.hasListMeaning || findFocusedStrip() != nil else {
                keyRepeat.stop(); return false
            }
            keyRepeat.start(key: key) { [weak self] in
                if let text = self?.mediaVolumeAdjust(move) { self?.announce(text) }
            }
            return true
        }

        // Cmd + a level key:
        //   • on a mixer strip -> that user's media-file volume
        //   • anywhere else     -> master (output) volume, for the arrows only
        if cmd, !shift, !mods.contains(.option), !mods.contains(.control),
           let key, let move {
            let strip = findFocusedStrip()
            if let uid = strip {
                keyRepeat.start(key: key) { [weak self] in
                    guard let self, let c = self.coordinator else { return }
                    self.announce(c.nudgeMedia(uid, move: move))
                }
            } else if !key.hasListMeaning {
                keyRepeat.start(key: key) { [weak self] in
                    if let text = self?.masterVolumeAdjust(move) { self?.announce(text) }
                }
            } else {
                // Cmd+Home/End/Page off a strip: the list under the cursor keeps them.
                keyRepeat.stop(); return false
            }
            return true
        }

        // Cmd+Left/Right -> the focused user's MEDIA-file pan (mirrors Cmd+Up/Down media
        // volume). Strip-gated only: unlike media volume, media pan has no off-strip
        // meaning, so off a strip these pass straight through.
        if cmd, !shift, !mods.contains(.option), !mods.contains(.control),
           let key, key == .left || key == .right {
            guard let uid = findFocusedStrip() else { keyRepeat.stop(); return false }
            keyRepeat.start(key: key) { [weak self] in
                guard let self, let c = self.coordinator else { return }
                self.announce(c.nudgeMediaPan(uid, right: key == .right))
            }
            return true
        }

        // Cmd+P -> announce (single) / reset-center (double) the focused user's media pan,
        // mirroring plain P for voice pan. Strip-gated, so off a strip Cmd+P is untouched.
        if cmd, !shift, !mods.contains(.option), !mods.contains(.control),
           !event.isARepeat, event.charactersIgnoringModifiers?.lowercased() == "p" {
            guard let uid = findFocusedStrip() else { return false }
            keyHandler.handle(key: "cmd-p",
                onSingle: { [weak self] in self?.announceFrom { $0.announceMediaPan(uid) } },
                onDouble: { [weak self] in self?.announceFrom { $0.resetMediaPan(uid) } })
            return true
        }

        // Everything else needs a focused user strip — but resolving it is up to ~8
        // system-wide AXUIElementCopyAttributeValue calls, far too costly to run on
        // every keystroke (and key-repeat). Only the plain level/pan keys and v/p/m/s act
        // on a strip, so gate the AX walk on those; typing, modified keys and unrelated
        // shortcuts pass straight through without paying for the IPC.
        guard plain else { return false }
        // Holding a letter down must not read as a double tap (which would toggle mute).
        if event.isARepeat, key == nil { return false }
        let isMixerKey = key != nil
            || ((event.charactersIgnoringModifiers?.lowercased()).map { ["v", "p", "m", "s"].contains($0) } ?? false)
        guard isMixerKey else { return false }

        guard let uid = findFocusedStrip(), coordinator != nil else {
            keyRepeat.stop(); return false
        }

        if plain, let key {
            keyRepeat.start(key: key) { [weak self] in
                guard let self, let c = self.coordinator else { return }
                let text: String
                if let move = key.levelMove {
                    text = c.nudgeVoice(uid, move: move)
                } else {
                    text = c.nudgeVoicePan(uid, right: key == .right)
                }
                self.announce(text)
            }
            return true
        }

        guard plain, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "v":
            keyHandler.handle(key: "v",
                onSingle: { [weak self] in self?.announceFrom { $0.announceVoice(uid) } },
                onDouble: { [weak self] in self?.announceFrom { $0.resetVoice(uid) } })
            return true
        case "p":
            keyHandler.handle(key: "p",
                onSingle: { [weak self] in self?.announceFrom { $0.announceVoicePan(uid) } },
                onDouble: { [weak self] in self?.announceFrom { $0.resetVoicePan(uid) } })
            return true
        case "m":
            keyHandler.handle(key: "m",
                onSingle: { [weak self] in self?.announceFrom { $0.muteState(uid) } },
                onDouble: { [weak self] in self?.announceFrom { $0.toggleMuteAndAnnounce(uid) } })
            return true
        case "s":
            keyHandler.handle(key: "s",
                onSingle: { [weak self] in self?.announceFrom { $0.soloState(uid) } },
                onDouble: { [weak self] in self?.announceFrom { $0.toggleSoloAndAnnounce(uid) } })
            return true
        default:
            return false
        }
    }

    private func announceFrom(_ make: (ChannelMixerCoordinator) -> String) {
        guard let coordinator else { return }
        announce(make(coordinator))
    }

    private func announce(_ text: String) {
        // .priority must be the NSNumber rawValue, not the enum, or VoiceOver drops it.
        // Keyboard edits aren't VO actions, so this explicit announcement is the only speech.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func mixerKey(from event: NSEvent) -> MixerKey? {
        MixerKey(event: event)
    }

    /// The user ID of the mixer strip VoiceOver's cursor is in, whether on the strip itself
    /// or on one of its controls. Walks the AX parent chain for "channel-strip-<id>", or a
    /// control's "channel-strip-<id>-control-<index>" (which saves a hop).
    private func findFocusedStrip() -> Int32? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let value = focused, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var current: AXUIElement? = unsafeBitCast(value, to: AXUIElement.self)
        let prefix = "channel-strip-"
        for _ in 0..<8 {
            guard let elem = current else { break }
            var ident: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXIdentifierAttribute as CFString, &ident) == .success,
               let id = ident as? String, id.hasPrefix(prefix) {
                let body = id.dropFirst(prefix.count)
                let stripPart = body.range(of: "-control-").map { body[body.startIndex..<$0.lowerBound] } ?? body
                if let uid = Int32(stripPart) { return uid }
            }
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parent) == .success,
               let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() {
                current = unsafeBitCast(p, to: AXUIElement.self)
            } else {
                break
            }
        }
        return nil
    }
}

// MARK: - Ported timing helpers (from Rocco's Mixer app)

/// The keys that drive a strip. Up/Down, Page Up/Down, Home and End move a level;
/// Left/Right pan it.
enum MixerKey: Hashable {
    case up, down, left, right, pageUp, pageDown, home, end

    /// The key an event carries, or nil for any other key. Shared with the window's level
    /// sliders (AudioGainControlView), so both read the keys the same way.
    init?(event: NSEvent) {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: self = .up
        case NSDownArrowFunctionKey: self = .down
        case NSLeftArrowFunctionKey: self = .left
        case NSRightArrowFunctionKey: self = .right
        case NSPageUpFunctionKey: self = .pageUp
        case NSPageDownFunctionKey: self = .pageDown
        case NSHomeFunctionKey: self = .home
        case NSEndFunctionKey: self = .end
        default: return nil
        }
    }

    /// What the key does to a level — nil for Left/Right.
    var levelMove: MixerLevelMove? {
        switch self {
        case .up: return .step(up: true)
        case .down: return .step(up: false)
        case .pageUp: return .page(up: true)
        case .pageDown: return .page(up: false)
        case .home: return .toMax
        case .end: return .toMin
        case .left, .right: return nil
        }
    }

    /// True for the keys macOS gives a meaning of their own in a list or a document:
    /// Home, End and the page keys all move through one. The mixer claims the ARROWS
    /// window-wide because under Command they mean nothing to a list; claiming these
    /// would cost the channel tree and the history their navigation, so off a strip they
    /// are left alone — Cmd+End must reach the last message, not silence the output.
    var hasListMeaning: Bool {
        switch self {
        case .home, .end, .pageUp, .pageDown: return true
        case .up, .down, .left, .right: return false
        }
    }

    /// Home and End jump once — there is nowhere further to go, and repeating them would
    /// only repeat the announcement.
    var repeats: Bool {
        switch self {
        case .home, .end: return false
        default: return true
        }
    }
}

/// Single vs double-tap discrimination for the v/p/m/s keys (0.35s window).
@MainActor
final class KeyCommandHandler {
    private var pending: [String: DispatchWorkItem] = [:]
    private var lastPress: [String: TimeInterval] = [:]
    private let doubleTapInterval: TimeInterval

    init(doubleTapInterval: TimeInterval = 0.35) {
        self.doubleTapInterval = doubleTapInterval
    }

    /// The single-tap action is DEFERRED until the double-tap window has passed, as in
    /// Rocco's Mixer app: a double tap must run ONLY its own action. Speaking the single
    /// tap on the first press was tried and rejected — every double tap then read the old
    /// value first (the single's announcement) and only then the double's.
    func handle(key: String, onSingle: @escaping () -> Void, onDouble: @escaping () -> Void) {
        let now = CACurrentMediaTime()
        if let last = lastPress[key], now - last <= doubleTapInterval {
            pending[key]?.cancel()
            pending[key] = nil
            lastPress[key] = 0          // a third press starts a fresh single tap
            onDouble()
            return
        }
        lastPress[key] = now
        let work = DispatchWorkItem { [weak self] in
            self?.lastPress[key] = 0
            self?.pending[key] = nil
            onSingle()
        }
        pending[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapInterval, execute: work)
    }
}

/// Key-repeat for the arrow and page keys (0.3s initial delay, then 0.15s). A key that
/// doesn't repeat (Home, End) still counts as held until its keyUp, so the system's own
/// auto-repeat keyDowns are swallowed instead of re-running the action.
@MainActor
final class ArrowRepeatHandler {
    private var pending: DispatchWorkItem?
    private var timer: Timer?
    private var activeKey: MixerKey?
    private let initialDelay: TimeInterval = 0.3
    private let repeatInterval: TimeInterval = 0.15

    func start(key: MixerKey, action: @escaping () -> Void) {
        if activeKey == key { return }
        stop()
        activeKey = key
        action()
        guard activeKey == key, key.repeats else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { _ in action() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: work)
    }

    func stop(key: MixerKey) { guard activeKey == key else { return }; stop() }

    func stop() {
        pending?.cancel(); pending = nil
        timer?.invalidate(); timer = nil
        activeKey = nil
    }
}
#endif
