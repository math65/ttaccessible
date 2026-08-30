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
import Combine

/// One user's row for the VISIBLE (sighted) mixer rendering. VoiceOver uses the separate
/// virtual-accessibility overlay, not this.
struct MixerDisplayStrip: Identifiable, Equatable {
    let id: Int32
    let name: String
    var voicePercent: Double
    var mediaPercent: Double
    var voicePan: Double
    var mediaPan: Double
    var muted: Bool
    var soloed: Bool
}

/// One global level's row in the VISIBLE mixer, mirroring MixerDisplayStrip. The General
/// strip exists for the eye as well as for VoiceOver: these levels live nowhere else in
/// the window's UI, so a sighted user must be able to reach them here.
struct MixerDisplayGain: Identifiable, Equatable {
    let id: Int          // position in globalGains
    let label: String
    var percent: Double
}

/// One global level exposed by the mixer's "General" strip — output, media bus,
/// microphone, sound effects. Reads and writes go straight to the session/preferences
/// through the window's applyXGain methods, which own normalisation, persistence and the
/// push to the audio layer. Values are in dB (-24…+24, 0 = unity), shown as 0–100 %.
struct MixerGlobalGain {
    let label: String
    let get: @MainActor @Sendable () -> Double
    let set: @MainActor @Sendable (Double) -> Void
}

@MainActor
final class ChannelMixerCoordinator: ObservableObject {
    /// Published snapshot driving the on-screen SwiftUI strips (accessibilityHidden on mac).
    @Published private(set) var displayStrips: [MixerDisplayStrip] = []
    /// The General strip, for the visible rendering.
    @Published private(set) var displayGlobalGains: [MixerDisplayGain] = []
    let overlay = A11yVirtualGridOverlayView(frame: .zero)
    private weak var controller: TeamTalkConnectionController?
    private var session: ConnectedServerSession?

    // Caches so the slider value the user sees is the EXACT value they set — the
    // percent→SDK-volume→percent round-trip is lossy and would otherwise make the
    // slider snap/jump while adjusting. muteCache is optimistic mute intent awaiting
    // session confirmation (so the toggle is responsive and announces once).
    private var voicePctCache: [Int32: Double] = [:]
    private var mediaPctCache: [Int32: Double] = [:]
    private var voicePanCache: [Int32: Double] = [:]
    private var mediaPanCache: [Int32: Double] = [:]
    private var muteCache: [Int32: Bool] = [:]
    // Solo: while any user is soloed, every NON-soloed user is muted in OUR engine
    // (independent of their persistent SDK mute). Lets you isolate one or more people.
    private var soloed: Set<Int32> = []
    private var lastKnownIDs: [Int32] = []
    private var soloWasActive = false

    /// Reserved strip id for the "General" strip — negative, so it can never collide
    /// with a user id (positive) or a media source key (positive, high bit set).
    static let generalStripID: Int32 = -100
    /// The global levels shown by the General strip, injected by the window (empty
    /// until then, in which case the strip is simply not built).
    var globalGains: [MixerGlobalGain] = [] {
        didSet { overlay.rebuildStrips(); refreshGlobalGains() }
    }
    /// Which of those levels the keyboard is aimed at. The General strip is navigated as
    /// ONE element — VoiceOver's cursor stays on the group, exactly as it does on a user
    /// strip — so left/right picks the level and up/down moves it. Its four controls stay
    /// in the tree for whoever does step into them.
    private var selectedGlobalGain = 0

    // Adjustment steps (VO swipe + keyboard arrows share these).
    private let volumeStep: Double = 2     // percent
    private let panStep: Double = 0.05     // -1...+1

    init(controller: TeamTalkConnectionController) {
        self.controller = controller
        overlay.configure(areaLabel: L10n.text("mixer.area.label"),
                          areaRoleDescription: L10n.text("mixer.area.roleDescription")) { [weak self] in
            self?.buildDescriptors() ?? []
        }
    }

