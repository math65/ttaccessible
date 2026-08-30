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

/// Ported from the Mixer app's `VirtualPickerConfig` (VirtualStripAccessibility.swift).
/// This is the picker machinery the first port deliberately left out — see this file's
/// header — which is why source pickers had to be hand-rolled as bare NSButtons and never
/// announced as pop up buttons.
///
/// `options` is a FLAT list, as in Mixer: VoiceOver steps it with increment/decrement
/// without opening anything, and press opens the menu positioned at the current item.
/// `extraItems` are trailing actions that are not selectable sources (e.g. "Select
/// Application…"), appended after a separator.
struct VirtualPickerConfig {
    let label: String
    /// Closure rather than Mixer's plain array: ttaccessible's source list grows when
    /// the user browses for an application that wasn't running.
    let getOptions: @MainActor @Sendable () -> [String]
    let getIndex: @MainActor @Sendable () -> Int?
    let setIndex: @MainActor @Sendable (Int) -> Void
    /// Title + handler for trailing non-source actions. Empty for a plain picker.
    var extraItems: [(title: String, action: @MainActor @Sendable () -> Void)] = []

    init(label: String,
         getOptions: @escaping @MainActor @Sendable () -> [String],
         getIndex: @escaping @MainActor @Sendable () -> Int?,
         setIndex: @escaping @MainActor @Sendable (Int) -> Void,
         extraItems: [(title: String, action: @MainActor @Sendable () -> Void)] = []) {
        self.label = label
        self.getOptions = getOptions
        self.getIndex = getIndex
        self.setIndex = setIndex
        self.extraItems = extraItems
    }
}

// MARK: - Virtual control view

/// Invisible NSView providing VoiceOver with one interactive control. Configured via
/// closures — does not know about the data model.
final class VirtualControlView: NSView {
    enum Config {
        case slider(VirtualSliderConfig)
        case toggle(VirtualToggleConfig)
        case picker(VirtualPickerConfig)
    }

    let config: Config
    /// "channel-strip-<stripID>-control-<index>", set by the owning strip. The keyboard
    /// controller reads it off VoiceOver's AX cursor to know WHICH control is focused —
    /// the General strip's arrows act on the focused level, not on a fixed one.
    var axIdentifier: String?
    private var announceToggle = false
    private var cachedPickerController: VirtualPickerController?

    private func pickerController(_ cfg: VirtualPickerConfig) -> VirtualPickerController {
        if let cachedPickerController { return cachedPickerController }
        let controller = VirtualPickerController(config: cfg)
        cachedPickerController = controller
        return controller
    }

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

    override func accessibilityIdentifier() -> String { axIdentifier ?? "" }

    override func accessibilityRole() -> NSAccessibility.Role? {
        switch config {
        case .slider: return .slider
        case .toggle: return .button
        case .picker: return .popUpButton
        }
    }

    override func accessibilityRoleDescription() -> String? {
        switch config {
        case .slider: return L10n.text("mixer.control.slider.roleDescription")
        case .toggle: return L10n.text("mixer.control.button.roleDescription")
        case .picker: return L10n.text("mixer.control.picker.roleDescription")
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
            case .picker(let cfg): return cfg.label
            }
        }
    }

    override func accessibilityValue() -> Any? {
        MainActor.assumeIsolated {
            switch config {
            case .slider(let cfg): return cfg.getValue()
            case .toggle: return nil
            case .picker(let cfg):
                let options = cfg.getOptions()
                guard let idx = cfg.getIndex(), options.indices.contains(idx) else { return nil }
                return options[idx]
            }
        }
    }

    override func accessibilityValueDescription() -> String? {
        MainActor.assumeIsolated {
            switch config {
            case .slider(let cfg):
                guard let value = cfg.getValue() else { return "Unknown" }
                return cfg.getDisplayString(value)
            case .toggle, .picker: return nil
            }
        }
    }

    override func accessibilityHelp() -> String? {
        switch config {
        case .slider(let cfg): return cfg.help
        case .toggle, .picker: return nil
        }
    }

    override func accessibilityMinValue() -> Any? {
        switch config {
        case .slider(let cfg): return cfg.minValue
        case .toggle, .picker: return nil
        }
    }

    override func accessibilityMaxValue() -> Any? {
        switch config {
        case .slider(let cfg): return cfg.maxValue
        case .toggle, .picker: return nil
        }
    }

    // MARK: Actions

    override func accessibilityActionNames() -> [NSAccessibility.Action] {
        switch config {
        case .slider: return [.increment, .decrement, .press]
        case .toggle: return [.press]
        // Press opens the menu; increment/decrement step the selection without it.
        case .picker: return [.increment, .decrement, .press]
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
                                         userInfo: [.announcement: desc, .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
            case .picker(let cfg):
                pickerController(cfg).showMenu(in: self)
                return true
            }
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        MainActor.assumeIsolated {
            if case .picker(let cfg) = config { return pickerController(cfg).step(by: 1) }
            guard case .slider(let cfg) = config, let current = cfg.getValue() else { return false }
            let newValue = cfg.incrementValue(current)
            cfg.setValue(newValue)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: cfg.getDisplayString(newValue), .priority: NSAccessibilityPriorityLevel.high.rawValue])
            return true
        }
    }

    override func accessibilityPerformDecrement() -> Bool {
        MainActor.assumeIsolated {
            if case .picker(let cfg) = config { return pickerController(cfg).step(by: -1) }
            guard case .slider(let cfg) = config, let current = cfg.getValue() else { return false }
            let newValue = cfg.decrementValue(current)
            cfg.setValue(newValue)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: cfg.getDisplayString(newValue), .priority: NSAccessibilityPriorityLevel.high.rawValue])
            return true
        }
    }

}



