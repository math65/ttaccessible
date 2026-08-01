//
//  HotkeyStatusStore.swift
//  ttaccessible
//
//  Runtime state of the global hotkeys, for Preferences to display. A binding
//  can be perfectly valid and still not run: the recorder asks the OS whether a
//  chord is free at record time, but another app can claim it afterwards, and
//  RegisterEventHotKey then refuses it. We deliberately don't fall back to the
//  event tap in that case (it would ask for Input Monitoring out of nowhere and
//  fire on top of the other app), so the hotkey is simply inactive — and
//  silence at that point reads as "the app is broken".
//

import Combine
import Foundation

@MainActor
final class HotkeyStatusStore: ObservableObject {
    static let shared = HotkeyStatusStore()

    /// The binding another app owns, when there is one. nil means the hotkey is
    /// running — or isn't configured at all.
    @Published private(set) var pushToTalkUnavailable: HotkeyBinding?
    @Published private(set) var muteHotkeyUnavailable: HotkeyBinding?

    private init() {}

    func setPushToTalkUnavailable(_ binding: HotkeyBinding?) {
        guard pushToTalkUnavailable != binding else { return }
        pushToTalkUnavailable = binding
    }

    func setMuteHotkeyUnavailable(_ binding: HotkeyBinding?) {
        guard muteHotkeyUnavailable != binding else { return }
        muteHotkeyUnavailable = binding
    }
}
