//
//  PreferencesAudioView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesAudioView: View {
    private let defaultDeviceTag = "__system_default__"

    @ObservedObject var store: AudioPreferencesStore
    let onOpenAdvancedMicrophoneSettings: () -> Void

    @State private var selectedInputID = "__system_default__"
    @State private var selectedOutputID = "__system_default__"

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(
                    L10n.text("preferences.general.microphoneEnabledByDefault"),
                    isOn: Binding(
                        get: { store.state.microphoneEnabledByDefault },
                        set: { store.updateMicrophoneEnabledByDefault($0) }
                    )
                )
                .toggleStyle(.switch)

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

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("preferences.audio.advanced.title"))
                    Text(store.state.advancedSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(store.state.advancedSummaryText)

                    if let feedbackMessage = store.state.advancedFeedbackMessage, feedbackMessage.isEmpty == false {
                        Text(feedbackMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(L10n.text("preferences.audio.advanced.open")) {
                        onOpenAdvancedMicrophoneSettings()
                    }
                }

                HStack {
                    Button(L10n.text("preferences.audio.refresh")) {
                        store.refreshDevices()
                    }

                    if store.state.isCatalogLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(L10n.text("preferences.audio.refresh"))
                    }
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
