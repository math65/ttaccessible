//
//  EscapeClosableWindow.swift
//  ttaccessible
//

import AppKit

/// Auxiliary window that closes when the user presses Escape, so dismissing a
/// panel never requires Cmd+W. Escape only reaches the window when nothing
/// closer in the responder chain consumed it (e.g. a text field being edited
/// cancels its own editing first), and `performClose` still honors
/// `windowShouldClose`, so editors keep their say. The MAIN window is
/// deliberately not this class — a stray Escape must never close the session
/// window.
final class EscapeClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
