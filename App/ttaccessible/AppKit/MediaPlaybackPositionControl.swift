//
//  MediaPlaybackPositionControl.swift
//  ttaccessible
//

import AppKit

/// Position readout + scrubber for media streaming.
///
/// Follows the same accessibility pattern as `AudioGainControlView`: the container is the
/// only accessibility element and speaks elapsed/total time. Child views are visual only.
@MainActor
final class MediaPlaybackPositionControl: NSView {
    private let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")
    private let slider = AccessibleSlider()

    private var durationMSec: UInt32 = 0
    private var isUserDragging = false
    private var hasVoiceOverFocus = false
    private var focusObserver: NSObjectProtocol?

    /// True while media is playing (not paused).
    var isPlaybackActive = false {
        didSet {
            guard oldValue != isPlaybackActive else { return }
            if !isPlaybackActive, hasVoiceOverFocus {
                announceValueToAccessibilityClient()
            }
        }
    }

    var onSeek: ((UInt32) -> Void)?

    var isAdjustingPosition: Bool { isUserDragging }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
            self.focusObserver = nil
        }
        guard newWindow != nil else { return }
        // Private AppKit notification (not in public API); used to detect VoiceOver focus on this control.
        focusObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("AXFocusedUIElementChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAccessibilityFocusChanged()
        }
    }

    func apply(
        elapsedMSec: UInt32,
        durationMSec: UInt32,
        enabled: Bool,
        announceAccessibility: Bool = false
    ) {
        self.durationMSec = durationMSec
        let timeText = Self.formatTime(elapsedMSec: elapsedMSec, durationMSec: durationMSec)

        timeLabel.stringValue = timeText
        slider.maxValue = max(1, Double(durationMSec))
        slider.isEnabled = enabled
        slider.doubleValue = Double(elapsedMSec)

        // Without this, an endless stream (live capture, radio) leaves a
        // perfectly ordinary-sounding slider in the tree that swallows every
        // adjustment. Say it's dimmed instead.
        setAccessibilityEnabled(enabled)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(max(1, Double(durationMSec)))

        if shouldPublishAccessibilityUpdates {
            publishAccessibilityValue(timeText, announce: announceAccessibility)
        } else if isPlaybackActive {
            // Keep the thumb and time label moving without posting .valueChanged (VoiceOver spam).
            setAccessibilityValue(timeText)
            setAccessibilityValueDescription(timeText)
        }
    }

    func beginUserDrag() {
        isUserDragging = true
    }

    func endUserDrag() {
        isUserDragging = false
    }

    override var acceptsFirstResponder: Bool { slider.isEnabled }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlain = modifiers.isDisjoint(with: [.command, .option, .control, .shift])
        guard isPlain else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123:
            seek(bySeconds: -5, announce: true)
        case 124:
            seek(bySeconds: +5, announce: true)
        case 115: // Home
            slider.setValueAndFire(slider.minValue)
        case 119: // End
            slider.setValueAndFire(slider.maxValue)
        case 116: // Page Up
            slider.setValueAndFire(slider.doubleValue + effectivePageStep)
        case 121: // Page Down
            slider.setValueAndFire(slider.doubleValue - effectivePageStep)
        default:
            super.keyDown(with: event)
        }
    }

    private var effectivePageStep: Double {
        if let pageStep = slider.pageStep, pageStep > 0 {
            return pageStep
        }
        return max(1, (slider.maxValue - slider.minValue) / 10)
    }

    /// Report the truth: returning `true` on a stream with nowhere to seek made
    /// VoiceOver confirm an adjustment that never happened.
    override func accessibilityPerformIncrement() -> Bool {
        seek(bySeconds: +5, announce: true)
    }

    override func accessibilityPerformDecrement() -> Bool {
        seek(bySeconds: -5, announce: true)
    }

    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }

    private var shouldPublishAccessibilityUpdates: Bool {
        !isPlaybackActive || hasVoiceOverFocus || isUserDragging
    }

    private func configure() {
        timeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setAccessibilityElement(false)

        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.pageStep = 10_000
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.setAccessibilityElement(false)

        let stack = NSStackView(views: [timeLabel, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            slider.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(L10n.text("mediaPlayer.position.label"))
        setAccessibilityValue("00:00 / 00:00")
        setAccessibilityValueDescription("00:00 / 00:00")
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let isDragging = NSApp.currentEvent?.type == .leftMouseDragged
        let elapsedMSec = UInt32(max(0, sender.doubleValue))
        let timeText = Self.formatTime(elapsedMSec: elapsedMSec, durationMSec: durationMSec)

        if isDragging {
            isUserDragging = true
            timeLabel.stringValue = timeText
            if shouldPublishAccessibilityUpdates {
                publishAccessibilityValue(timeText, announce: false)
            }
            return
        }

        isUserDragging = false
        apply(elapsedMSec: elapsedMSec, durationMSec: durationMSec, enabled: slider.isEnabled, announceAccessibility: true)
        onSeek?(elapsedMSec)
    }

    @discardableResult
    private func seek(bySeconds seconds: Int, announce: Bool) -> Bool {
        guard slider.isEnabled, durationMSec > 0 else { return false }
        let current = Int(slider.doubleValue)
        let duration = Int(durationMSec)
        let newMS = max(0, min(current + seconds * 1000, duration - 1))
        apply(elapsedMSec: UInt32(newMS), durationMSec: durationMSec, enabled: true, announceAccessibility: announce)
        onSeek?(UInt32(newMS))
        return true
    }

    private func publishAccessibilityValue(_ timeText: String, announce: Bool) {
        setAccessibilityValue(timeText)
        setAccessibilityValueDescription(timeText)
        if announce {
            announceValueToAccessibilityClient()
        }
    }

    private func handleAccessibilityFocusChanged() {
        let wasFocused = hasVoiceOverFocus
        hasVoiceOverFocus = isVoiceOverFocusedOnSelf()
        guard wasFocused != hasVoiceOverFocus else { return }
        guard hasVoiceOverFocus else { return }
        let elapsed = UInt32(max(0, slider.doubleValue))
        let timeText = Self.formatTime(elapsedMSec: elapsed, durationMSec: durationMSec)
        // Announce once on focus; timer-driven applies refresh silently while focused during playback.
        publishAccessibilityValue(timeText, announce: true)
    }

    private func isVoiceOverFocusedOnSelf() -> Bool {
        guard let focused = NSApp.accessibilityFocusedUIElement as AnyObject? else {
            return false
        }
        if focused === self { return true }
        if let view = focused as? NSView {
            return view === self || view.isDescendant(of: self)
        }
        return false
    }

    private func announceValueToAccessibilityClient() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private static func formatTime(elapsedMSec: UInt32, durationMSec: UInt32) -> String {
        "\(formatMSec(elapsedMSec)) / \(formatMSec(durationMSec))"
    }

    private static func formatMSec(_ msec: UInt32) -> String {
        let totalSec = Int(msec / 1000)
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d", m, s)
    }
}
