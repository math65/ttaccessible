//
//  ChannelMixerKeyboardController.swift
//  ttaccessible
//
//  The Channel Mixer's keyboard model, matching Rocco's Mixer app: a local NSEvent
//  monitor that, while VoiceOver is focused on a mixer strip, routes
//    Cmd+Up/Down    -> the focused user's media-file volume (master output volume when
//                      the cursor is OUTSIDE the mixer)
//    Up/Down        -> the focused user's voice volume
//    Left/Right     -> the focused user's VOICE pan
//    Cmd+Left/Right -> the focused user's MEDIA pan (on a strip only)
//    v / p / m      -> announce voice volume / voice pan / mute (single tap); reset 50% /
//                      center / toggle mute (double tap)
//    Cmd+p          -> announce media pan (single tap); reset media pan to center (double)
//  Single/double-tap and key-repeat use the ported KeyCommandHandler / ArrowRepeatHandler.
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
    /// Adjust the master/output volume one step (up==true) and return the announcement.
    private let masterVolumeAdjust: (Bool) -> String?

    private var monitor: Any?
    private let keyHandler = KeyCommandHandler()
    private let arrowRepeat = ArrowRepeatHandler()

    init(coordinator: ChannelMixerCoordinator, masterVolumeAdjust: @escaping (Bool) -> String?) {
        self.coordinator = coordinator
        self.masterVolumeAdjust = masterVolumeAdjust
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
        arrowRepeat.stop()
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    // MARK: Dispatch

    private func handle(_ event: NSEvent) -> Bool {
        guard NSApp.isActive else { arrowRepeat.stop(); return false }
        // Never intercept while typing in a text field.
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }

        let arrow = arrowKey(from: event)

        if event.type == .keyUp {
            if let arrow { arrowRepeat.stop(key: arrow) }
            return false
        }
        guard event.type == .keyDown else { return false }

        let mods = event.modifierFlags
        let cmd = mods.contains(.command)
        let plain = !cmd && !mods.contains(.option) && !mods.contains(.control)

        // Cmd+Up/Down:
        //   • on a mixer strip -> that user's media-file volume
        //   • anywhere else     -> master (output) volume
        if cmd, !mods.contains(.option), !mods.contains(.control),
           let arrow, arrow == .up || arrow == .down {
            if let uid = findFocusedStripUserID() {
                arrowRepeat.start(key: arrow) { [weak self] in
                    guard let self, let c = self.coordinator else { return }
                    self.announce(c.nudgeMedia(uid, up: arrow == .up))
                }
            } else {
                arrowRepeat.start(key: arrow) { [weak self] in
                    if let text = self?.masterVolumeAdjust(arrow == .up) { self?.announce(text) }
                }
            }
            return true
        }

        // Cmd+Left/Right -> the focused user's MEDIA-file pan (mirrors Cmd+Up/Down media
        // volume). Strip-gated only: unlike media volume, media pan has no off-strip
        // meaning, so off a strip these pass straight through.
        if cmd, !mods.contains(.option), !mods.contains(.control),
           let arrow, arrow == .left || arrow == .right {
            guard let uid = findFocusedStripUserID() else { arrowRepeat.stop(); return false }
            arrowRepeat.start(key: arrow) { [weak self] in
                guard let self, let c = self.coordinator else { return }
                self.announce(c.nudgeMediaPan(uid, right: arrow == .right))
            }
            return true
        }

        // Cmd+P -> announce (single) / reset-center (double) the focused user's media pan,
        // mirroring plain P for voice pan. Strip-gated, so off a strip Cmd+P is untouched.
        if cmd, !mods.contains(.option), !mods.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "p" {
            guard let uid = findFocusedStripUserID() else { return false }
            keyHandler.handle(key: "cmd-p",
                onSingle: { [weak self] in self?.announceFrom { $0.announceMediaPan(uid) } },
                onDouble: { [weak self] in self?.announceFrom { $0.resetMediaPan(uid) } })
            return true
        }

        // Everything else needs a focused user strip — but resolving it is up to ~8
        // system-wide AXUIElementCopyAttributeValue calls, far too costly to run on
        // every keystroke (and key-repeat). Only the plain arrows and v/p/m/s act on a
        // strip, so gate the AX walk on those; typing, modified keys and unrelated
        // shortcuts pass straight through without paying for the IPC.
        guard plain else { return false }
        let isMixerKey = arrow != nil
            || ((event.charactersIgnoringModifiers?.lowercased()).map { ["v", "p", "m", "s"].contains($0) } ?? false)
        guard isMixerKey else { return false }

        guard let uid = findFocusedStripUserID(), coordinator != nil else {
            arrowRepeat.stop(); return false
        }

        if plain, let arrow {
            arrowRepeat.start(key: arrow) { [weak self] in
                guard let self, let c = self.coordinator else { return }
                let text: String
                switch arrow {
                case .up: text = c.nudgeVoice(uid, up: true)
                case .down: text = c.nudgeVoice(uid, up: false)
                case .left: text = c.nudgeVoicePan(uid, right: false)
                case .right: text = c.nudgeVoicePan(uid, right: true)
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

    private func arrowKey(from event: NSEvent) -> ArrowKey? {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: return .up
        case NSDownArrowFunctionKey: return .down
        case NSLeftArrowFunctionKey: return .left
        case NSRightArrowFunctionKey: return .right
        default: return nil
        }
    }

    /// Walk the AX parent chain of VoiceOver's focused element for a "channel-strip-<id>".
    private func findFocusedStripUserID() -> Int32? {
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
               let id = ident as? String, id.hasPrefix(prefix),
               let uid = Int32(id.dropFirst(prefix.count)) {
                return uid
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

enum ArrowKey { case up, down, left, right }

/// Single vs double-tap discrimination for the v/p/m keys (0.35s window).
@MainActor
final class KeyCommandHandler {
    private var pending: [String: DispatchWorkItem] = [:]
    private var lastPress: [String: TimeInterval] = [:]
    private let doubleTapInterval: TimeInterval = 0.35

    func handle(key: String, onSingle: @escaping () -> Void, onDouble: @escaping () -> Void) {
        let now = CACurrentMediaTime()
        if let last = lastPress[key], now - last <= doubleTapInterval {
            pending[key]?.cancel(); pending[key] = nil; lastPress[key] = 0
            onDouble()
            return
        }
        lastPress[key] = now
        let work = DispatchWorkItem { [weak self] in
            self?.lastPress[key] = 0
            onSingle()
        }
        pending[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapInterval, execute: work)
    }
}

/// Key-repeat for the arrow keys (0.3s initial delay, then 0.15s).
@MainActor
final class ArrowRepeatHandler {
    private var pending: DispatchWorkItem?
    private var timer: Timer?
    private var activeKey: ArrowKey?
    private let initialDelay: TimeInterval = 0.3
    private let repeatInterval: TimeInterval = 0.15

    func start(key: ArrowKey, action: @escaping () -> Void) {
        if activeKey == key { return }
        stop()
        activeKey = key
        action()
        guard activeKey == key else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { _ in action() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: work)
    }

    func stop(key: ArrowKey) { guard activeKey == key else { return }; stop() }

    func stop() {
        pending?.cancel(); pending = nil
        timer?.invalidate(); timer = nil
        activeKey = nil
    }
}
#endif
