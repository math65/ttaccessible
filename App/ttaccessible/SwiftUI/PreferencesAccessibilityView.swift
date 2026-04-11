//
//  PreferencesAccessibilityView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
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

                DisclosureGroup(L10n.text("preferences.accessibility.historyAnnouncements")) {
                    HStack(spacing: 12) {
                        Button(L10n.text("preferences.historyEvents.enableAll")) {
                            store.enableAllSessionHistoryKinds()
                        }
                        Button(L10n.text("preferences.historyEvents.disableAll")) {
                            store.disableAllSessionHistoryKinds()
                        }
                    }
                    .padding(.bottom, 4)

                    ForEach(SessionHistoryEntry.Kind.announcementGroups) { group in
                        Text(L10n.text(group.localizationKey))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)

                        ForEach(group.kinds, id: \.self) { kind in
                            Toggle(
                                L10n.text(kind.localizationKey),
                                isOn: Binding(
                                    get: { store.isSessionHistoryKindEnabled(kind) },
                                    set: { store.updateSessionHistoryKindEnabled(kind, $0) }
                                )
                            )
                            .toggleStyle(.switch)
                        }
                    }
                }

                Text(L10n.text("preferences.accessibility.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
