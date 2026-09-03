//
//  PreferencesGeneralView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesGeneralView: View {
    /// The three free-text fields, so a store echo can tell whether the field it
    /// is about to refresh is the one being typed into.
    private enum Field {
        case nickname
        case statusMessage
        case autoAwayStatusMessage
    }

    @ObservedObject var store: ConnectionPreferencesStore
    @ObservedObject var rootStore: AppPreferencesStore
    @FocusState private var focusedField: Field?
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
                        .focused($focusedField, equals: .nickname)
                        .accessibilityLabel(L10n.text("preferences.general.defaultNickname"))
                        .onChangeCompat(of: nicknameDraft) { _ in
                            scheduleNicknameCommit()
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
                        .focused($focusedField, equals: .statusMessage)
                        .accessibilityLabel(L10n.text("preferences.connection.defaultStatusMessage"))
                        .onChangeCompat(of: statusMessageDraft) { _ in
                            scheduleStatusCommit()
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
                        .focused($focusedField, equals: .autoAwayStatusMessage)
                        .accessibilityLabel(L10n.text("preferences.connection.autoAwayStatusMessage"))
                        .onChangeCompat(of: autoAwayStatusMessageDraft) { _ in
                            scheduleAutoAwayCommit()
                        }
                        .onSubmit { commitAutoAwayDraft() }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.general.userNameDisplayStyle.label"))
                        .accessibilityHidden(true)
                    Picker(
                        L10n.text("preferences.general.userNameDisplayStyle.label"),
                        selection: Binding(
                            get: { rootStore.preferences.userNameDisplayStyle },
                            set: { rootStore.updateUserNameDisplayStyle($0) }
                        )
                    ) {
                        ForEach(AppPreferences.UserNameDisplayStyle.allCases, id: \.self) { style in
                            Text(L10n.text(style.localizationKey)).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel(L10n.text("preferences.general.userNameDisplayStyle.label"))

                    Text(L10n.text("preferences.general.userNameDisplayStyle.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
        // These mirror a value changed elsewhere (⌘F5 renames the nickname while
        // this pane is open). They must never touch the field being typed into:
        // the store trims what it stores, so echoing it back mid-word deletes
        // the space the user just typed — VoiceOver duly announces the deletion,
        // and the next word runs into the previous one.
        .onChangeCompat(of: store.state.defaultNickname) { newValue in
            guard focusedField != .nickname else { return }
            if newValue != nicknameDraft { nicknameDraft = newValue }
        }
        .onChangeCompat(of: store.state.defaultStatusMessage) { newValue in
            guard focusedField != .statusMessage else { return }
            if newValue != statusMessageDraft { statusMessageDraft = newValue }
        }
        .onChangeCompat(of: store.state.autoAwayStatusMessage) { newValue in
            guard focusedField != .autoAwayStatusMessage else { return }
            if newValue != autoAwayStatusMessageDraft { autoAwayStatusMessageDraft = newValue }
        }
        .onDisappear {
            commitNicknameDraft()
            commitStatusDraft()
            commitAutoAwayDraft()
        }
    }

    // The debounced commits read the draft when they fire rather than capturing
    // it when they are scheduled: a keystroke landing between the two would
    // otherwise write a value that is already one character out of date.
    private func scheduleNicknameCommit() {
        nicknameCommitTask?.cancel()
        nicknameCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return }
            store.updateDefaultNickname(trimmed)
        }
    }

    private func scheduleStatusCommit() {
        statusCommitTask?.cancel()
        statusCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            store.updateDefaultStatusMessage(statusMessageDraft)
        }
    }

    private func scheduleAutoAwayCommit() {
        autoAwayCommitTask?.cancel()
        autoAwayCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else { return }
            store.updateAutoAwayStatusMessage(autoAwayStatusMessageDraft)
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
