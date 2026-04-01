//
//  PreferencesSoundsView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesSoundsView: View {
    @ObservedObject var store: NotificationsPreferencesStore

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(
                    L10n.text("preferences.general.soundNotifications"),
                    isOn: Binding(
                        get: { store.state.soundNotificationsEnabled },
                        set: { store.updateSoundNotificationsEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Picker(
                    L10n.text("preferences.notifications.soundPack"),
                    selection: Binding(
                        get: { store.state.soundPack },
                        set: { store.updateSoundPack($0) }
                    )
                ) {
                    ForEach(SoundPlayer.availablePacks, id: \.self) { pack in
                        Text(pack).tag(pack)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("preferences.notifications.soundEvents.title"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(NotificationSound.allCases, id: \.self) { sound in
                        Toggle(
                            L10n.text(sound.localizationKey),
                            isOn: Binding(
                                get: { store.isSoundEventEnabled(sound) },
                                set: { store.setSoundEventEnabled(sound, enabled: $0) }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                }
            }
        }
    }
}
