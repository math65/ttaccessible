//
//  UserAccountsWindowController.swift
//  ttaccessible
//

import AppKit

final class UserAccountsWindowController: NSWindowController {
    init(contentViewController: NSViewController) {
        let window = EscapeClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("accounts.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = contentViewController
        // Assigning contentViewController makes the window adopt that view's fittingSize
        // and discard contentRect — which is why several windows opened far smaller than
        // intended (Channel files at a third of its width, Preferences as a bare title
        // bar). Load the view, then restore the size actually asked for.
        _ = window.contentViewController?.view
        window.setContentSize(NSSize(width: 640, height: 420))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
