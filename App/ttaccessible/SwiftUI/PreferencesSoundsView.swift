//
//  PreferencesSoundsView.swift
//  ttaccessible
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesSoundsView: View {
    @ObservedObject var store: NotificationsPreferencesStore
    @State private var availablePacks = SoundPlayer.availablePacks

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

                HStack(spacing: 12) {
                    Picker(
                        L10n.text("preferences.notifications.soundPack"),
                        selection: Binding(
                            get: { store.state.soundPack },
                            set: { store.updateSoundPack($0) }
                        )
                    ) {
                        ForEach(availablePacks, id: \.self) { pack in
                            Text(pack).tag(pack)
                        }
                    }

                    if SoundPlayer.canDeletePack(store.state.soundPack) {
                        Button(L10n.format("preferences.sounds.deletePack", store.state.soundPack)) {
                            deleteSelectedPack()
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button(L10n.text("preferences.sounds.newPack")) {
                        createSoundPack()
                    }
                    Button(L10n.text("preferences.sounds.requiredFiles")) {
                        showRequiredSoundFiles()
                    }
                    Button(L10n.text("preferences.sounds.revealPacksFolder")) {
                        revealSoundPacksFolder()
                    }
                }

                if SoundPlayer.isCustomPack(store.state.soundPack) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("preferences.sounds.editPack.title"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(NotificationSound.allCases, id: \.self) { sound in
                            HStack(spacing: 10) {
                                Text(L10n.text(sound.localizationKey))
                                    .frame(minWidth: 220, alignment: .leading)

                                Text(customSoundStatus(for: sound))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 120, alignment: .leading)

                                Button(L10n.text("preferences.sounds.chooseSound")) {
                                    chooseCustomSound(sound)
                                }

                                Button(L10n.text("preferences.sounds.resetSound")) {
                                    removeCustomSound(sound)
                                }
                                .disabled(!SoundPlayer.hasCustomSound(sound, in: store.state.soundPack))
                            }
                        }
                    }

                    Divider()
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
        .onAppear {
            refreshAvailablePacks()
        }
    }

    private func refreshAvailablePacks() {
        availablePacks = SoundPlayer.availablePacks
        if !availablePacks.contains(store.state.soundPack) {
            store.updateSoundPack(availablePacks.first ?? SoundPlayer.defaultPack)
        }
    }

    private func createSoundPack() {
        guard let sourceURL = promptForSoundPackFolder() else { return }
        do {
            let packName = try SoundPlayer.importCustomPack(from: sourceURL)
            refreshAvailablePacks()
            store.updateSoundPack(packName)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func promptForSoundPackFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.text("preferences.sounds.newPack.panelTitle")
        panel.message = L10n.text("preferences.sounds.newPack.panelMessage")
        panel.prompt = L10n.text("preferences.sounds.newPack.panelPrompt")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return url
    }

    private func deleteSelectedPack() {
        let packName = store.state.soundPack
        guard SoundPlayer.canDeletePack(packName) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("preferences.sounds.deletePack.panelTitle", packName)
        alert.informativeText = L10n.text("preferences.sounds.deletePack.panelMessage")
        alert.addButton(withTitle: L10n.text("preferences.sounds.deletePack.panelDelete"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try SoundPlayer.deletePack(named: packName)
            refreshAvailablePacks()
            store.updateSoundPack(availablePacks.first ?? SoundPlayer.defaultPack)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func revealSoundPacksFolder() {
        let directory = SoundPlayer.ensureCustomSoundPacksDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([directory])
        refreshAvailablePacks()
    }

    private func showRequiredSoundFiles() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("preferences.sounds.requiredFiles.panelTitle")
        alert.informativeText = L10n.text("preferences.sounds.requiredFiles.panelMessage")
        alert.addButton(withTitle: L10n.text("common.ok"))

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.string = requiredSoundFilesText()
        textView.setAccessibilityLabel(L10n.text("preferences.sounds.requiredFiles.accessibilityLabel"))

        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        alert.runModal()
    }

    private func requiredSoundFilesText() -> String {
        let header = [
            L10n.text("preferences.sounds.requiredFiles.fileNameHeader"),
            L10n.text("preferences.sounds.requiredFiles.eventHeader")
        ].joined(separator: "\t")
        let rows = NotificationSound.allCases.map { sound in
            [
                sound.soundPackFileName,
                L10n.text(sound.localizationKey)
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func chooseCustomSound(_ sound: NotificationSound) {
        let panel = NSOpenPanel()
        panel.title = L10n.format("preferences.sounds.chooseSound.panelTitle", L10n.text(sound.localizationKey))
        panel.prompt = L10n.text("preferences.sounds.chooseSound.panelPrompt")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio, .audio]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SoundPlayer.setCustomSound(sound, in: store.state.soundPack, from: url)
            store.updateSoundPack(store.state.soundPack)
            refreshAvailablePacks()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func removeCustomSound(_ sound: NotificationSound) {
        do {
            try SoundPlayer.removeCustomSound(sound, from: store.state.soundPack)
            store.updateSoundPack(store.state.soundPack)
            refreshAvailablePacks()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func customSoundStatus(for sound: NotificationSound) -> String {
        SoundPlayer.hasCustomSound(sound, in: store.state.soundPack)
            ? L10n.text("preferences.sounds.soundStatus.custom")
            : L10n.text("preferences.sounds.soundStatus.default")
    }
}
