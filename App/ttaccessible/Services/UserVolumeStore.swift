//
//  UserVolumeStore.swift
//  ttaccessible
//

import Foundation

/// Per-user voice/media volume, stereo balance and pan.
///
/// **Memory mode** (issue #24, johanntan's request) controls whether adjustments are
/// remembered at all:
/// - `.off`     — never remembered; every lookup returns nil, so reconnecting resets
///                everyone to 50% (matches the official client). Writes are no-ops.
/// - `.session` — kept in memory only, so adjustments survive reconnects but are
///                discarded when the app quits.
/// - `.persistent` — kept in the profile's UserDefaults across launches.
///
/// **Server scoping**: entries are keyed by `serverScope` + username, NOT username
/// alone. TeamTalk `szUsername` is frequently shared/generic on public servers (guest,
/// anonymous, club accounts), so a username-only key let a volume set for one person
/// silently re-apply to a different person with the same username — even across servers
/// (issue #24). Scoping by server (host:port) confines a stored volume to the server it
/// was set on. Same-server collisions on a shared account are an inherent limit:
/// `szUsername` is the only identifier the SDK keeps stable across reconnects.
///
/// Pre-scoping persistent entries (bare-username keys) no longer match a scoped lookup
/// and fall back to the 50% default — intentional, as those values are exactly the
/// cross-server-polluted data the scoping fixes.
final class UserVolumeStore {
    typealias MemoryMode = AppPreferences.UserVolumeMemoryMode

    private let key = "userVoiceVolumeByUsername"
    private let mediaFileKey = "userMediaFileVolumeByUsername"
    private let stereoKey = "userStereoBalanceByUsername"
    private let panKey = "userPanByUsername"
    private let mediaPanKey = "userMediaPanByUsername"
    private let defaults: UserDefaults

    /// Guards the mutable state below. It is written on the TeamTalk queue (connect /
    /// preference apply) but read from both that queue and the main thread (mixer /
    /// user-actions UI).
    private let lock = NSLock()
    /// Server identity (e.g. "host:port") prepended to every entry key. Empty until a
    /// session is established; reads/writes only happen while connected.
    private var serverScope = ""
    private var memoryMode: MemoryMode = .persistent
    /// In-memory backing for `.session` mode, keyed by the same type keys as UserDefaults.
    private var sessionDicts: [String: [String: Any]] = [:]

    init(defaults: UserDefaults = ProfileContext.current.userDefaults) {
        self.defaults = defaults
    }

    /// Set the current server scope (call on connect), or nil to clear (on disconnect).
    func setServerScope(_ scope: String?) {
        lock.lock()
        serverScope = scope ?? ""
        lock.unlock()
    }

    /// Set how adjustments are remembered. Switching mode never erases already-stored
    /// data (e.g. persistent → off just stops reading it); only quitting clears the
    /// session backing, and only writing the default prunes a persistent entry.
    func setMemoryMode(_ mode: MemoryMode) {
        lock.lock()
        memoryMode = mode
        lock.unlock()
    }

    /// Compose the persisted entry key from the current server scope and the username.
    /// The unit-separator (U+001F) can't appear in a host or a TeamTalk username, so it
    /// is an unambiguous delimiter. With no scope set, falls back to the bare username.
    private func entryKey(_ username: String) -> String {
        lock.lock()
        let scope = serverScope
        lock.unlock()
        return scope.isEmpty ? username : scope + "\u{1F}" + username
    }

    /// Read the backing dictionary for a type key, honoring the current memory mode.
    /// `.off` always reads empty so every lookup falls back to the default.
    private func loadDict(_ typeKey: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        switch memoryMode {
        case .off: return nil
        case .session: return sessionDicts[typeKey]
        case .persistent: return defaults.dictionary(forKey: typeKey)
        }
    }

    /// Write the backing dictionary for a type key, honoring the current memory mode.
    /// `.off` discards the write.
    private func storeDict(_ dict: [String: Any], _ typeKey: String) {
        lock.lock()
        defer { lock.unlock() }
        switch memoryMode {
        case .off: return
        case .session: sessionDicts[typeKey] = dict
        case .persistent: defaults.set(dict, forKey: typeKey)
        }
    }

