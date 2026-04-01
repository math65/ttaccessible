//
//  PreferencesRecordingView.swift
//  ttaccessible
//

import SwiftUI

struct PreferencesRecordingView: View {
    @ObservedObject var store: RecordingPreferencesStore

    var body: some View {
        PreferencesPaneScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("preferences.recording.folder.label"))
                    .font(.headline)

                HStack {
                    Text(store.state.folderDisplayPath ?? L10n.text("preferences.recording.folder.none"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(store.state.folderDisplayPath == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        guard let window = NSApp.keyWindow else { return }
                        store.chooseFolder(from: window)
                    } label: {
                        Text(L10n.text("preferences.recording.folder.choose"))
                    }

                    if store.state.folderBookmark != nil {
                        Button {
                            store.clearFolder()
                        } label: {
                            Text(L10n.text("preferences.recording.folder.clear"))
                        }
                    }
                }

                Divider()

                Text(L10n.text("preferences.recording.mode.label"))
                    .font(.headline)

                Picker(
                    L10n.text("preferences.recording.mode.label"),
                    selection: Binding(
                        get: { store.state.recordingMode },
                        set: { store.updateRecordingMode($0) }
                    )
                ) {
                    ForEach(RecordingPreferencesStore.modeOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()

                Divider()

                Text(L10n.text("preferences.recording.format.label"))
                    .font(.headline)

                Picker(
                    L10n.text("preferences.recording.format.label"),
                    selection: Binding(
                        get: { store.state.audioFileFormat },
                        set: { store.updateAudioFileFormat($0) }
                    )
                ) {
                    ForEach(RecordingPreferencesStore.formatOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()

                Text(L10n.text("preferences.recording.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
