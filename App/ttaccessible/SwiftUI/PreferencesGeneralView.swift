//
//  PreferencesGeneralView.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import SwiftUI

struct PreferencesGeneralView: View {
    @ObservedObject var store: AppPreferencesStore
    var onBroadcastSubscriptionPreferenceChanged: ((Bool) -> Void)? = nil
    @State private var nicknameDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("preferences.general.defaultNickname"))
                TextField("", text: $nicknameDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.text("preferences.general.defaultNickname"))
                    .onChange(of: nicknameDraft) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty == false {
                            store.updateDefaultNickname(trimmed)
                        }
                    }
                    .onSubmit {
                        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            nicknameDraft = store.preferences.defaultNickname
                        }
                    }

                Text(L10n.text("preferences.general.defaultNickname.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                L10n.text("preferences.general.autoDetectImport"),
                isOn: Binding(
                    get: { store.preferences.prefersAutomaticTeamTalkConfigDetection },
                    set: { store.updatePrefersAutomaticTeamTalkConfigDetection($0) }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                L10n.text("preferences.general.autoJoinRootChannel"),
                isOn: Binding(
                    get: { store.preferences.autoJoinRootChannel },
                    set: { store.updateAutoJoinRootChannel($0) }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                L10n.text("preferences.general.autoReconnect"),
                isOn: Binding(
                    get: { store.preferences.autoReconnect },
                    set: { store.updateAutoReconnect($0) }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                L10n.text("preferences.general.rejoinLastChannelOnReconnect"),
                isOn: Binding(
                    get: { store.preferences.rejoinLastChannelOnReconnect },
                    set: { store.updateRejoinLastChannelOnReconnect($0) }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                L10n.text("preferences.general.subscribeBroadcastMessages"),
                isOn: Binding(
                    get: { store.preferences.subscribeBroadcastMessages },
                    set: {
                        store.updateSubscribeBroadcastMessages($0)
                        onBroadcastSubscriptionPreferenceChanged?($0)
                    }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                L10n.text("preferences.general.soundNotifications"),
                isOn: Binding(
                    get: { store.preferences.soundNotificationsEnabled },
                    set: { store.updateSoundNotificationsEnabled($0) }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                L10n.text("preferences.general.microphoneEnabledByDefault"),
                isOn: Binding(
                    get: { store.preferences.microphoneEnabledByDefault },
                    set: { store.updateMicrophoneEnabledByDefault($0) }
                )
            )
            .toggleStyle(.switch)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            nicknameDraft = store.preferences.defaultNickname
        }
        .onChange(of: store.preferences.defaultNickname) { _, newValue in
            if nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nicknameDraft = newValue
            }
        }
    }

}