// MARK: - Picker behaviour (ported from Mixer's VirtualStripAccessibility)

/// The picker half of Mixer's virtual-accessibility engine, factored out so it can be
/// attached to ANY view — the invisible `VirtualControlView` (Channel Mixer) or a real,
/// visible AppKit control. Mixer needs an invisible parallel tree because its visible
/// layer is SwiftUI; where the visible control is already an NSView there is nothing to
/// duplicate, so the behaviour lives here and the control adopts it.
@MainActor
final class VirtualPickerController: NSObject {
    private let config: VirtualPickerConfig

    init(config: VirtualPickerConfig) {
        self.config = config
    }

    var label: String { config.label }

    /// The selected option, which is what VoiceOver reads as the control's value.
    var selectedOption: String? {
        let options = config.getOptions()
        guard let idx = config.getIndex(), options.indices.contains(idx) else { return nil }
        return options[idx]
    }

    /// Step the selection WITHOUT opening the menu — VoiceOver's increment/decrement.
    /// This is what lets every source be reached without entering a menu at all.
    func step(by offset: Int) -> Bool {
        let options = config.getOptions()
        guard options.isEmpty == false, let idx = config.getIndex() else { return false }
        let next = min(max(idx + offset, 0), options.count - 1)
        guard next != idx else { return false }
        config.setIndex(next)
        announce(options[next])
        return true
    }

    /// Flat menu, opened positioned at the current selection — exactly Mixer's picker.
    /// Deliberately no submenus: no submenu-bearing menu has ever been navigable by
    /// VoiceOver here (NSPopUpButton+submenu announces "pop up button group";
    /// NSButton+submenu announces "button group" and bounces focus back to the sheet).
    func showMenu(in view: NSView) {
        let options = config.getOptions()
        let idx = config.getIndex() ?? 0
        let menu = NSMenu()
        for (i, option) in options.enumerated() {
            let item = NSMenuItem(title: option, action: #selector(itemSelected(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            if i == idx { item.state = .on }
            menu.addItem(item)
        }
        if config.extraItems.isEmpty == false {
            menu.addItem(.separator())
            for (i, extra) in config.extraItems.enumerated() {
                let item = NSMenuItem(title: extra.title, action: #selector(extraSelected(_:)), keyEquivalent: "")
                item.tag = i
                item.target = self
                menu.addItem(item)
            }
        }
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            menu.popUp(positioning: menu.item(at: idx), at: NSPoint(x: 0, y: view.bounds.height), in: view)
        }
    }

    @objc private func itemSelected(_ sender: NSMenuItem) {
        let options = config.getOptions()
        guard options.indices.contains(sender.tag) else { return }
        config.setIndex(sender.tag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.announce(options[sender.tag])
        }
    }

    @objc private func extraSelected(_ sender: NSMenuItem) {
        guard config.extraItems.indices.contains(sender.tag) else { return }
        config.extraItems[sender.tag].action()
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
        for (index, cfg) in descriptor.controls.enumerated() {
            let control = VirtualControlView(config: cfg)
            control.axIdentifier = "channel-strip-\(descriptor.id)-control-\(index)"
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
