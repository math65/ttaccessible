//
//  HotkeyStatusStore.swift
//  ttaccessible
//
//  Runtime state of the global hotkeys, for Preferences to display. A binding
//  can be perfectly valid and still not run — our two hotkeys carrying the same
//  chord, or a key the chat field needs bound globally (see
//  HotkeyMonitor.Unavailability). The hotkey is then simply inactive, and
//  silence at that point reads as "the app is broken".
//

import Combine
import Foundation

@MainActor
final class HotkeyStatusStore: ObservableObject {
    static let shared = HotkeyStatusStore()

    /// Why each hotkey isn't running, when it isn't. nil means it runs — or
    /// isn't configured at all.
    @Published private(set) var pushToTalk: HotkeyMonitor.Unavailability?
    @Published private(set) var muteHotkey: HotkeyMonitor.Unavailability?

    private init() {}

    func setPushToTalk(_ reason: HotkeyMonitor.Unavailability?) {
        guard pushToTalk != reason else { return }
        pushToTalk = reason
    }

    func setMuteHotkey(_ reason: HotkeyMonitor.Unavailability?) {
        guard muteHotkey != reason else { return }
        muteHotkey = reason
    }
}
