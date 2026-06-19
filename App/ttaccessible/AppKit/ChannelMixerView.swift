//
//  ChannelMixerView.swift
//  ttaccessible
//
//  A live "mixing desk" for the current channel: one strip per other user, each with
//  voice volume, media-file volume, continuous pan, and mute — all applied live and
//  persisted per-username. Volume rides the SDK layer (percent scale, like the
//  per-user Adjust Volume dialog); continuous pan drives our own OutputAudioRenderEngine
//  (independent of the SDK's discrete Left/Right checkboxes, which are left untouched).
//

import Combine
import SwiftUI

// MARK: - Model

@MainActor
final class ChannelMixerModel: ObservableObject {
    struct Strip: Identifiable, Equatable {
        let id: Int32                 // userID
        let username: String
        let displayName: String
        var voicePercent: Double      // 0...100
        var mediaPercent: Double      // 0...100
        var pan: Double               // -1...+1
        var voiceMuted: Bool
        var mediaMuted: Bool
    }

    @Published private(set) var strips: [Strip] = []
    private weak var controller: TeamTalkConnectionController?
    // Optimistic mute intent awaiting SDK/session confirmation. Lets the toggle flip
    // immediately and announce ONCE in VoiceOver, instead of flickering when an
    // unrelated session update arrives before the mute round-trips.
    private var pendingVoiceMute: [Int32: Bool] = [:]
    private var pendingMediaMute: [Int32: Bool] = [:]

    init(controller: TeamTalkConnectionController) {
        self.controller = controller
        if let session = controller.sessionSnapshot {
            update(session: session)
        }
    }

    /// Rebuild the strips from a session snapshot. Fed by AppDelegate's session
    /// forwarding so the desk stays live as users join/leave or mute changes.
    func update(session: ConnectedServerSession) {
        guard let controller else { return }
        let myID = session.currentUser?.id
        let users = session.findChannelByID(session.currentChannelID)?.users ?? []
        let store = controller.userVolumeStore
        let next: [Strip] = users
            .filter { $0.id != myID && $0.id > 0 }
            .map { user in
                let voice = store.volume(forUsername: user.username) ?? user.volumeVoice
                let media = store.mediaFileVolume(forUsername: user.username) ?? user.volumeMediaFile
                let pan = store.pan(forUsername: user.username) ?? 0
                return Strip(
                    id: user.id,
                    username: user.username,
                    displayName: user.displayName,
                    voicePercent: Double(TeamTalkConnectionController.percentFromUserVolume(voice)),
                    mediaPercent: Double(TeamTalkConnectionController.percentFromUserVolume(media)),
                    pan: Double(pan),
                    voiceMuted: reconcile(&pendingVoiceMute, user.id, session: user.isMuted),
                    mediaMuted: reconcile(&pendingMediaMute, user.id, session: user.isMediaFileMuted)
                )
            }
        if next != strips { strips = next }
    }

    /// Keep the optimistic mute value until the session confirms it, then defer to the
    /// session (so external mute changes still show). Avoids the toggle flickering.
    private func reconcile(_ pending: inout [Int32: Bool], _ id: Int32, session: Bool) -> Bool {
        if let intent = pending[id] {
            if intent == session { pending[id] = nil; return session }
            return intent
        }
        return session
    }

    // MARK: Apply (live + persisted)

    func setVoicePercent(_ percent: Double, for strip: Strip) {
        let volume = TeamTalkConnectionController.userVolumeFromPercent(percent)
        controller?.setUserVoiceVolume(userID: strip.id, username: strip.username, volume: volume)
        mutate(strip.id) { $0.voicePercent = percent }
    }

    func setMediaPercent(_ percent: Double, for strip: Strip) {
        let volume = TeamTalkConnectionController.userVolumeFromPercent(percent)
        controller?.setUserMediaFileVolume(userID: strip.id, username: strip.username, volume: volume)
        mutate(strip.id) { $0.mediaPercent = percent }
    }

