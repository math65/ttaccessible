//
//  ConnectedServerViewController+Mixer.swift
//  ttaccessible
//
//  Embeds the Channel Mixer as an inline section in the main connected-server window.
//  The visible heading + (placeholder) area sit alongside the invisible virtual-
//  accessibility overlay (channelMixerCoordinator.overlay), which is what VoiceOver
//  navigates: Mixer → per-user strip → controls. Fed by update(session:).
//

#if os(macOS)
import AppKit
import SwiftUI

extension ConnectedServerViewController {
    func buildChannelMixerSection() -> NSView {
        // The visible (sighted/mouse) SwiftUI strips, with the invisible virtual-
        // accessibility overlay laid over them — VoiceOver navigates the overlay, mouse
        // users see/use the SwiftUI. The overlay supplies the "Mixer / area" label+role.
        let hosting = NSHostingView(rootView: ChannelMixerView(coordinator: channelMixerCoordinator))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let overlay = channelMixerCoordinator.overlay
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Install the mixer keyboard model (Cmd+arrows master, arrows volume/pan, p/v/m/s).
        // The monitor only acts while VoiceOver is focused inside the mixer.
        channelMixerKeyboardController.start()
        return container
    }
}
#endif