    func update(session: ConnectedServerSession) {
        self.session = session
        // Reconcile optimistic mute intent: once the session agrees, drop the override.
        let ids = Set(usersInChannel().map { $0.id })
        for (id, intent) in muteCache where !ids.contains(id) || isMutedFromSession(id) == intent {
            muteCache[id] = nil
        }
        // Prune value caches for users no longer present.
        voicePctCache = voicePctCache.filter { ids.contains($0.key) }
        mediaPctCache = mediaPctCache.filter { ids.contains($0.key) }
        voicePanCache = voicePanCache.filter { ids.contains($0.key) }
        mediaPanCache = mediaPanCache.filter { ids.contains($0.key) }
        // Solo: drop leavers; re-apply engine mutes when the roster changed while solo is
        // (or was just) active, so a joiner gets muted and a departed soloist clears.
        soloed = soloed.intersection(ids)
        let idList = Array(ids)
        let nowActive = !soloed.isEmpty
        if Set(lastKnownIDs) != ids && (nowActive || soloWasActive) {
            reapplySolo()
        }
        soloWasActive = nowActive
        lastKnownIDs = idList
        overlay.rebuildStrips()
        refreshDisplay()
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
        let users = usersInChannel().map { descriptor(for: $0) }
        guard !globalGains.isEmpty else { return users }
        return [generalDescriptor()] + users
    }

    /// The "General" strip: the levels that belong to nobody in particular — output,
    /// media bus, microphone, sound effects. Rendered both ways, like the user strips:
    /// here for VoiceOver, and in ChannelMixerView for the eye.
    private func generalDescriptor() -> MixerStripDescriptor {
        MixerStripDescriptor(
            id: Self.generalStripID,
            label: { [weak self] in self?.generalStripLabel() },
            controls: globalGains.map { .slider(globalGainConfig($0)) }
        )
    }

    /// "General, Output volume" — which level the arrows are armed on, and NOT its value:
    /// VoiceOver re-reads the focused element when its label changes, so a value in here
    /// would be spoken a second time, late, after every single arrow press.
    private func generalStripLabel() -> String {
        let general = L10n.text("mixer.general.label")
        guard let gain = selectedGain else { return general }
        return [general, gain.label].joined(separator: ", ")
    }

    /// dB in, percent out — the window sliders' own mapping, so both routes speak the
    /// same number for the same level (50 % = unity).
    private func globalGainConfig(_ gain: MixerGlobalGain) -> VirtualSliderConfig {
        VirtualSliderConfig(
            label: gain.label,
            getValue: { AudioGainControlView.percent(forGainDB: gain.get()) },
            getDisplayString: { v in L10n.format("mixer.value.percent", Int(v.rounded())) },
            setValue: { v in gain.set(AudioGainControlView.gainDB(forPercent: v)) },
            incrementValue: { [volumeStep] v in min(100, v + volumeStep) },
            decrementValue: { [volumeStep] v in max(0, v - volumeStep) },
            minValue: 0, maxValue: 100, resetValue: 50
        )
    }

    /// One step on the General strip's level at `index` (its position in the strip).
    /// Routed through the very config the overlay exposes, so the arrow keys and the
    /// VoiceOver increment/decrement gestures can never drift apart.
    /// `step` overrides the mixer's own 2 % step — Cmd+arrows have moved these levels by
    /// 1 % since long before the mixer existed, and that is not something to change here.
    func nudgeGlobalGain(_ index: Int, up: Bool, step: Double? = nil) -> String? {
        guard globalGains.indices.contains(index) else { return nil }
        selectedGlobalGain = index
        let config = globalGainConfig(globalGains[index])
        guard let current = config.getValue() else { return nil }
        let delta = step ?? volumeStep
        let value = min(100, max(0, current + (up ? delta : -delta)))
        config.setValue(value)
        refreshGlobalGains()
        return config.getDisplayString(value)
    }

    /// Up/Down on the General strip itself: move the selected level.
    func nudgeSelectedGlobalGain(up: Bool) -> String? {
        nudgeGlobalGain(selectedGlobalGain, up: up)
    }

