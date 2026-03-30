//
//  AdvancedMicrophoneSettingsView.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import SwiftUI

private final class AdvancedMicrophoneParameterSliderNSView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)

    private var value: Double = 0
    private var step: Double = 1
    private var minimum: Double = 0
    private var maximum: Double = 1
    private var formatter: (Double) -> String = { "\($0)" }
    private var onChange: ((Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setAccessibilityElement(false)

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

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        title: String,
        minimum: Double,
        maximum: Double,
        step: Double,
        value: Double,
        formatter: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) {
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.formatter = formatter
        self.onChange = onChange
        slider.minValue = minimum
        slider.maxValue = maximum
        setValue(value)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow, .downArrow:
            adjust(by: -step)
        case .rightArrow, .upArrow:
            adjust(by: step)
        case .pageUp:
            adjust(by: step * 10)
        case .pageDown:
            adjust(by: -(step * 10))
        case .home:
            setAndNotify(minimum)
        case .end:
            setAndNotify(maximum)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        adjust(by: step)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        adjust(by: -step)
        return true
    }

    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }

    @objc
    private func handleSliderChanged(_ sender: NSSlider) {
        let snapped = snap(sender.doubleValue)
        setValue(snapped)
        onChange?(snapped)
    }

    private func setValue(_ newValue: Double) {
        value = clamp(snap(newValue))
        slider.doubleValue = value
        let text = formatter(value)
        valueLabel.stringValue = text
        setAccessibilityValue(text)
    }

    private func adjust(by delta: Double) {
        setAndNotify(value + delta)
    }

    private func setAndNotify(_ newValue: Double) {
        let adjusted = clamp(snap(newValue))
        guard adjusted != value else { return }
        setValue(adjusted)
        onChange?(adjusted)
    }

    private func clamp(_ candidate: Double) -> Double {
        min(max(candidate, minimum), maximum)
    }

    private func snap(_ candidate: Double) -> Double {
        guard step > 0 else { return candidate }
        let snapped = ((candidate - minimum) / step).rounded() * step + minimum
        return snapped
    }
}

private struct AdvancedMicrophoneParameterSlider: NSViewRepresentable {
    let title: String
    let minimum: Double
    let maximum: Double
    let step: Double
    let value: Double
    let formatter: (Double) -> String
    let onChange: (Double) -> Void

    func makeNSView(context: Context) -> AdvancedMicrophoneParameterSliderNSView {
        AdvancedMicrophoneParameterSliderNSView(frame: .zero)
    }

    func updateNSView(_ nsView: AdvancedMicrophoneParameterSliderNSView, context: Context) {
        nsView.configure(
            title: title,
            minimum: minimum,
            maximum: maximum,
            step: step,
            value: value,
            formatter: formatter,
            onChange: onChange
        )
    }
}

