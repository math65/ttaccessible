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

extension ConnectedServerViewController {
    func buildChannelMixerSection() -> NSView {
        let heading = NSTextField(labelWithString: L10n.text("mixer.area.label"))
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.setAccessibilityElement(false)   // VoiceOver uses the overlay's group label

        let overlay = channelMixerCoordinator.overlay
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView(views: [heading, overlay])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            overlay.widthAnchor.constraint(equalTo: container.widthAnchor),
            overlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        return container
    }
}
#endif
