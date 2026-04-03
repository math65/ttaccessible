//
//  PreferencesAudioView.swift
//  ttaccessible

import SwiftUI

struct PreferencesAudioView: View {
    private let defaultDeviceTag = "__system_default__"

    @ObservedObject var store: AudioPreferencesStore

    @State private var selectedInputID = "__system_default__"
    @State private var selectedOutputID = "__system_default__"

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.audio.outputDevice"))
                    Picker("", selection: $selectedOutputID) {
                        Text(L10n.text("preferences.audio.systemDefault")).tag(defaultDeviceTag)
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

                // Microphone settings (AEC, channel preset, preview).
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("preferences.audio.advanced.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Toggle(
                        L10n.text("preferences.audio.advanced.echoCancellation"),
                        isOn: Binding(
                            get: { store.advancedPreferences.echoCancellationEnabled },
                            set: { store.updateEchoCancellationEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Text(L10n.text("preferences.audio.advanced.echoCancellation.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