struct AdvancedMicrophoneSettingsView: View {
    @ObservedObject var store: AdvancedMicrophoneSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("preferences.audio.advanced.device.label"))
                Text(store.deviceName)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        L10n.format("preferences.audio.advanced.device.accessibilityFormat", store.deviceName)
                    )
            }

            Button(
                store.isPreviewRunning
                ? L10n.text("preferences.audio.advanced.preview.stop")
                : L10n.text("preferences.audio.advanced.preview.start")
            ) {
                store.togglePreview()
            }
            .disabled(store.deviceInfo == nil)

            Toggle(
                L10n.text("preferences.audio.advanced.enabled"),
                isOn: Binding(
                    get: { store.advancedPreferences.isEnabled },
                    set: { store.updateAdvancedEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("preferences.audio.advanced.preset.label"))
                Picker(
                    "",
                    selection: Binding(
                        get: { store.advancedPreferences.preset },
                        set: { store.updatePreset($0) }
                    )
                ) {
                    ForEach(store.presetOptions) { option in
                        Text(option.title).tag(option.preset)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(L10n.text("preferences.audio.advanced.preset.label"))
                .disabled(store.advancedPreferences.isEnabled == false)
            }

            Toggle(
                L10n.text("preferences.audio.advanced.dynamic.enabled"),
                isOn: Binding(
                    get: { store.advancedPreferences.dynamicProcessorEnabled },
                    set: { store.updateDynamicProcessorEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .disabled(store.advancedPreferences.isEnabled == false)

            if store.advancedPreferences.dynamicProcessorEnabled && store.advancedPreferences.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.audio.advanced.dynamic.mode"))
                        Picker(
                            "",
                            selection: Binding(
                                get: { store.advancedPreferences.dynamicProcessorMode },
                                set: { store.updateDynamicProcessorMode($0) }
                            )
                        ) {
                            ForEach(DynamicProcessorMode.allCases, id: \.self) { mode in
                                Text(L10n.text(mode.localizationKey)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(L10n.text("preferences.audio.advanced.dynamic.mode"))
                    }

                    switch store.advancedPreferences.dynamicProcessorMode {
                    case .gate:
                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.gate.threshold.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateThresholdRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateThresholdRange.upperBound,
                            step: 1,
                            value: store.advancedPreferences.gate.thresholdDB,
                            formatter: InputAudioDeviceResolver.formatThresholdDB,
                            onChange: store.updateGateThresholdDB
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.gate.attack.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateAttackRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateAttackRange.upperBound,
                            step: 5,
                            value: store.advancedPreferences.gate.attackMilliseconds,
                            formatter: { "\(Int($0.rounded())) ms" },
                            onChange: store.updateGateAttackMilliseconds
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.gate.hold.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateHoldRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateHoldRange.upperBound,
                            step: 10,
                            value: store.advancedPreferences.gate.holdMilliseconds,
                            formatter: { "\(Int($0.rounded())) ms" },
                            onChange: store.updateGateHoldMilliseconds
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.gate.release.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateReleaseRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateReleaseRange.upperBound,
                            step: 10,
                            value: store.advancedPreferences.gate.releaseMilliseconds,
                            formatter: { "\(Int($0.rounded())) ms" },
                            onChange: store.updateGateReleaseMilliseconds
                        )

                    case .expander:
                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.expander.threshold.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateThresholdRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateThresholdRange.upperBound,
                            step: 1,
                            value: store.advancedPreferences.expander.thresholdDB,
                            formatter: InputAudioDeviceResolver.formatThresholdDB,
                            onChange: store.updateExpanderThresholdDB
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.expander.ratio.label"),
                            minimum: AdvancedInputAudioPreferences.expanderRatioRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.expanderRatioRange.upperBound,
                            step: 0.1,
                            value: store.advancedPreferences.expander.ratio,
                            formatter: InputAudioDeviceResolver.formatRatio,
                            onChange: store.updateExpanderRatio
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.expander.attack.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateAttackRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateAttackRange.upperBound,
                            step: 5,
                            value: store.advancedPreferences.expander.attackMilliseconds,
                            formatter: { "\(Int($0.rounded())) ms" },
                            onChange: store.updateExpanderAttackMilliseconds
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.dynamic.expander.release.label"),
                            minimum: AdvancedInputAudioPreferences.noiseGateReleaseRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.noiseGateReleaseRange.upperBound,
                            step: 10,
                            value: store.advancedPreferences.expander.releaseMilliseconds,
                            formatter: { "\(Int($0.rounded())) ms" },
                            onChange: store.updateExpanderReleaseMilliseconds
                        )
                    }
                }
            }

            Toggle(
                L10n.text("preferences.audio.advanced.limiter.enabled"),
                isOn: Binding(
                    get: { store.advancedPreferences.limiterEnabled },
                    set: { store.updateLimiterEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .disabled(store.advancedPreferences.isEnabled == false)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("preferences.audio.advanced.limiter.mode"))
                Picker(
                    "",
                    selection: Binding(
                        get: { store.advancedPreferences.limiterMode },
                        set: { store.updateLimiterMode($0) }
                    )
                ) {
                    ForEach(LimiterControlMode.allCases, id: \.self) { mode in
                        Text(L10n.text(mode.localizationKey)).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(L10n.text("preferences.audio.advanced.limiter.mode"))
                .disabled(store.advancedPreferences.isEnabled == false || store.advancedPreferences.limiterEnabled == false)
            }

            if store.advancedPreferences.limiterEnabled && store.advancedPreferences.isEnabled {
                switch store.advancedPreferences.limiterMode {
                case .preset:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.audio.advanced.limiter.preset"))
                        Picker(
                            "",
                            selection: Binding(
                                get: { store.advancedPreferences.limiterPreset },
                                set: { store.updateLimiterPreset($0) }
                            )
                        ) {
                            ForEach(LimiterPreset.allCases, id: \.self) { preset in
                                Text(L10n.text(preset.localizationKey)).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(L10n.text("preferences.audio.advanced.limiter.preset"))
                    }

                case .manual:
                    VStack(alignment: .leading, spacing: 10) {
                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.limiter.threshold.label"),
                            minimum: AdvancedInputAudioPreferences.manualThresholdRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.manualThresholdRange.upperBound,
                            step: 0.5,
                            value: store.advancedPreferences.limiterThresholdDB,
                            formatter: InputAudioDeviceResolver.formatThresholdDB,
                            onChange: store.updateLimiterThresholdDB
                        )

                        AdvancedMicrophoneParameterSlider(
                            title: L10n.text("preferences.audio.advanced.limiter.release.label"),
                            minimum: AdvancedInputAudioPreferences.manualReleaseRange.lowerBound,
                            maximum: AdvancedInputAudioPreferences.manualReleaseRange.upperBound,
                            step: 10,
                            value: store.advancedPreferences.limiterReleaseMilliseconds,
                            formatter: { "\(Int($0.rounded())) ms" },
                            onChange: store.updateLimiterReleaseMilliseconds
                        )
                    }
                }
            }

            if let feedbackMessage = store.feedbackMessage, feedbackMessage.isEmpty == false {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastErrorMessage = store.lastErrorMessage, lastErrorMessage.isEmpty == false {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            store.refresh()
        }
        .onDisappear {
            store.stopPreview()
        }
    }
}
