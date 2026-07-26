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
    let getDisplayString: @MainActor @Sendable (Double) -> String
    let setValue: @MainActor @Sendable (Double) -> Void
    let incrementValue: @Sendable (Double) -> Double
    let decrementValue: @Sendable (Double) -> Double
    let minValue: Double
    let maxValue: Double
    let resetValue: Double?

    init(label: String,
         help: String? = nil,
         getValue: @escaping @MainActor @Sendable () -> Double?,
         getDisplayString: @escaping @MainActor @Sendable (Double) -> String,
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

    init(config: Config) {
        self.config = config
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

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
        case .slider: return L10n.text("mixer.control.slider.roleDescription")
        case .toggle: return L10n.text("mixer.control.button.roleDescription")
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

// MARK: - Region announcement

/// Elements that can carry a one-shot spoken prefix ("Channel Mixer") so that when the
/// VoiceOver cursor is moved onto them programmatically (Cmd+5), the region name is spoken
/// before the element's own label — in a single utterance, so the focus change can't
/// interrupt it. Cleared after the read via `clearRegionPrefix(after:)`.
@MainActor
protocol MixerRegionAnnouncing: AnyObject {
    var regionAnnouncementPrefix: String? { get set }
    /// Pending clear for the current prefix, so a rapid re-announcement can cancel it.
    var regionPrefixClearWorkItem: DispatchWorkItem? { get set }
}

extension MixerRegionAnnouncing {
    /// Prepend the region name to `label` for one read, then clear it shortly after so
    /// ordinary navigation back to this element doesn't repeat the prefix.
    func applyRegionPrefix(_ prefix: String) {
        // Cancel any clear still pending from an earlier announcement — otherwise two
        // quick Cmd+5s would leave the first announcement's timer to fire mid-read of
        // the second, blanking the prefix before VoiceOver finishes speaking it.
        regionPrefixClearWorkItem?.cancel()
        regionAnnouncementPrefix = prefix
        let clear = DispatchWorkItem { [weak self] in
            self?.regionAnnouncementPrefix = nil
            self?.regionPrefixClearWorkItem = nil
        }
        regionPrefixClearWorkItem = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: clear)
    }

    func regionPrefixed(_ label: String?) -> String? {
        guard let prefix = regionAnnouncementPrefix else { return label }
        guard let label, !label.isEmpty else { return prefix }
        return "\(prefix), \(label)"
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
final class VirtualStripView: NSView, MixerRegionAnnouncing {
    let stripId: Int32
    private let labelProvider: @MainActor @Sendable () -> String?
    private(set) var childElements: [VirtualControlView] = []
    var regionAnnouncementPrefix: String?
    var regionPrefixClearWorkItem: DispatchWorkItem?

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
    override func accessibilityRoleDescription() -> String? { L10n.text("mixer.strip.roleDescription") }
    override func accessibilityIdentifier() -> String { "channel-strip-\(stripId)" }
    override func accessibilityLabel() -> String? { MainActor.assumeIsolated { regionPrefixed(labelProvider()) } }
    override func accessibilityChildren() -> [Any]? { childElements.isEmpty ? nil : childElements }
}

// MARK: - Grid overlay container (the "Mixer" area)

/// Accessibility-only NSView overlay. VoiceOver navigates the virtual strips/controls;
/// the visible UI is drawn separately (and accessibilityHidden). Driven by a descriptor
/// provider so it rebuilds as users join/leave the channel.
final class A11yVirtualGridOverlayView: NSView, MixerRegionAnnouncing {
    private(set) var virtualStrips: [VirtualStripView] = []
    private var provider: (@MainActor () -> [MixerStripDescriptor])?
    private var areaLabel: String = "Mixer"
    private var areaRoleDescription: String = "area"
    private var lastStripIds: [Int32] = []
    var regionAnnouncementPrefix: String?
    var regionPrefixClearWorkItem: DispatchWorkItem?

    override init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    // First-responder-capable so focusChannelMixer() can land here as a fallback when the
    // channel has no user strips (the strips themselves are already first-responder-capable).
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityRoleDescription() -> String? { areaRoleDescription }
    override func accessibilityLabel() -> String? { MainActor.assumeIsolated { regionPrefixed(areaLabel) } }
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
