//
//  AudioGainControlView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

final class AudioGainControlView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    var valueDB: Double = 0
    var onChange: ((Double) -> Void)?

    init(title: String, accessibilityLabel: String, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)

        titleLabel.stringValue = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setAccessibilityElement(false)

        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(handleSliderChanged(_:))
        slider.setAccessibilityElement(false)

        let stack = NSStackView(views: [titleLabel, slider, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(100)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(
                name: L10n.text("connectedServer.audio.gain.resetAccessibilityAction"),
                target: self,
                selector: #selector(resetToZeroAccessibilityAction)
            )
        ])

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        setValue(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setValue(_ value: Double) {
        valueDB = AppPreferences.clampGainDB(value)
        slider.doubleValue = Self.percent(forGainDB: valueDB)
        let text = Self.format(percent: slider.doubleValue)
        valueLabel.stringValue = text
        setAccessibilityValue(slider.doubleValue)
        setAccessibilityValueDescription(text)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow, .downArrow:
            adjust(by: -1)
        case .rightArrow, .upArrow:
            adjust(by: 1)
        case .pageUp:
            adjust(by: 10)
        case .pageDown:
            adjust(by: -10)
        case .home:
            setAndNotify(-24)
        case .end:
            setAndNotify(24)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        adjust(by: 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        adjust(by: -1)
        return true
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        self
    }

    @objc
    func resetToZeroAccessibilityAction() -> Bool {
        setValue(0)
        onChange?(0)
        return true
    }

    @objc
    func handleSliderChanged(_ sender: NSSlider) {
        let gainDB = Self.gainDB(forPercent: sender.doubleValue)
        setValue(gainDB)
        onChange?(valueDB)
    }

    func adjust(by delta: Double) {
        let updated = min(max((slider.doubleValue + delta).rounded(), 0), 100)
        setAndNotify(Self.gainDB(forPercent: updated))
    }

    func setAndNotify(_ value: Double) {
        guard value != valueDB else {
            return
        }
        setValue(value)
        onChange?(valueDB)
    }

    static func percent(forGainDB value: Double) -> Double {
        ((AppPreferences.clampGainDB(value) + 24) / 48 * 100).rounded()
    }

    static func gainDB(forPercent value: Double) -> Double {
        let clamped = min(max(value.rounded(), 0), 100)
        return AppPreferences.clampGainDB((clamped / 100 * 48) - 24)
    }

    static func format(percent value: Double) -> String {
        String(format: "%.0f%%", min(max(value.rounded(), 0), 100))
    }
}
