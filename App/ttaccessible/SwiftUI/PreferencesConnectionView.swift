//
//  PreferencesConnectionView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesConnectionView: View {
    @ObservedObject var store: ConnectionPreferencesStore

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(
                    L10n.text("preferences.general.autoJoinRootChannel"),
                    isOn: Binding(
                        get: { store.state.autoJoinRootChannel },
                        set: { store.updateAutoJoinRootChannel($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.general.autoReconnect"),
                    isOn: Binding(
                        get: { store.state.autoReconnect },
                        set: { store.updateAutoReconnect($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.general.rejoinLastChannelOnReconnect"),
                    isOn: Binding(
                        get: { store.state.rejoinLastChannelOnReconnect },
                        set: { store.updateRejoinLastChannelOnReconnect($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.connection.skipKickConfirmation"),
                    isOn: Binding(
                        get: { store.state.skipKickConfirmation },
                        set: { store.updateSkipKickConfirmation($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    L10n.text("preferences.connection.adaptiveJitterBuffer"),
                    isOn: Binding(
                        get: { store.state.adaptiveJitterBuffer },
                        set: { store.updateAdaptiveJitterBuffer($0) }
                    )
                )
                .toggleStyle(.switch)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("preferences.connection.subscriptions.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(UserSubscriptionOption.regularCases, id: \.self) { option in
                        Toggle(
                            L10n.text(option.preferencesKey),
                            isOn: Binding(
                                get: { store.isSubscriptionEnabledByDefault(option) },
                                set: { enabled in store.updateSubscriptionEnabledByDefault(enabled, for: option) }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("preferences.connection.intercepts.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(UserSubscriptionOption.interceptCases, id: \.self) { option in
                        Toggle(
                            L10n.text(option.preferencesKey),
                            isOn: Binding(
                                get: { store.isSubscriptionEnabledByDefault(option) },
                                set: { enabled in store.updateSubscriptionEnabledByDefault(enabled, for: option) }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }
            }
        }
    }
}