    func volume(forUsername username: String) -> Int32? {
        volume(forUsername: username, key: key)
    }

    func setVolume(_ volume: Int32, forUsername username: String) {
        setVolume(volume, forUsername: username, key: key)
    }

    func mediaFileVolume(forUsername username: String) -> Int32? {
        volume(forUsername: username, key: mediaFileKey)
    }

    func setMediaFileVolume(_ volume: Int32, forUsername username: String) {
        setVolume(volume, forUsername: username, key: mediaFileKey)
    }

    private func volume(forUsername username: String, key: String) -> Int32? {
        guard !username.isEmpty,
              let dict = loadDict(key),
              let value = dict[entryKey(username)] as? Int else { return nil }
        return Int32(value)
    }

    private func setVolume(_ volume: Int32, forUsername username: String, key: String) {
        guard !username.isEmpty else { return }
        var dict = loadDict(key) ?? [:]
        let entry = entryKey(username)
        if volume == SOUND_VOLUME_DEFAULT.rawValue {
            dict.removeValue(forKey: entry)
        } else {
            dict[entry] = Int(volume)
        }
        storeDict(dict, key)
    }

    // MARK: - Stereo Balance

    struct StereoBalance: Equatable {
        let left: Bool
        let right: Bool
        static let `default` = StereoBalance(left: true, right: true)
    }

    func stereoBalance(forUsername username: String) -> StereoBalance? {
        guard !username.isEmpty,
              let dict = loadDict(stereoKey),
              let entry = dict[entryKey(username)] as? [String: Bool],
              let left = entry["left"],
              let right = entry["right"] else { return nil }
        return StereoBalance(left: left, right: right)
    }

    func setStereoBalance(_ balance: StereoBalance, forUsername username: String) {
        guard !username.isEmpty else { return }
        var dict = loadDict(stereoKey) ?? [:]
        let entry = entryKey(username)
        if balance == .default {
            dict.removeValue(forKey: entry)
        } else {
            dict[entry] = ["left": balance.left, "right": balance.right]
        }
        storeDict(dict, stereoKey)
    }

    // MARK: - Continuous Pan (Channel Mixer)
    //
    // The mixer's pan slider drives OutputAudioRenderEngine.setUserSettings (our own
    // per-user mix), independent of the SDK's discrete left/right StereoBalance above.
    // Range -1 (full left) .. 0 (center) .. +1 (full right); center is the default and
    // is stored as "no entry" so it never overrides a user who only touches the L/R checks.

    // Voice and media-file each have their OWN pan, mirroring the split voice/media
    // volume controls. The voice pan reuses the original `userPanByUsername` key, so a
    // pan saved before the voice/media split carries forward as that user's voice pan.

    func voicePan(forUsername username: String) -> Float? { pan(forUsername: username, key: panKey) }
    func setVoicePan(_ pan: Float, forUsername username: String) { setPan(pan, forUsername: username, key: panKey) }

    func mediaPan(forUsername username: String) -> Float? { pan(forUsername: username, key: mediaPanKey) }
    func setMediaPan(_ pan: Float, forUsername username: String) { setPan(pan, forUsername: username, key: mediaPanKey) }

    private func pan(forUsername username: String, key: String) -> Float? {
        guard !username.isEmpty,
              let dict = loadDict(key),
              let value = dict[entryKey(username)] as? Double else { return nil }
        return Float(value)
    }

    private func setPan(_ pan: Float, forUsername username: String, key: String) {
        guard !username.isEmpty else { return }
        let clamped = max(-1, min(1, pan))
        var dict = loadDict(key) ?? [:]
        let entry = entryKey(username)
        if abs(clamped) < 0.0001 {
            dict.removeValue(forKey: entry)
        } else {
            dict[entry] = Double(clamped)
        }
        storeDict(dict, key)
    }
}
