//
//  MixerVirtualAccessibility.swift
//  ttaccessible
//
//  Ported from Rocco's Mixer app (Shared/Views/VirtualStripAccessibility.swift) so the
//  Channel Mixer's VoiceOver behaviour matches it exactly. On macOS the on-screen SwiftUI
//  is accessibilityHidden; THIS invisible parallel NSView tree is what VoiceOver navigates:
//
//      Mixer area (A11yVirtualGridOverlayView)
//        └─ per-user strip (VirtualStripView)            role .group, "channel-strip-<userID>"
//             └─ controls (VirtualControlView)           sliders + mute toggle
//
//  The strip/grid are decoupled from the Mixer app's MixerSession and driven by closures
//  (MixerStripDescriptor) so they bind to ttAccessible's per-user voice/media/pan/mute.
//  VirtualControlView's slider/toggle behaviour (increment/decrement/press + the high-
//  priority .announcementRequested posts) is kept verbatim; the X32 picker/text-edit/
//  section machinery is omitted (the channel mixer only needs sliders and a mute toggle).
//

#if os(macOS)
import AppKit

// MARK: - Control config (closure-driven; knows nothing about the data model)

struct VirtualSliderConfig {
    let label: String
    let help: String?
    let getValue: @MainActor @Sendable () -> Double?
    let getDisplayString: @Sendable (Double) -> String
    let setValue: @MainActor @Sendable (Double) -> Void
    let incrementValue: @Sendable (Double) -> Double
    let decrementValue: @Sendable (Double) -> Double
    let minValue: Double
    let maxValue: Double
    let resetValue: Double?

    init(label: String,
         help: String? = nil,
         getValue: @escaping @MainActor @Sendable () -> Double?,
         getDisplayString: @escaping @Sendable (Double) -> String,
         setValue: @escaping @MainActor @Sendable (Double) -> Void,
         incrementValue: @escaping @Sendable (Double) -> Double,
         decrementValue: @escaping @Sendable (Double) -> Double,
         minValue: Double,
         maxValue: Double,
         resetValue: Double? = nil) {
        self.label = label
        self.help = help
        self.getValue = getValue
        self.getDisplayString = getDisplayString
        self.setValue = setValue
        self.incrementValue = incrementValue
        self.decrementValue = decrementValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.resetValue = resetValue
    }
}

struct VirtualToggleConfig {
    let getLabel: @MainActor @Sendable () -> String
    let getState: @MainActor @Sendable () -> Bool?
    let setState: @MainActor @Sendable (Bool) -> Void
    let onAnnouncement: String
    let offAnnouncement: String
}

// MARK: - Virtual control view

/// Invisible NSView providing VoiceOver with one interactive control. Configured via
/// closures — does not know about the data model.
final class VirtualControlView: NSView {
    enum Config {
        case slider(VirtualSliderConfig)
        case toggle(VirtualToggleConfig)
    }

    let config: Config
    private var announceToggle = false

    // Per-instance accessibility identifier so the keyboard handler can map "the element
    // VoiceOver reports as focused" back to this NSView via a static registry.
    nonisolated(unsafe) private static var nextRegistryId: UInt64 = 0
    nonisolated(unsafe) private static var registry: [String: WeakBox] = [:]
    private final class WeakBox { weak var view: VirtualControlView? }
    let registryId: String

    init(config: Config) {
        self.config = config
        Self.nextRegistryId &+= 1
        self.registryId = "vctrl-\(Self.nextRegistryId)"
        super.init(frame: .zero)
        setAccessibilityIdentifier(registryId)
        let box = WeakBox()
        box.view = self
        Self.registry[registryId] = box
    }

    deinit { Self.registry.removeValue(forKey: registryId) }

    override func accessibilityIdentifier() -> String { registryId }

