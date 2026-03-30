//
//  SavedServerEditorWindowController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import SwiftUI

final class SavedServerEditorWindowController: NSWindowController {
    private final class Coordinator: NSObject, NSWindowDelegate {
        var result: SavedServerDraft?

        func windowWillClose(_ notification: Notification) {
            NSApp.stopModal()
        }
    }

    private let coordinator = Coordinator()

    init(mode: SavedServerEditorMode, draft: SavedServerDraft, parentWindow: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = mode.title
        window.isReleasedWhenClosed = false
        window.center()

        if let parentFrame = parentWindow?.frame {
            let origin = NSPoint(
                x: parentFrame.midX - (window.frame.width / 2),
                y: parentFrame.midY - (window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
        }

        super.init(window: window)

        let rootView = SavedServerFormView(
            mode: mode,
            draft: draft,
            onCancel: { [weak self] in
                self?.closeWithResult(nil)
            },
            onSave: { [weak self] result in
                self?.closeWithResult(result)
            }
        )

        window.delegate = coordinator
        window.contentViewController = NSHostingController(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func runModal() -> SavedServerDraft? {
        guard let window else {
            return nil
        }

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        return coordinator.result
    }

    private func closeWithResult(_ result: SavedServerDraft?) {
        coordinator.result = result
        close()
    }
}
