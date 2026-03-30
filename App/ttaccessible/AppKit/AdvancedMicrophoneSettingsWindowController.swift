//
//  AdvancedMicrophoneSettingsWindowController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import SwiftUI

@MainActor
final class AdvancedMicrophoneSettingsWindowController: NSWindowController {
    private let settingsStore: AdvancedMicrophoneSettingsStore

    init(settingsStore: AdvancedMicrophoneSettingsStore) {
        self.settingsStore = settingsStore

        let contentViewController = NSHostingController(
            rootView: AdvancedMicrophoneSettingsView(store: settingsStore)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("preferences.audio.advanced.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = contentViewController

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showAdvancedSettings() {
        settingsStore.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AdvancedMicrophoneSettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settingsStore.stopPreview()
    }
}
