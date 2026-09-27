//
//  ChannelMixerView.swift
//  ttaccessible
//
//  The VISIBLE (sighted / mouse) rendering of the Channel Mixer: one row per user with
//  voice + media volume, pan, mute and solo. It renders the coordinator's published
//  snapshot and drives the same coordinator methods. VoiceOver does NOT use this — the
//  virtual-accessibility overlay (MixerVirtualAccessibility) is the screen-reader
//  interface — so the whole view is accessibilityHidden on macOS.
//

import SwiftUI

struct ChannelMixerView: View {
    @ObservedObject var coordinator: ChannelMixerCoordinator

    var body: some View {
        // Scrolls inside its own box: the strip count is unbounded (one per person in the
        // channel) while the window's height is not. Safe for VoiceOver — the whole view
        // is accessibilityHidden, so this scroll view never reaches the AX tree.
        ScrollView(.vertical) { content }
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The window titles its other sections (chat, history); this one had none.
            Text(L10n.text("mixer.area.label"))
                .font(.headline)
            if coordinator.displayStrips.isEmpty {
                Text(L10n.text("mixer.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(coordinator.displayStrips) { strip in
                    MixerStripRow(strip: strip, coordinator: coordinator)
                    if strip.id != coordinator.displayStrips.last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One labelled fader + read-out, used by the user strips.
private struct MixerFader: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let set: (Double) -> Void
    let display: (Double) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range)
            Text(display(value)).monospacedDigit().frame(width: 72, alignment: .trailing)
        }
        // A fader spanning the whole content pane looks like a progress bar, not a control.
        .frame(maxWidth: 620, alignment: .leading)
    }
}

private struct MixerStripRow: View {
    let strip: MixerDisplayStrip
    @ObservedObject var coordinator: ChannelMixerCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strip.name).font(.headline)

            fader(L10n.text("mixer.voice.label.short"), value: strip.voicePercent, range: 0...100,
                  set: { coordinator.setVoice(id: strip.id, percent: $0) },
                  display: Self.percent)
            fader(L10n.text("mixer.pan.label.short"), value: strip.voicePan, range: -1...1,
                  set: { coordinator.setVoicePan(id: strip.id, value: $0) },
                  display: { coordinator.voicePanDescription(strip.id, value: $0) })
            fader(L10n.text("mixer.media.label.short"), value: strip.mediaPercent, range: 0...100,
                  set: { coordinator.setMedia(id: strip.id, percent: $0) },
                  display: Self.percent)
            fader(L10n.text("mixer.mediapan.label.short"), value: strip.mediaPan, range: -1...1,
                  set: { coordinator.setMediaPan(id: strip.id, value: $0) },
                  display: { coordinator.mediaPanDescription(strip.id, value: $0) })

            HStack(spacing: 16) {
                Toggle(L10n.text("mixer.mute.label.short"), isOn: Binding(
                    get: { strip.muted }, set: { _ in coordinator.toggleMute(strip.id) }))
                Toggle(L10n.text("mixer.solo.action.solo"), isOn: Binding(
                    get: { strip.soloed }, set: { _ in coordinator.toggleSolo(strip.id) }))
            }
            .toggleStyle(.checkbox)
        }
    }

    static func percent(_ value: Double) -> String {
        L10n.format("mixer.value.percent", Int(value.rounded()))
    }

    private func fader(_ title: String, value: Double, range: ClosedRange<Double>,
                       set: @escaping (Double) -> Void, display: @escaping (Double) -> String) -> some View {
        MixerFader(title: title, value: value, range: range, set: set, display: display)
    }
}
