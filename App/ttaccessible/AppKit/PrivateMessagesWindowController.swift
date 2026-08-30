//
//  PrivateMessagesWindowController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

final class PrivateMessagesWindowController: NSWindowController, NSWindowDelegate {
    var onUserClose: (() -> Void)?

    init(contentViewController: NSViewController) {
        let window = EscapeClosableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("privateMessages.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = contentViewController
        // Assigning contentViewController makes the window adopt that view's fittingSize
        // and discard contentRect — which is why several windows opened far smaller than
        // intended (Channel files at a third of its width, Preferences as a bare title
        // bar). Load the view, then restore the size actually asked for.
        _ = window.contentViewController?.view
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        onUserClose?()
    }
}
