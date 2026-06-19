//
//  ChannelMixerWindowController.swift
//  ttaccessible
//
//  Hosts the SwiftUI Channel Mixer in an NSWindow. AppDelegate forwards session
//  updates to `update(session:)` so the desk stays live while open.
//

import AppKit
import SwiftUI

@MainActor
final class ChannelMixerWindowController: NSWindowController {
    let model: ChannelMixerModel

    init(connectionController: TeamTalkConnectionController) {
        self.model = ChannelMixerModel(controller: connectionController)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("mixer.window.title")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ChannelMixerWindow")
        window.center()

        super.init(window: window)

        window.contentViewController = NSHostingController(rootView: ChannelMixerView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(session: ConnectedServerSession) {
        model.update(session: session)
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
