//
//  ChannelMixerCoordinator.swift
//  ttaccessible
//
//  Binds the ported virtual-accessibility engine (MixerVirtualAccessibility.swift) to
//  ttAccessible's per-user audio. Builds one MixerStripDescriptor per other user in the
//  current channel — voice volume %, media volume %, pan, mute — with live read/write
//  closures through TeamTalkConnectionController. The A11yVirtualGridOverlayView it owns
//  is embedded as a section in the main window; VoiceOver navigates Mixer → strip →
//  controls and adjusts via swipe (the engine's increment/decrement). Keyboard shortcuts
//  are added by ChannelMixerKeyboardController.
//

#if os(macOS)
import AppKit

@MainActor
final class ChannelMixerCoordinator {
    let overlay = A11yVirtualGridOverlayView(frame: .zero)
    private weak var controller: TeamTalkConnectionController?
    private var session: ConnectedServerSession?

    // Adjustment steps (VO swipe + keyboard arrows share these).
    private let volumeStep: Double = 2     // percent
    private let panStep: Double = 0.05     // -1...+1

    init(controller: TeamTalkConnectionController) {
        self.controller = controller
        overlay.configure(areaLabel: L10n.text("mixer.area.label")) { [weak self] in
            self?.buildDescriptors() ?? []
        }
    }

    func update(session: ConnectedServerSession) {
        self.session = session
        overlay.rebuildStrips()
    }

    /// The current user IDs the mixer shows (for the keyboard controller's routing).
    func currentUserIDs() -> [Int32] { buildDescriptors().map { $0.id } }

    // MARK: Descriptor building

    private func usersInChannel() -> [ConnectedServerUser] {
        guard let session else { return [] }
        let myID = session.currentUser?.id
        return (session.findChannelByID(session.currentChannelID)?.users ?? [])
            .filter { $0.id != myID && $0.id > 0 }
    }

    func user(for id: Int32) -> ConnectedServerUser? {
        usersInChannel().first { $0.id == id }
    }

    private func buildDescriptors() -> [MixerStripDescriptor] {
        usersInChannel().map { descriptor(for: $0) }
    }

    private func descriptor(for user: ConnectedServerUser) -> MixerStripDescriptor {
        let id = user.id
        return MixerStripDescriptor(
            id: id,
            label: { [weak self] in self?.stripLabel(for: id) },
            controls: [
                .slider(voiceConfig(id: id)),
                .slider(mediaConfig(id: id)),
                .slider(panConfig(id: id)),
                .toggle(muteConfig(id: id))
            ]
        )
    }

