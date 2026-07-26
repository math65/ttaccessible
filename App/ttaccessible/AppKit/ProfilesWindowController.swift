//
//  ProfilesWindowController.swift
//  ttaccessible
//

import AppKit

final class ProfilesWindowController: NSWindowController {
    init(contentViewController: NSViewController) {
        let window = EscapeClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("profiles.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = contentViewController
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
