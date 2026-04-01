//
//  PreferencesAnnouncementsView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesAnnouncementsView: View {
    @ObservedObject var notificationsStore: NotificationsPreferencesStore
    @ObservedObject var accessibilityStore: AccessibilityPreferencesStore
    @State private var ttsPreviewService = MacOSTextToSpeechAnnouncementService()

    private var selectedVoiceLabel: String {
        notificationsStore.state.voiceOptions.first(where: { $0.id == notificationsStore.state.macOSTTSVoiceIdentifier })?.displayName
            ?? MacOSTextToSpeechVoiceOption.systemDefault.displayName
    }

    private var groupedVoiceOptions: [(language: String, regular: [MacOSTextToSpeechVoiceOption], eloquence: [MacOSTextToSpeechVoiceOption])] {
        let groups = Dictionary(grouping: notificationsStore.state.voiceOptions.filter { $0.id != nil }) { option in
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
                                    get: { notificationsStore.backgroundAnnouncementMode(for: type) },
                                    set: { notificationsStore.updateBackgroundAnnouncementMode($0, for: type) }
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

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("preferences.notifications.tts.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.notifications.tts.voice"))
                        Menu(selectedVoiceLabel) {
                            Button(MacOSTextToSpeechVoiceOption.systemDefault.displayName) {
                                notificationsStore.updateMacOSTTSVoiceIdentifier(nil)
                            }
                            Divider()

                            ForEach(groupedVoiceOptions, id: \.language) { group in
                                Menu(group.language) {
                                    ForEach(group.regular) { option in
                                        Button(option.name) {
                                            notificationsStore.updateMacOSTTSVoiceIdentifier(option.id)
                                        }
                                    }

                                    if group.eloquence.isEmpty == false {
                                        if group.regular.isEmpty == false {
                                            Divider()
                                        }
                                        Menu("Eloquence") {
                                            ForEach(group.eloquence) { option in
                                                Button(option.name) {
                                                    notificationsStore.updateMacOSTTSVoiceIdentifier(option.id)
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
                        value: notificationsStore.state.macOSTTSSpeechRate,
                        formatter: rateFormatter,
                        onChange: notificationsStore.updateMacOSTTSSpeechRate
                    )
                    .frame(height: 24)

                    NotificationParameterSlider(
                        title: L10n.text("preferences.notifications.tts.volume"),
                        minimum: 0,
                        maximum: 1,
                        step: 0.05,
                        value: notificationsStore.state.macOSTTSVolume,
                        formatter: volumeFormatter,
                        onChange: notificationsStore.updateMacOSTTSVolume
                    )
                    .frame(height: 24)

                    Button {
                        ttsPreviewService.announce(
                            L10n.text("preferences.notifications.tts.testPhrase"),
                            voiceIdentifier: notificationsStore.state.macOSTTSVoiceIdentifier,
                            speechRate: notificationsStore.state.macOSTTSSpeechRate,
                            volume: notificationsStore.state.macOSTTSVolume
                        )
                    } label: {
                        Text(L10n.text("preferences.notifications.tts.test"))
                    }
                }

                if notificationsStore.state.isVoiceOptionsLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("preferences.announcements.voiceover.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Toggle(
                        L10n.text("preferences.accessibility.channelAnnouncements"),
                        isOn: Binding(
                            get: { accessibilityStore.state.channelMessagesEnabled },
                            set: { accessibilityStore.updateVoiceOverChannelMessagesEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Toggle(
                        L10n.text("preferences.accessibility.privateAnnouncements"),
                        isOn: Binding(
                            get: { accessibilityStore.state.privateMessagesEnabled },
                            set: { accessibilityStore.updateVoiceOverPrivateMessagesEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Toggle(
                        L10n.text("preferences.accessibility.broadcastAnnouncements"),
                        isOn: Binding(
                            get: { accessibilityStore.state.broadcastMessagesEnabled },
                            set: { accessibilityStore.updateVoiceOverBroadcastMessagesEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Toggle(
                        L10n.text("preferences.accessibility.historyAnnouncements"),
                        isOn: Binding(
                            get: { accessibilityStore.state.sessionHistoryEnabled },
                            set: { accessibilityStore.updateVoiceOverSessionHistoryEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Text(L10n.text("preferences.accessibility.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            notificationsStore.prepareIfNeeded()
        }
    }
}