    /// Resolve "the virtual control VoiceOver thinks is focused" to its VirtualControlView.
    /// Walks the AX parent chain of the focused element looking for a "vctrl-N" identifier.
    @MainActor
    static func findFocusedControl() -> VirtualControlView? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let value = focused,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var current: AXUIElement? = unsafeBitCast(value, to: AXUIElement.self)
        for _ in 0..<6 {
            guard let elem = current else { break }
            var ident: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXIdentifierAttribute as CFString, &ident) == .success,
               let id = ident as? String,
               id.hasPrefix("vctrl-"),
               let view = registry[id]?.view {
                return view
            }
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parent) == .success,
               let p = parent,
               CFGetTypeID(p) == AXUIElementGetTypeID() {
                current = unsafeBitCast(p, to: AXUIElement.self)
            } else {
                break
            }
        }
        return nil
    }

    nonisolated(unsafe) static weak var currentFocused: VirtualControlView?

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func setAccessibilityFocused(_ focused: Bool) {
        super.setAccessibilityFocused(focused)
        if focused {
            Self.currentFocused = self
        } else if Self.currentFocused === self {
            Self.currentFocused = nil
        }
    }

    // MARK: Accessibility identity

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? {
        switch config {
        case .slider: return .slider
        case .toggle: return .button
        }
    }

    override func accessibilityRoleDescription() -> String? {
        switch config {
        case .slider: return "slider"
        case .toggle: return "button"
        }
    }

    override func accessibilityLabel() -> String? {
        MainActor.assumeIsolated {
            switch config {
            case .slider(let cfg): return cfg.label
            case .toggle(let cfg):
                // After a press, temporarily return action text ("Muted") instead of
                // state text ("Mute, On").
                if announceToggle {
                    guard let state = cfg.getState() else { return cfg.getLabel() }
                    return state ? cfg.onAnnouncement : cfg.offAnnouncement
                }
                return cfg.getLabel()
            }
        }
    }

    override func accessibilityValue() -> Any? {
        MainActor.assumeIsolated {
            switch config {
            case .slider(let cfg): return cfg.getValue()
            case .toggle: return nil
            }
        }
    }

    override func accessibilityValueDescription() -> String? {
        MainActor.assumeIsolated {
            switch config {
            case .slider(let cfg):
                guard let value = cfg.getValue() else { return "Unknown" }
                return cfg.getDisplayString(value)
            case .toggle: return nil
            }
        }
    }

    override func accessibilityHelp() -> String? {
        switch config {
        case .slider(let cfg): return cfg.help
        case .toggle: return nil
        }
    }

    override func accessibilityMinValue() -> Any? {
        switch config {
        case .slider(let cfg): return cfg.minValue
        case .toggle: return nil
        }
    }

    override func accessibilityMaxValue() -> Any? {
        switch config {
        case .slider(let cfg): return cfg.maxValue
        case .toggle: return nil
        }
    }

    // MARK: Actions

    override func accessibilityActionNames() -> [NSAccessibility.Action] {
        switch config {
        case .slider: return [.increment, .decrement, .press]
        case .toggle: return [.press]
        }
    }

    override func accessibilityActionDescription(_ action: NSAccessibility.Action) -> String? {
        switch action {
        case .increment: return "Increment"
        case .decrement: return "Decrement"
        case .press: return "Press"
        default: return nil
        }
    }

    override func accessibilityPerformAction(_ action: NSAccessibility.Action) {
        switch action {
        case .press: _ = accessibilityPerformPress()
        case .increment: _ = accessibilityPerformIncrement()
        case .decrement: _ = accessibilityPerformDecrement()
        default: super.accessibilityPerformAction(action)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated {
            switch config {
            case .slider(let cfg):
                guard let resetValue = cfg.resetValue else { return false }
                cfg.setValue(resetValue)
                let desc = cfg.getDisplayString(resetValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                         userInfo: [.announcement: desc, .priority: NSAccessibilityPriorityLevel.high])
                }
                return true
            case .toggle(let cfg):
                guard let current = cfg.getState() else { return false }
                announceToggle = true
                cfg.setState(!current)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.announceToggle = false
                }
                return true
            }
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        MainActor.assumeIsolated {
            guard case .slider(let cfg) = config, let current = cfg.getValue() else { return false }
            let newValue = cfg.incrementValue(current)
            cfg.setValue(newValue)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: cfg.getDisplayString(newValue), .priority: NSAccessibilityPriorityLevel.high])
            return true
        }
    }

    override func accessibilityPerformDecrement() -> Bool {
        MainActor.assumeIsolated {
            guard case .slider(let cfg) = config, let current = cfg.getValue() else { return false }
            let newValue = cfg.decrementValue(current)
            cfg.setValue(newValue)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: cfg.getDisplayString(newValue), .priority: NSAccessibilityPriorityLevel.high])
            return true
        }
    }
}

