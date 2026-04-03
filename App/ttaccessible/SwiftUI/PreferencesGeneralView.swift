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
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.general.defaultNickname"))
                    TextField("", text: $nicknameDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("preferences.general.defaultNickname"))
                        .onChange(of: nicknameDraft) { _, newValue in
                            scheduleNicknameCommit(for: newValue)
                        }
                        .onSubmit { commitNicknameDraft() }

                    Text(L10n.text("preferences.general.defaultNickname.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.connection.defaultStatusMessage"))
                    TextField("", text: $statusMessageDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("preferences.connection.defaultStatusMessage"))
                        .onChange(of: statusMessageDraft) { _, newValue in
                            scheduleStatusCommit(for: newValue)
                        }
                        .onSubmit { commitStatusDraft() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.connection.defaultGender"))
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
                    TextField("", text: $autoAwayStatusMessageDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("preferences.connection.autoAwayStatusMessage"))
                        .onChange(of: autoAwayStatusMessageDraft) { _, newValue in
                            scheduleAutoAwayCommit(for: newValue)
                        }
                        .onSubmit { commitAutoAwayDraft() }
                }

                Divider()

                Toggle(
                    L10n.text("preferences.general.relativeTimestamps"),
                    isOn: Binding(
                        get: { rootStore.preferences.useRelativeTimestamps },
                        set: { rootStore.updateUseRelativeTimestamps($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.general.autoDetectImport"),
                    isOn: Binding(
                        get: { rootStore.preferences.prefersAutomaticTeamTalkConfigDetection },
                        set: { rootStore.updatePrefersAutomaticTeamTalkConfigDetection($0) }
                    )
                )
                .toggleStyle(.switch)
            }
        }
        .onAppear {
            nicknameDraft = store.state.defaultNickname
            statusMessageDraft = store.state.defaultStatusMessage
            autoAwayStatusMessageDraft = store.state.autoAwayStatusMessage
        }
        .onChange(of: store.state.defaultNickname) { _, newValue in
            if nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { nicknameDraft = newValue }
        }
        .onChange(of: store.state.defaultStatusMessage) { _, newValue in
            if newValue != statusMessageDraft { statusMessageDraft = newValue }
        }
        .onChange(of: store.state.autoAwayStatusMessage) { _, newValue in
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
        nicknameCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            commitNickname(value)
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
