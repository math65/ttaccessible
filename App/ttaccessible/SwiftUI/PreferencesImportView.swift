//
//  PreferencesImportView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesImportView: View {
    @ObservedObject var store: AppPreferencesStore

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(
                    L10n.text("preferences.general.autoDetectImport"),
                    isOn: Binding(
                        get: { store.preferences.prefersAutomaticTeamTalkConfigDetection },
                        set: { store.updatePrefersAutomaticTeamTalkConfigDetection($0) }
                    )
                )
                .toggleStyle(.switch)
            }
        }
    }
}