// MARK: - Strip descriptor (one per user)

struct MixerStripDescriptor {
    let id: Int32                                    // userID; identifier "channel-strip-<id>"
    let label: @MainActor @Sendable () -> String?    // "<name>, <voice level>, muted"
    let controls: [VirtualControlView.Config]
}

// MARK: - Virtual strip view (one user)

/// Invisible NSView for one user strip. VoiceOver enters it to reach the controls.
final class VirtualStripView: NSView {
    let stripId: Int32
    private let labelProvider: @MainActor @Sendable () -> String?
    private(set) var childElements: [VirtualControlView] = []

    init(descriptor: MixerStripDescriptor) {
        self.stripId = descriptor.id
        self.labelProvider = descriptor.label
        super.init(frame: .zero)
        setAccessibilityIdentifier("channel-strip-\(descriptor.id)")
        for cfg in descriptor.controls {
            let control = VirtualControlView(config: cfg)
            addSubview(control)
            childElements.append(control)
        }
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityRoleDescription() -> String? { "channel strip" }
    override func accessibilityIdentifier() -> String { "channel-strip-\(stripId)" }
    override func accessibilityLabel() -> String? { MainActor.assumeIsolated { labelProvider() } }
    override func accessibilityChildren() -> [Any]? { childElements.isEmpty ? nil : childElements }
}

// MARK: - Grid overlay container (the "Mixer" area)

/// Accessibility-only NSView overlay. VoiceOver navigates the virtual strips/controls;
/// the visible UI is drawn separately (and accessibilityHidden). Driven by a descriptor
/// provider so it rebuilds as users join/leave the channel.
final class A11yVirtualGridOverlayView: NSView {
    private(set) var virtualStrips: [VirtualStripView] = []
    private var provider: (@MainActor () -> [MixerStripDescriptor])?
    private var areaLabel: String = "Mixer"
    private var areaRoleDescription: String = "area"
    private var lastStripIds: [Int32] = []

    override init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityRoleDescription() -> String? { areaRoleDescription }
    override func accessibilityLabel() -> String? { areaLabel }
    override func accessibilityChildren() -> [Any]? { virtualStrips.isEmpty ? nil : virtualStrips }

    func configure(areaLabel: String, areaRoleDescription: String,
                   provider: @escaping @MainActor () -> [MixerStripDescriptor]) {
        self.areaLabel = areaLabel
        self.areaRoleDescription = areaRoleDescription
        self.provider = provider
        rebuildStrips()
    }

    /// Rebuild the virtual strips when the set of users changes (identity, not just count).
    func rebuildStrips() {
        guard let provider else { return }
        MainActor.assumeIsolated {
            let descriptors = provider()
            let ids = descriptors.map { $0.id }
            if ids == lastStripIds { return }
            lastStripIds = ids
            virtualStrips.forEach { $0.removeFromSuperview() }
            virtualStrips = descriptors.map { descriptor in
                let strip = VirtualStripView(descriptor: descriptor)
                addSubview(strip)
                return strip
            }
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        guard !virtualStrips.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        // Single vertical column of strips; controls stacked within each strip.
        let stripHeight = bounds.height / CGFloat(virtualStrips.count)
        for (i, strip) in virtualStrips.enumerated() {
            strip.frame = NSRect(x: 0, y: CGFloat(i) * stripHeight, width: bounds.width, height: stripHeight)
            let children = strip.childElements
            guard !children.isEmpty else { continue }
            let childHeight = stripHeight / CGFloat(children.count)
            for (j, child) in children.enumerated() {
                child.frame = NSRect(x: 0, y: CGFloat(j) * childHeight, width: bounds.width, height: childHeight)
            }
        }
    }
}
#endif
