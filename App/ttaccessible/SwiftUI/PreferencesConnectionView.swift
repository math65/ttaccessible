//
//  PreferencesConnectionView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesConnectionView: View {
    @ObservedObject var store: ConnectionPreferencesStore

    var body: some View {
        PreferencesPaneScrollView(accessibilityLabel: L10n.text("preferences.connection.title")) {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: Binding(
                    get: { store.state.autoJoinRootChannel },
                    set: { store.updateAutoJoinRootChannel($0) }
                )) {
                    Text(L10n.text("preferences.general.autoJoinRootChannel"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.general.autoJoinRootChannel"))

                Toggle(isOn: Binding(
                    get: { store.state.autoReconnect },
                    set: { store.updateAutoReconnect($0) }
                )) {
                    Text(L10n.text("preferences.general.autoReconnect"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.general.autoReconnect"))

                Toggle(isOn: Binding(
                    get: { store.state.rejoinLastChannelOnReconnect },
                    set: { store.updateRejoinLastChannelOnReconnect($0) }
                )) {
                    Text(L10n.text("preferences.general.rejoinLastChannelOnReconnect"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.general.rejoinLastChannelOnReconnect"))

                Toggle(isOn: Binding(
                    get: { store.state.connectToLastServerOnLaunch },
                    set: { store.updateConnectToLastServerOnLaunch($0) }
                )) {
                    Text(L10n.text("preferences.general.connectToLastServerOnLaunch"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.general.connectToLastServerOnLaunch"))

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { store.state.startWithMicrophoneMuted },
                        set: { store.updateStartWithMicrophoneMuted($0) }
                    )) {
                        Text(L10n.text("preferences.connection.startWithMicrophoneMuted"))
                            .accessibilityHidden(true)
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.text("preferences.connection.startWithMicrophoneMuted"))

                    Text(L10n.text("preferences.connection.startWithMicrophoneMuted.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: Binding(
                    get: { store.state.skipKickConfirmation },
                    set: { store.updateSkipKickConfirmation($0) }
                )) {
                    Text(L10n.text("preferences.connection.skipKickConfirmation"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.connection.skipKickConfirmation"))

                Toggle(isOn: Binding(
                    get: { store.state.adaptiveJitterBuffer },
                    set: { store.updateAdaptiveJitterBuffer($0) }
                )) {
                    Text(L10n.text("preferences.connection.adaptiveJitterBuffer"))
                        .accessibilityHidden(true)
                }
                .toggleStyle(.switch)
                .accessibilityLabel(L10n.text("preferences.connection.adaptiveJitterBuffer"))

                Picker(
                    L10n.text("preferences.connection.channelSortMode"),
                    selection: Binding(
                        get: { store.state.channelSortMode },
                        set: { store.updateChannelSortMode($0) }
                    )
                ) {
                    Text(L10n.text("preferences.connection.channelSortMode.name"))
                        .tag(AppPreferences.ChannelSortMode.name)
                    Text(L10n.text("preferences.connection.channelSortMode.userCount"))
                        .tag(AppPreferences.ChannelSortMode.userCount)
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("preferences.general.userNameDisplayStyle.label"))
                        .accessibilityHidden(true)
                    Picker(
                        L10n.text("preferences.general.userNameDisplayStyle.label"),
                        selection: Binding(
                            get: { store.state.userNameDisplayStyle },
                            set: { store.updateUserNameDisplayStyle($0) }
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

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("preferences.connection.subscriptions.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(UserSubscriptionOption.regularCases, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { store.isSubscriptionEnabledByDefault(option) },
                            set: { enabled in store.updateSubscriptionEnabledByDefault(enabled, for: option) }
                        )) {
                            Text(L10n.text(option.preferencesKey))
                                .accessibilityHidden(true)
                        }
                        .toggleStyle(.switch)
                        .accessibilityLabel(L10n.text(option.preferencesKey))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("preferences.connection.intercepts.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(UserSubscriptionOption.interceptCases, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { store.isSubscriptionEnabledByDefault(option) },
                            set: { enabled in store.updateSubscriptionEnabledByDefault(enabled, for: option) }
                        )) {
                            Text(L10n.text(option.preferencesKey))
                                .accessibilityHidden(true)
                        }
                        .toggleStyle(.switch)
                        .accessibilityLabel(L10n.text(option.preferencesKey))
                    }
                }
            }
        }
    }
}
