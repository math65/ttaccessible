//
//  ConnectedUsersWindowController.swift
//  ttaccessible
//

import AppKit

final class ConnectedUsersWindowController: NSWindowController {
    init(contentViewController: NSViewController) {
        let window = EscapeClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("connectedUsers.window.title")
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