    private func stripLabel(for id: Int32) -> String? {
        guard let user = user(for: id) else { return nil }
        var parts = [user.displayName]
        parts.append(L10n.format("mixer.value.percent", Int(voicePercent(id).rounded())))
        if user.isMuted { parts.append(L10n.text("mixer.toggle.muted")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Live value access

    private func voicePercent(_ id: Int32) -> Double {
        guard let controller, let user = user(for: id) else { return 0 }
        let v = controller.userVolumeStore.volume(forUsername: user.username) ?? user.volumeVoice
        return Double(TeamTalkConnectionController.percentFromUserVolume(v))
    }

    private func mediaPercent(_ id: Int32) -> Double {
        guard let controller, let user = user(for: id) else { return 0 }
        let v = controller.userVolumeStore.mediaFileVolume(forUsername: user.username) ?? user.volumeMediaFile
        return Double(TeamTalkConnectionController.percentFromUserVolume(v))
    }

    private func panValue(_ id: Int32) -> Double {
        guard let controller, let user = user(for: id) else { return 0 }
        return Double(controller.userVolumeStore.pan(forUsername: user.username) ?? 0)
    }

    // MARK: Control configs

    private func voiceConfig(id: Int32) -> VirtualSliderConfig {
        VirtualSliderConfig(
            label: L10n.text("mixer.voice.label.short"),
            getValue: { [weak self] in self.map { Double(($0.voicePercent(id)).rounded()) } },
            getDisplayString: { v in L10n.format("mixer.value.percent", Int(v.rounded())) },
            setValue: { [weak self] v in self?.setVoice(id: id, percent: v) },
            incrementValue: { [volumeStep] v in min(100, v + volumeStep) },
            decrementValue: { [volumeStep] v in max(0, v - volumeStep) },
            minValue: 0, maxValue: 100, resetValue: 100
        )
    }

    private func mediaConfig(id: Int32) -> VirtualSliderConfig {
        VirtualSliderConfig(
            label: L10n.text("mixer.media.label.short"),
            getValue: { [weak self] in self.map { Double(($0.mediaPercent(id)).rounded()) } },
            getDisplayString: { v in L10n.format("mixer.value.percent", Int(v.rounded())) },
            setValue: { [weak self] v in self?.setMedia(id: id, percent: v) },
            incrementValue: { [volumeStep] v in min(100, v + volumeStep) },
            decrementValue: { [volumeStep] v in max(0, v - volumeStep) },
            minValue: 0, maxValue: 100, resetValue: 100
        )
    }

    private func panConfig(id: Int32) -> VirtualSliderConfig {
        VirtualSliderConfig(
            label: L10n.text("mixer.pan.label.short"),
            getValue: { [weak self] in self.map { $0.panValue(id) } },
            getDisplayString: { v in ChannelMixerCoordinator.panDescription(v) },
            setValue: { [weak self] v in self?.setPan(id: id, value: v) },
            incrementValue: { [panStep] v in min(1, v + panStep) },
            decrementValue: { [panStep] v in max(-1, v - panStep) },
            minValue: -1, maxValue: 1, resetValue: 0
        )
    }

    private func muteConfig(id: Int32) -> VirtualToggleConfig {
        VirtualToggleConfig(
            getLabel: { L10n.text("mixer.mute.label.short") },
            getState: { [weak self] in self?.user(for: id)?.isMuted },
            setState: { [weak self] muted in self?.controller?.muteUser(userID: id, mute: muted) },
            onAnnouncement: L10n.text("mixer.toggle.muted"),
            offAnnouncement: L10n.text("mixer.toggle.unmuted")
        )
    }

    // MARK: Apply (also used by the keyboard controller)

    func setVoice(id: Int32, percent: Double) {
        guard let controller, let user = user(for: id) else { return }
        let clamped = min(100, max(0, percent))
        controller.setUserVoiceVolume(userID: id, username: user.username,
                                      volume: TeamTalkConnectionController.userVolumeFromPercent(clamped))
    }

    func setMedia(id: Int32, percent: Double) {
        guard let controller, let user = user(for: id) else { return }
        let clamped = min(100, max(0, percent))
        controller.setUserMediaFileVolume(userID: id, username: user.username,
                                          volume: TeamTalkConnectionController.userVolumeFromPercent(clamped))
    }

    func setPan(id: Int32, value: Double) {
        guard let controller, let user = user(for: id) else { return }
        controller.setUserPan(userID: id, username: user.username, pan: Float(min(1, max(-1, value))))
    }

    func currentVoicePercent(_ id: Int32) -> Double { voicePercent(id) }
    func currentMediaPercent(_ id: Int32) -> Double { mediaPercent(id) }
    func currentPan(_ id: Int32) -> Double { panValue(id) }
    func isMuted(_ id: Int32) -> Bool { user(for: id)?.isMuted ?? false }
    func toggleMute(_ id: Int32) {
        guard let controller else { return }
        controller.muteUser(userID: id, mute: !isMuted(id))
    }

    static func panDescription(_ pan: Double) -> String {
        let pct = Int((abs(pan) * 100).rounded())
        if pct == 0 { return L10n.text("mixer.pan.center") }
        return pan < 0 ? L10n.format("mixer.pan.left", pct) : L10n.format("mixer.pan.right", pct)
    }
}
#endif