    /// Left/Right on the General strip: pick the level the arrows act on. Announced with
    /// its name AND value, since this is the only thing that says which one is armed.
    func selectGlobalGain(next: Bool) -> String? {
        guard !globalGains.isEmpty else { return nil }
        let count = globalGains.count
        selectedGlobalGain = ((selectedGlobalGain + (next ? 1 : -1)) % count + count) % count
        return announceSelectedGlobalGain()
    }

    /// "Output volume, 50 %" — the selected level, name included.
    func announceSelectedGlobalGain() -> String? {
        guard let gain = selectedGain else { return nil }
        return [gain.label, globalGainPercentString(gain)].joined(separator: ", ")
    }

    /// Double-tap V on the General strip, mirroring a user strip's voice reset.
    func resetSelectedGlobalGain() -> String? {
        guard let gain = selectedGain else { return nil }
        let config = globalGainConfig(gain)
        guard let reset = config.resetValue else { return nil }
        config.setValue(reset)
        refreshGlobalGains()
        return [gain.label, config.getDisplayString(reset)].joined(separator: ", ")
    }

    private var selectedGain: MixerGlobalGain? {
        globalGains.indices.contains(selectedGlobalGain) ? globalGains[selectedGlobalGain] : nil
    }

    private func globalGainPercentString(_ gain: MixerGlobalGain) -> String {
        L10n.format("mixer.value.percent", Int(AudioGainControlView.percent(forGainDB: gain.get()).rounded()))
    }

    private func descriptor(for user: ConnectedServerUser) -> MixerStripDescriptor {
        let id = user.id
        return MixerStripDescriptor(
            id: id,
            label: { [weak self] in self?.stripLabel(for: id) },
            controls: [
                .slider(voiceConfig(id: id)),
                .slider(voicePanConfig(id: id)),
                .slider(mediaConfig(id: id)),
                .slider(mediaPanConfig(id: id)),
                .toggle(muteConfig(id: id)),
                .toggle(soloConfig(id: id))
            ]
        )
    }

