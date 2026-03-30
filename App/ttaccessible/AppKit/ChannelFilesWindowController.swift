//
//  ChannelFilesWindowController.swift
//  ttaccessible
//

import AppKit

final class ChannelFilesWindowController: NSWindowController {
    init(contentViewController: NSViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("files.window.title")
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