    func setPan(_ pan: Double, for strip: Strip) {
        controller?.setUserPan(userID: strip.id, username: strip.username, pan: Float(pan))
        mutate(strip.id) { $0.pan = pan }
    }

    func toggleVoiceMute(_ strip: Strip) {
        let muted = !strip.voiceMuted
        pendingVoiceMute[strip.id] = muted
        controller?.muteUser(userID: strip.id, mute: muted)
        mutate(strip.id) { $0.voiceMuted = muted }
    }

    func toggleMediaMute(_ strip: Strip) {
        let muted = !strip.mediaMuted
        pendingMediaMute[strip.id] = muted
        controller?.muteUserMediaFile(userID: strip.id, mute: muted)
        mutate(strip.id) { $0.mediaMuted = muted }
    }

    private func mutate(_ id: Int32, _ change: (inout Strip) -> Void) {
        guard let i = strips.firstIndex(where: { $0.id == id }) else { return }
        change(&strips[i])
    }
}

// MARK: - Mixer window content

struct ChannelMixerView: View {
    @ObservedObject var model: ChannelMixerModel

    var body: some View {
        Group {
            if model.strips.isEmpty {
                Text(L10n.text("mixer.empty"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.strips) { strip in
                            ChannelStripView(strip: strip, model: model)
                            Divider()
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 340, minHeight: 200)
    }
}

// MARK: - One user's strip

private struct ChannelStripView: View {
    let strip: ChannelMixerModel.Strip
    @ObservedObject var model: ChannelMixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strip.displayName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            volumeRow(
                titleKey: "mixer.voice.label",
                percent: strip.voicePercent,
                set: { model.setVoicePercent($0, for: strip) }
            )
            volumeRow(
                titleKey: "mixer.media.label",
                percent: strip.mediaPercent,
                set: { model.setMediaPercent($0, for: strip) }
            )
            panRow

            HStack(spacing: 16) {
                Toggle(L10n.format("mixer.mute.voice", strip.displayName), isOn: Binding(
                    get: { strip.voiceMuted },
                    set: { _ in model.toggleVoiceMute(strip) }
                ))
                Toggle(L10n.format("mixer.mute.media", strip.displayName), isOn: Binding(
                    get: { strip.mediaMuted },
                    set: { _ in model.toggleMediaMute(strip) }
                ))
            }
            .toggleStyle(.checkbox)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(stripAccessibilityLabel)
    }

    private func volumeRow(titleKey: String, percent: Double, set: @escaping (Double) -> Void) -> some View {
        let label = L10n.format(titleKey, strip.displayName)
        return HStack(spacing: 8) {
            Slider(
                value: Binding(get: { percent }, set: { set($0.rounded()) }),
                in: 0...100, step: 1
            )
            .accessibilityLabel(label)
            .accessibilityValue(L10n.format("mixer.value.percent", Int(percent.rounded())))
            Text(L10n.format("mixer.value.percent", Int(percent.rounded())))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var panRow: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(get: { strip.pan }, set: { model.setPan(($0 * 20).rounded() / 20, for: strip) }),
                in: -1...1
            )
            .accessibilityLabel(L10n.format("mixer.pan.label", strip.displayName))
            .accessibilityValue(Self.panDescription(strip.pan))
            Text(Self.panDescription(strip.pan))
                .frame(width: 64, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var stripAccessibilityLabel: String {
        var parts = [strip.displayName]
        if strip.voiceMuted { parts.append(L10n.text("mixer.muted.voice")) }
        if strip.mediaMuted { parts.append(L10n.text("mixer.muted.media")) }
        return parts.joined(separator: ", ")
    }

    static func panDescription(_ pan: Double) -> String {
        let pct = Int((abs(pan) * 100).rounded())
        if pct == 0 { return L10n.text("mixer.pan.center") }
        return pan < 0 ? L10n.format("mixer.pan.left", pct) : L10n.format("mixer.pan.right", pct)
    }
}