    private func stripLabel(for id: Int32) -> String? {
        guard let user = user(for: id) else { return nil }
        var parts = [user.displayName]
        parts.append(L10n.format("mixer.value.percent", Int(voicePercent(id).rounded())))
        // Use the mixer's own mute state (optimistic intent + voice/media), the same
        // state the mute toggle reports — so the strip name reflects a mute applied
        // here immediately, instead of only the SDK's voice-mute flag.
        if isMuted(id) { parts.append(L10n.text("mixer.toggle.muted")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Live value access

    private func voicePercent(_ id: Int32) -> Double {
        if let cached = voicePctCache[id] { return cached }
        guard let controller, let user = user(for: id) else { return 0 }
        let v = controller.userVolumeStore.volume(forUsername: user.username) ?? user.volumeVoice
        return Double(TeamTalkConnectionController.percentFromUserVolume(v))
    }

    private func mediaPercent(_ id: Int32) -> Double {
        if let cached = mediaPctCache[id] { return cached }
        guard let controller, let user = user(for: id) else { return 0 }
        let v = controller.userVolumeStore.mediaFileVolume(forUsername: user.username) ?? user.volumeMediaFile
        return Double(TeamTalkConnectionController.percentFromUserVolume(v))
    }

    private func voicePanValue(_ id: Int32) -> Double {
        if let cached = voicePanCache[id] { return cached }
        guard let controller, let user = user(for: id) else { return 0 }
        return Double(controller.userVolumeStore.voicePan(forUsername: user.username) ?? 0)
    }

    private func mediaPanValue(_ id: Int32) -> Double {
        if let cached = mediaPanCache[id] { return cached }
        guard let controller, let user = user(for: id) else { return 0 }
        return Double(controller.userVolumeStore.mediaPan(forUsername: user.username) ?? 0)
    }

    private func isMutedFromSession(_ id: Int32) -> Bool {
        guard let user = user(for: id) else { return false }
        return user.isMuted || user.isMediaFileMuted
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
            minValue: 0, maxValue: 100, resetValue: 50
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
            minValue: 0, maxValue: 100, resetValue: 50
        )
    }

    private func voicePanConfig(id: Int32) -> VirtualSliderConfig {
        VirtualSliderConfig(
            label: L10n.text("mixer.pan.label.short"),
            getValue: { [weak self] in self.map { $0.voicePanValue(id) } },
            getDisplayString: { [weak self] v in self?.voicePanDescription(id, value: v) ?? ChannelMixerCoordinator.panDescription(v) },
            setValue: { [weak self] v in self?.setVoicePan(id: id, value: v) },
            incrementValue: { [panStep] v in min(1, v + panStep) },
            decrementValue: { [panStep] v in max(-1, v - panStep) },
            minValue: -1, maxValue: 1, resetValue: 0
        )
    }

    private func mediaPanConfig(id: Int32) -> VirtualSliderConfig {
        VirtualSliderConfig(
            label: L10n.text("mixer.mediapan.label.short"),
            getValue: { [weak self] in self.map { $0.mediaPanValue(id) } },
            getDisplayString: { [weak self] v in self?.mediaPanDescription(id, value: v) ?? ChannelMixerCoordinator.panDescription(v) },
            setValue: { [weak self] v in self?.setMediaPan(id: id, value: v) },
            incrementValue: { [panStep] v in min(1, v + panStep) },
            decrementValue: { [panStep] v in max(-1, v - panStep) },
            minValue: -1, maxValue: 1, resetValue: 0
        )
    }

    private func muteConfig(id: Int32) -> VirtualToggleConfig {
        VirtualToggleConfig(
            getLabel: { [weak self] in
                // Action-style label so VoiceOver conveys state: "Unmute" means it's
                // currently muted, "Mute" means it's not.
                (self?.isMuted(id) ?? false) ? L10n.text("mixer.mute.action.unmute")
                                             : L10n.text("mixer.mute.action.mute")
            },
            getState: { [weak self] in
                guard let self else { return nil }
                return self.muteCache[id] ?? self.isMutedFromSession(id)
            },
            setState: { [weak self] muted in self?.applyMute(id: id, muted: muted) },
            onAnnouncement: L10n.text("mixer.toggle.muted"),
            offAnnouncement: L10n.text("mixer.toggle.unmuted")
        )
    }

    /// Mute the WHOLE user — both voice and media — since a single "Mute" should
    /// silence everyone, including media-only sources like the radio bot.
    func applyMute(id: Int32, muted: Bool) {
        guard let controller else { return }
        muteCache[id] = muted
        controller.muteUser(userID: id, mute: muted)
        controller.muteUserMediaFile(userID: id, mute: muted)
        refreshDisplay()
    }

    private func soloConfig(id: Int32) -> VirtualToggleConfig {
        VirtualToggleConfig(
            getLabel: { [weak self] in
                (self?.isSoloed(id) ?? false) ? L10n.text("mixer.solo.action.unsolo")
                                              : L10n.text("mixer.solo.action.solo")
            },
            getState: { [weak self] in self?.isSoloed(id) },
            setState: { [weak self] _ in self?.toggleSolo(id) },
            onAnnouncement: L10n.text("mixer.solo.on"),
            offAnnouncement: L10n.text("mixer.solo.off")
        )
    }

    // MARK: Apply (also used by the keyboard controller)

    func setVoice(id: Int32, percent: Double) {
        guard let controller, let user = user(for: id) else { return }
        let clamped = min(100, max(0, percent))
        voicePctCache[id] = clamped
        controller.setUserVoiceVolume(userID: id, username: user.username,
                                      volume: TeamTalkConnectionController.userVolumeFromPercent(clamped))
        refreshDisplay()
    }

    func setMedia(id: Int32, percent: Double) {
        guard let controller, let user = user(for: id) else { return }
        let clamped = min(100, max(0, percent))
        mediaPctCache[id] = clamped
        controller.setUserMediaFileVolume(userID: id, username: user.username,
                                          volume: TeamTalkConnectionController.userVolumeFromPercent(clamped))
        refreshDisplay()
    }

    func setVoicePan(id: Int32, value: Double) {
        guard let controller, let user = user(for: id) else { return }
        let clamped = Double(min(1, max(-1, value)))
        voicePanCache[id] = clamped
        controller.setUserVoicePan(userID: id, username: user.username, pan: Float(clamped), engineMuted: soloMuted(id))
        refreshDisplay()
    }

    func setMediaPan(id: Int32, value: Double) {
        guard let controller, let user = user(for: id) else { return }
        let clamped = Double(min(1, max(-1, value)))
        mediaPanCache[id] = clamped
        controller.setUserMediaPan(userID: id, username: user.username, pan: Float(clamped), engineMuted: soloMuted(id))
        refreshDisplay()
    }

    // MARK: Solo

    /// A user is solo-muted when solo is active and they are NOT one of the soloed users.
    private func soloMuted(_ id: Int32) -> Bool { !soloed.isEmpty && !soloed.contains(id) }

    func isSoloed(_ id: Int32) -> Bool { soloed.contains(id) }

    func toggleSolo(_ id: Int32) {
        if soloed.contains(id) { soloed.remove(id) } else { soloed.insert(id) }
        soloWasActive = !soloed.isEmpty
        reapplySolo()
        refreshDisplay()
    }

    /// Push each user's combined engine settings (pan + solo-mute) — the solo set changed.
    private func reapplySolo() {
        guard let controller else { return }
        for u in usersInChannel() {
            let muted = soloMuted(u.id)
            controller.setUserVoicePan(userID: u.id, username: u.username,
                                       pan: Float(currentVoicePan(u.id)), engineMuted: muted)
            controller.setUserMediaPan(userID: u.id, username: u.username,
                                       pan: Float(currentMediaPan(u.id)), engineMuted: muted)
        }
    }

    /// Rebuild the published snapshot for the on-screen strips from current state.
    func refreshDisplay() {
        refreshGlobalGains()
        displayStrips = usersInChannel().map { u in
            MixerDisplayStrip(id: u.id, name: u.displayName,
                              voicePercent: currentVoicePercent(u.id),
                              mediaPercent: currentMediaPercent(u.id),
                              voicePan: currentVoicePan(u.id),
                              mediaPan: currentMediaPan(u.id),
                              muted: isMuted(u.id),
                              soloed: isSoloed(u.id))
        }
    }

    /// Republish the General strip's levels for the visible mixer. Cheap (four reads), so
    /// it rides along with every display refresh and every keyboard nudge.
    private func refreshGlobalGains() {
        displayGlobalGains = globalGains.enumerated().map { index, gain in
            MixerDisplayGain(id: index, label: gain.label,
                             percent: AudioGainControlView.percent(forGainDB: gain.get()))
        }
    }

    /// The visible fader's write path (mouse). Also arms that level for the keyboard, so
    /// the two routes agree on which level is current.
    func setGlobalGain(_ index: Int, percent: Double) {
        guard globalGains.indices.contains(index) else { return }
        selectedGlobalGain = index
        globalGains[index].set(AudioGainControlView.gainDB(forPercent: percent))
        refreshGlobalGains()
    }

    func currentVoicePercent(_ id: Int32) -> Double { voicePercent(id) }
    func currentMediaPercent(_ id: Int32) -> Double { mediaPercent(id) }
    func currentVoicePan(_ id: Int32) -> Double { voicePanValue(id) }
    func currentMediaPan(_ id: Int32) -> Double { mediaPanValue(id) }
    func isMuted(_ id: Int32) -> Bool { muteCache[id] ?? isMutedFromSession(id) }
    func toggleMute(_ id: Int32) { applyMute(id: id, muted: !isMuted(id)) }

    // MARK: Keyboard actions (return the VoiceOver announcement string)

    func nudgeVoice(_ id: Int32, up: Bool) -> String {
        let v = min(100, max(0, currentVoicePercent(id) + (up ? volumeStep : -volumeStep)))
        setVoice(id: id, percent: v)
        return L10n.format("mixer.value.percent", Int(v.rounded()))
    }
    func nudgeMedia(_ id: Int32, up: Bool) -> String {
        let v = min(100, max(0, currentMediaPercent(id) + (up ? volumeStep : -volumeStep)))
        setMedia(id: id, percent: v)
        // Qualified so VoiceOver distinguishes it from the plain-arrow voice nudge.
        return L10n.format("mixer.media.label", L10n.format("mixer.value.percent", Int(v.rounded())))
    }
    func nudgeVoicePan(_ id: Int32, right: Bool) -> String {
        let p = min(1, max(-1, currentVoicePan(id) + (right ? panStep : -panStep)))
        setVoicePan(id: id, value: p)
        return voicePanDescription(id)
    }
    func nudgeMediaPan(_ id: Int32, right: Bool) -> String {
        let p = min(1, max(-1, currentMediaPan(id) + (right ? panStep : -panStep)))
        setMediaPan(id: id, value: p)
        // Qualified so VoiceOver distinguishes it from the plain-arrow voice pan.
        return L10n.format("mixer.mediapan.label", mediaPanDescription(id))
    }
    func announceVoice(_ id: Int32) -> String { L10n.format("mixer.value.percent", Int(currentVoicePercent(id).rounded())) }
    func announceVoicePan(_ id: Int32) -> String { voicePanDescription(id) }
    func announceMediaPan(_ id: Int32) -> String { L10n.format("mixer.mediapan.label", mediaPanDescription(id)) }
    func resetVoice(_ id: Int32) -> String { setVoice(id: id, percent: 50); return L10n.format("mixer.value.percent", 50) }
    func resetVoicePan(_ id: Int32) -> String { setVoicePan(id: id, value: 0); return voicePanDescription(id) }
    func resetMediaPan(_ id: Int32) -> String { setMediaPan(id: id, value: 0); return L10n.format("mixer.mediapan.label", mediaPanDescription(id)) }
    func muteState(_ id: Int32) -> String {
        isMuted(id) ? L10n.text("mixer.toggle.muted") : L10n.text("mixer.toggle.unmuted")
    }
    func toggleMuteAndAnnounce(_ id: Int32) -> String {
        toggleMute(id)
        return isMuted(id) ? L10n.text("mixer.toggle.muted") : L10n.text("mixer.toggle.unmuted")
    }
    func soloState(_ id: Int32) -> String { isSoloed(id) ? L10n.text("mixer.solo.on") : L10n.text("mixer.solo.off") }
    func toggleSoloAndAnnounce(_ id: Int32) -> String {
        toggleSolo(id)
        return isSoloed(id) ? L10n.text("mixer.solo.on") : L10n.text("mixer.solo.off")
    }

    /// Pan announcement. At center, says "Stereo" when the source is actually sending
    /// two channels and "Center" otherwise (mono, or nothing received yet) — so the user
    /// hears whether a centered stereo sender keeps its stereo image (it does; only
    /// off-center pans fold to mono).
    static func panDescription(_ pan: Double, channels: Int? = nil) -> String {
        let pct = Int((abs(pan) * 100).rounded())
        if pct == 0 { return channels == 2 ? L10n.text("mixer.pan.stereo") : L10n.text("mixer.pan.center") }
        return pan < 0 ? L10n.format("mixer.pan.left", pct) : L10n.format("mixer.pan.right", pct)
    }

    /// Pan description for a user's VOICE source, stereo-aware from its live channel count.
    func voicePanDescription(_ id: Int32, value: Double? = nil) -> String {
        Self.panDescription(value ?? currentVoicePan(id), channels: controller?.deliveredVoiceChannels(userID: id))
    }
    /// Pan description for a user's MEDIA source, stereo-aware from its live channel count.
    func mediaPanDescription(_ id: Int32, value: Double? = nil) -> String {
        Self.panDescription(value ?? currentMediaPan(id), channels: controller?.deliveredMediaChannels(userID: id))
    }
}
#endif
