//
//  PreferencesNotificationsView.swift
//  ttaccessible
//

import AppKit
import SwiftUI

final class NotificationParameterSliderNSView: NSView {
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
        setAccessibilityMinValue(minimum)
        setAccessibilityMaxValue(maximum)
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
        setAccessibilityValue(value)
        setAccessibilityValueDescription(text)
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

    private func snap(_ rawValue: Double) -> Double {
        guard step > 0 else { return rawValue }
        let steps = ((rawValue - minimum) / step).rounded()
        return minimum + (steps * step)
    }

    private func clamp(_ rawValue: Double) -> Double {
        min(max(rawValue, minimum), maximum)
    }
}

struct NotificationParameterSlider: NSViewRepresentable {
    let title: String
    let minimum: Double
    let maximum: Double
    let step: Double
    let value: Double
    let formatter: (Double) -> String
    let onChange: (Double) -> Void

    func makeNSView(context: Context) -> NotificationParameterSliderNSView {
        NotificationParameterSliderNSView(frame: .zero)
    }

    func updateNSView(_ nsView: NotificationParameterSliderNSView, context: Context) {
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

struct PreferencesNotificationsView: View {
    @ObservedObject var store: NotificationsPreferencesStore
    @State private var ttsPreviewService = MacOSTextToSpeechAnnouncementService()

    private var selectedVoiceLabel: String {
        store.state.voiceOptions.first(where: { $0.id == store.state.macOSTTSVoiceIdentifier })?.displayName
            ?? MacOSTextToSpeechVoiceOption.systemDefault.displayName
    }

    private var groupedVoiceOptions: [(language: String, regular: [MacOSTextToSpeechVoiceOption], eloquence: [MacOSTextToSpeechVoiceOption])] {
        let groups = Dictionary(grouping: store.state.voiceOptions.filter { $0.id != nil }) { option in
            option.languageName ?? ""
        }

        return groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { language in
                let options = groups[language] ?? []
                return (
                    language: language,
                    regular: options.filter { $0.isEloquence == false },
                    eloquence: options.filter { $0.isEloquence }
                )
            }
    }

    private func rateFormatter(_ value: Double) -> String {
        let multiplier = value / MacOSTextToSpeechAnnouncementService.defaultSpeechRate
        return String(format: L10n.text("preferences.notifications.tts.rate.value"), multiplier)
    }

    private func volumeFormatter(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return L10n.format("preferences.notifications.tts.volume.value", "\(percent)")
    }

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(
                    L10n.text("preferences.general.soundNotifications"),
                    isOn: Binding(
                        get: { store.state.soundNotificationsEnabled },
                        set: { store.updateSoundNotificationsEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Picker(
                    L10n.text("preferences.notifications.soundPack"),
                    selection: Binding(
                        get: { store.state.soundPack },
                        set: { store.updateSoundPack($0) }
                    )
                ) {
                    ForEach(SoundPlayer.availablePacks, id: \.self) { pack in
                        Text(pack).tag(pack)
                    }
                }

                Divider()

                Text(L10n.text("preferences.notifications.soundEvents.title"))
                    .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(NotificationSound.allCases, id: \.self) { sound in
                        Toggle(
                            L10n.text(sound.localizationKey),
                            isOn: Binding(
                                get: { store.isSoundEventEnabled(sound) },
                                set: { store.setSoundEventEnabled(sound, enabled: $0) }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("preferences.notifications.backgroundAnnouncements.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(BackgroundMessageAnnouncementType.allCases) { type in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text(type.titleLocalizationKey))
                            Picker(
                                L10n.text(type.titleLocalizationKey),
                                selection: Binding(
                                    get: { store.backgroundAnnouncementMode(for: type) },
                                    set: { store.updateBackgroundAnnouncementMode($0, for: type) }
                                )
                            ) {
                                ForEach(BackgroundMessageAnnouncementMode.allCases) { mode in
                                    Text(L10n.text(mode.localizationKey)).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("preferences.notifications.tts.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.notifications.tts.voice"))
                        Menu(selectedVoiceLabel) {
                            Button(MacOSTextToSpeechVoiceOption.systemDefault.displayName) {
                                store.updateMacOSTTSVoiceIdentifier(nil)
                            }
                            Divider()

                            ForEach(groupedVoiceOptions, id: \.language) { group in
                                Menu(group.language) {
                                    ForEach(group.regular) { option in
                                        Button(option.name) {
                                            store.updateMacOSTTSVoiceIdentifier(option.id)
                                        }
                                    }

                                    if group.eloquence.isEmpty == false {
                                        if group.regular.isEmpty == false {
                                            Divider()
                                        }
                                        Menu("Eloquence") {
                                            ForEach(group.eloquence) { option in
                                                Button(option.name) {
                                                    store.updateMacOSTTSVoiceIdentifier(option.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    NotificationParameterSlider(
                        title: L10n.text("preferences.notifications.tts.rate"),
                        minimum: MacOSTextToSpeechAnnouncementService.minimumSpeechRate,
                        maximum: MacOSTextToSpeechAnnouncementService.maximumSpeechRate,
                        step: 0.025,
                        value: store.state.macOSTTSSpeechRate,
                        formatter: rateFormatter,
                        onChange: store.updateMacOSTTSSpeechRate
                    )
                    .frame(height: 24)

                    NotificationParameterSlider(
                        title: L10n.text("preferences.notifications.tts.volume"),
                        minimum: 0,
                        maximum: 1,
                        step: 0.05,
                        value: store.state.macOSTTSVolume,
                        formatter: volumeFormatter,
                        onChange: store.updateMacOSTTSVolume
                    )
                    .frame(height: 24)

                    Button(L10n.text("preferences.notifications.tts.test")) {
                        ttsPreviewService.announce(
                            L10n.text("preferences.notifications.tts.testPhrase"),
                            voiceIdentifier: store.state.macOSTTSVoiceIdentifier,
                            speechRate: store.state.macOSTTSSpeechRate,
                            volume: store.state.macOSTTSVolume
                        )
                    }
                }

                if store.state.isVoiceOptionsLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task {
            store.prepareIfNeeded()
        }
    }
}
