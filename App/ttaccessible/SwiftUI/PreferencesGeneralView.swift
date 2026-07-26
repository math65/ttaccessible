//
//  PreferencesGeneralView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesGeneralView: View {
    @ObservedObject var store: ConnectionPreferencesStore
    @ObservedObject var rootStore: AppPreferencesStore
    @State private var nicknameDraft: String = ""
    @State private var statusMessageDraft: String = ""
    @State private var autoAwayStatusMessageDraft: String = ""
    @State private var nicknameCommitTask: Task<Void, Never>?
    @State private var statusCommitTask: Task<Void, Never>?
    @State private var autoAwayCommitTask: Task<Void, Never>?

    var body: some View {
        PreferencesPaneScrollView(accessibilityLabel: L10n.text("preferences.general.title")) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.general.defaultNickname"))
                        .accessibilityHidden(true)
                    TextField("", text: $nicknameDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("preferences.general.defaultNickname"))
                        .onChangeCompat(of: nicknameDraft) { newValue in
                            scheduleNicknameCommit(for: newValue)
                        }
                        .onSubmit { commitNicknameDraft() }

                    Text(L10n.text("preferences.general.defaultNickname.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.connection.defaultStatusMessage"))
                        .accessibilityHidden(true)
                    TextField("", text: $statusMessageDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("preferences.connection.defaultStatusMessage"))
                        .onChangeCompat(of: statusMessageDraft) { newValue in
                            scheduleStatusCommit(for: newValue)
                        }
                        .onSubmit { commitStatusDraft() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.connection.defaultGender"))
                        .accessibilityHidden(true)
                    Picker(
                        L10n.text("preferences.connection.defaultGender"),
                        selection: Binding(
                            get: { store.state.defaultGender },
                            set: { store.updateDefaultGender($0) }
                        )
                    ) {
                        ForEach(TeamTalkGender.allCases, id: \.self) { gender in
                            Text(L10n.text(gender.localizationKey)).tag(gender)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel(L10n.text("preferences.connection.defaultGender"))
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.connection.autoAwayTimeout"))
                        .accessibilityHidden(true)
                    HStack(alignment: .center, spacing: 8) {
                        TextField(
                            "",
                            value: Binding(
                                get: { store.state.autoAwayTimeoutMinutes },
                                set: { store.updateAutoAwayTimeoutMinutes($0) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .accessibilityLabel(L10n.text("preferences.connection.autoAwayTimeout.accessibility"))

                        Text(L10n.text("preferences.connection.autoAwayMinutesShort"))
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.text("preferences.connection.autoAwayHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.connection.autoAwayStatusMessage"))
                        .accessibilityHidden(true)
                    TextField("", text: $autoAwayStatusMessageDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("preferences.connection.autoAwayStatusMessage"))
                        .onChangeCompat(of: autoAwayStatusMessageDraft) { newValue in
                            scheduleAutoAwayCommit(for: newValue)
                        }
                        .onSubmit { commitAutoAwayDraft() }
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { rootStore.preferences.useRelativeTimestamps },
                    set: { rootStore.updateUseRelativeTimestamps($0) }
                )) {
                    Text(L10n.text("preferences.general.relativeTimestamps"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.general.relativeTimestamps"))

                Toggle(isOn: Binding(
                    get: { rootStore.preferences.prefersAutomaticTeamTalkConfigDetection },
                    set: { rootStore.updatePrefersAutomaticTeamTalkConfigDetection($0) }
                )) {
                    Text(L10n.text("preferences.general.autoDetectImport"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.general.autoDetectImport"))

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.general.language.label"))
                        .accessibilityHidden(true)
                    Picker(
                        L10n.text("preferences.general.language.label"),
                        selection: Binding(
                            get: { rootStore.preferences.languagePreference },
                            set: { rootStore.updateLanguagePreference($0) }
                        )
                    ) {
                        ForEach(AppLanguagePreference.allCases, id: \.self) { languagePreference in
                            Text(L10n.text(languagePreference.localizationKey)).tag(languagePreference)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel(L10n.text("preferences.general.language.label"))

                    Text(L10n.text("preferences.general.language.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text(L10n.text("preferences.updates.section"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Toggle(isOn: Binding(
                    get: { rootStore.preferences.autoCheckForUpdates },
                    set: { rootStore.updateAutoCheckForUpdates($0) }
                )) {
                    Text(L10n.text("preferences.updates.autoCheck"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.updates.autoCheck"))

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { rootStore.preferences.includeBetaUpdates },
                        set: { rootStore.updateIncludeBetaUpdates($0) }
                    )) {
                        Text(L10n.text("preferences.updates.includeBeta"))
                            .accessibilityHidden(true)
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.text("preferences.updates.includeBeta"))

                    Text(L10n.text("preferences.updates.includeBeta.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            nicknameDraft = store.state.defaultNickname
            statusMessageDraft = store.state.defaultStatusMessage
            autoAwayStatusMessageDraft = store.state.autoAwayStatusMessage
        }
        .onChangeCompat(of: store.state.defaultNickname) { newValue in
            if nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { nicknameDraft = newValue }
        }
        .onChangeCompat(of: store.state.defaultStatusMessage) { newValue in
            if newValue != statusMessageDraft { statusMessageDraft = newValue }
        }
        .onChangeCompat(of: store.state.autoAwayStatusMessage) { newValue in
            if newValue != autoAwayStatusMessageDraft { autoAwayStatusMessageDraft = newValue }
        }
        .onDisappear {
            commitNicknameDraft()
            commitStatusDraft()
            commitAutoAwayDraft()
        }
    }

    private func scheduleNicknameCommit(for value: String) {
        nicknameCommitTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        nicknameCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            store.updateDefaultNickname(trimmed)
        }
    }

    private func scheduleStatusCommit(for value: String) {
        statusCommitTask?.cancel()
        statusCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            store.updateDefaultStatusMessage(value)
        }
    }

    private func scheduleAutoAwayCommit(for value: String) {
        autoAwayCommitTask?.cancel()
        autoAwayCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            store.updateAutoAwayStatusMessage(value)
        }
    }

    private func commitNicknameDraft() {
        nicknameCommitTask?.cancel()
        commitNickname(nicknameDraft)
    }

    private func commitStatusDraft() {
        statusCommitTask?.cancel()
        store.updateDefaultStatusMessage(statusMessageDraft)
    }

    private func commitAutoAwayDraft() {
        autoAwayCommitTask?.cancel()
        store.updateAutoAwayStatusMessage(autoAwayStatusMessageDraft)
    }

    private func commitNickname(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nicknameDraft = store.state.defaultNickname
            return
        }
        store.updateDefaultNickname(trimmed)
    }
}
