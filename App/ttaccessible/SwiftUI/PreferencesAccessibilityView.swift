//
//  PreferencesAccessibilityView.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import SwiftUI

struct PreferencesAccessibilityView: View {
    @ObservedObject var store: AccessibilityPreferencesStore

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    L10n.text("preferences.accessibility.channelAnnouncements"),
                    isOn: Binding(
                        get: { store.state.channelMessagesEnabled },
                        set: { store.updateVoiceOverChannelMessagesEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.accessibility.privateAnnouncements"),
                    isOn: Binding(
                        get: { store.state.privateMessagesEnabled },
                        set: { store.updateVoiceOverPrivateMessagesEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.accessibility.broadcastAnnouncements"),
                    isOn: Binding(
                        get: { store.state.broadcastMessagesEnabled },
                        set: { store.updateVoiceOverBroadcastMessagesEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.accessibility.historyAnnouncements"),
                    isOn: Binding(
                        get: { store.state.sessionHistoryEnabled },
                        set: { store.updateVoiceOverSessionHistoryEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Text(L10n.text("preferences.accessibility.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
