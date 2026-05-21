//
//  MediaStreamingPlayerWindowController.swift
//  ttaccessible
//

import AppKit

final class MediaStreamingPlayerWindowController: NSWindowController, NSWindowDelegate {
    var onCloseRequested: (() -> Void)?

    init(contentViewController: NSViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("mediaPlayer.window.title")
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequested?()
        return false
    }
}
