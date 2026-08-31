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
        // Assigning contentViewController makes the window adopt that view's fittingSize
        // and discard contentRect — which is why several windows opened far smaller than
        // intended (Channel files at a third of its width, Preferences as a bare title
        // bar). Load the view, then restore the size actually asked for.
        _ = window.contentViewController?.view
        window.setContentSize(NSSize(width: 560, height: 380))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
