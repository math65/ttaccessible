//
//  PreferencesAudioView.swift
//  ttaccessible

import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreferencesAudioView: View {
    private let defaultDeviceTag = "__system_default__"
    private let noOutputDeviceTag = AudioDevicePreference.noOutputSentinelID

    @ObservedObject var store: AudioPreferencesStore

    @State private var selectedInputID = "__system_default__"
    @State private var selectedOutputID = "__system_default__"
    @State private var pushToTalkShortcutConfigured: Bool = KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil

    var body: some View {
        PreferencesPaneScrollView(accessibilityLabel: L10n.text("preferences.audio.title")) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.audio.outputDevice"))
                        .accessibilityHidden(true)
                    Picker("", selection: $selectedOutputID) {
                        Text(L10n.text("preferences.audio.systemDefault")).tag(defaultDeviceTag)
                        Text(L10n.text("preferences.audio.noOutput")).tag(noOutputDeviceTag)
                        ForEach(store.state.catalog.outputDevices) { device in
                            Text(device.displayName).tag(device.persistentID)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(L10n.text("preferences.audio.outputDevice"))
                    .onChange(of: selectedOutputID) { _, _ in
                        persistAndApply()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.audio.inputDevice"))
                        .accessibilityHidden(true)
                    Picker("", selection: $selectedInputID) {
                        Text(L10n.text("preferences.audio.systemDefault")).tag(defaultDeviceTag)
                        ForEach(store.state.catalog.inputDevices) { device in
                            Text(device.displayName).tag(device.persistentID)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(L10n.text("preferences.audio.inputDevice"))
                    .onChange(of: selectedInputID) { _, _ in
                        persistAndApply()
                    }
                }

                Button(L10n.text("preferences.audio.refreshDevices")) {
                    store.restartSoundSystem()
                }
                .disabled(store.state.isCatalogLoading)

                // Microphone settings (AEC, channel preset, preview).
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("preferences.audio.advanced.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Toggle(isOn: Binding(
                        get: { store.advancedPreferences.echoCancellationEnabled },
                        set: { store.updateEchoCancellationEnabled($0) }
                    )) {
                        Text(L10n.text("preferences.audio.advanced.echoCancellation"))
                            .accessibilityHidden(true)
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.text("preferences.audio.advanced.echoCancellation"))

                    Text(L10n.text("preferences.audio.advanced.echoCancellation.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.audio.advanced.preset.label"))
                            .accessibilityHidden(true)
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
                    }

                    Button(
                        store.isPreviewRunning
                        ? L10n.text("preferences.audio.advanced.preview.stop")
                        : L10n.text("preferences.audio.advanced.preview.start")
                    ) {
                        store.togglePreview()
                    }
                    .disabled(store.state.catalog.inputDevices.isEmpty && store.advancedDeviceInfo == nil)
                }

                pushToTalkSection

                if let feedbackMessage = store.state.advancedFeedbackMessage, feedbackMessage.isEmpty == false {
                    Text(feedbackMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastErrorMessage = store.state.lastErrorMessage, lastErrorMessage.isEmpty == false {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let advancedErrorMessage = store.state.advancedErrorMessage, advancedErrorMessage.isEmpty == false {
                    Text(advancedErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if store.state.isCatalogLoading && store.state.catalog == .empty {
                    Text(L10n.text("preferences.audio.refresh"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("preferences.audio.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            store.prepareIfNeeded()
            syncSelectionFromStore()
        }
        .onChange(of: store.state.preferredInputDevice) { _, _ in
            syncSelectionFromStore()
        }
        .onChange(of: store.state.preferredOutputDevice) { _, _ in
            syncSelectionFromStore()
        }
        .onChange(of: store.state.catalog) { _, _ in
            syncSelectionFromStore()
        }
        .onDisappear {
            store.stopPreview()
            store.suspendWhenHidden()
        }
    }

    private func persistAndApply() {
        store.updateSelectedDevices(inputID: selectedInputID, outputID: selectedOutputID)
    }

    @ViewBuilder
    private var pushToTalkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("preferences.audio.pushToTalk.section"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("preferences.audio.microphoneMode.label"))
                    .accessibilityHidden(true)
                Picker(
                    "",
                    selection: Binding(
                        get: { store.state.microphoneMode },
                        set: { store.updateMicrophoneMode($0) }
                    )
                ) {
                    Text(L10n.text("preferences.audio.microphoneMode.alwaysOn"))
                        .tag(AppPreferences.MicrophoneMode.alwaysOn)
                    Text(L10n.text("preferences.audio.microphoneMode.pushToTalk"))
                        .tag(AppPreferences.MicrophoneMode.pushToTalk)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .accessibilityLabel(L10n.text("preferences.audio.microphoneMode.label"))
            }

            if store.state.microphoneMode == .pushToTalk {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.audio.pushToTalk.key.label"))
                        .accessibilityHidden(true)
                    KeyboardShortcuts.Recorder(for: .pushToTalk)
                        .accessibilityLabel(L10n.text("preferences.audio.pushToTalk.key.label"))
                }

                if !pushToTalkShortcutConfigured {
                    Text(L10n.text("preferences.audio.pushToTalk.warning.noShortcut"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(isOn: Binding(
                    get: { store.state.pushToTalkBeepEnabled },
                    set: { store.updatePushToTalkBeepEnabled($0) }
                )) {
                    Text(L10n.text("preferences.audio.pushToTalk.beep.label"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.audio.pushToTalk.beep.label"))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let configured = KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
            if configured != pushToTalkShortcutConfigured {
                pushToTalkShortcutConfigured = configured
            }
        }
    }

    private func syncSelectionFromStore() {
        selectedOutputID = store.selectionID(
            for: store.state.preferredOutputDevice,
            devices: store.state.catalog.outputDevices
        )
        selectedInputID = store.selectionID(
            for: store.state.preferredInputDevice,
            devices: store.state.catalog.inputDevices
        )
    }
}
