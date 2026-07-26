//
//  ProfileDuplicator.swift
//  ttaccessible
//
//  Clones an existing profile (servers, passwords, settings, chat history and
//  sound packs) into a brand-new profile. Surfaced by the Profiles window's
//  "Duplicate…" action. Unlike "New Profile" — which registers an empty slug —
//  this copies every storage backend a profile owns:
//    1. the UserDefaults suite (servers, all preferences, volumes, last channel…)
//    2. the keychain items (per-server passwords)
//    3. the Application Support files (chat history, custom sound packs)
//

import Foundation

enum ProfileDuplicatorError: LocalizedError {
    /// The new name was empty or normalized to an unusable slug.
    case invalidName
    /// The new name normalizes to the source's own slug — copying would write
    /// the profile back onto itself.
    case slugCollision
    /// The source profile is open in another running instance; its data could
    /// be mutated mid-copy.
    case sourceIsRunningElsewhere

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return L10n.text("profile.create.error.invalid")
        case .slugCollision:
            return L10n.text("profile.duplicate.error.failed")
        case .sourceIsRunningElsewhere:
            return L10n.text("profile.duplicate.error.failed")
        }
    }
}

enum ProfileDuplicator {
    /// UserDefaults keys carrying security-scoped bookmark data. Stripped from
    /// the copy — the bytes are tied to the granting selection event and a stale
    /// grant in the new profile is worse than re-prompting on first use.
    private static let bookmarkSuiteKeys: Set<String> = ["teamTalkImport.bookmarkData"]

    /// Suite keys we deliberately do NOT carry into the copy. A fresh clone
    /// should not inherit which server was selected, and the target store's own
    /// init re-creates its bookkeeping / migration flags.
    private static func shouldSkipSuiteKey(_ key: String) -> Bool {
        // Framework keys (Sparkle, AppKit window-frame autosave, etc.) — same
        // filter `ProfileContext.migrateDefaultProfileStorageIfNeeded` uses.
        let systemPrefixes = ["SU", "NS", "Apple", "com.apple", "WebKit", "Sparkle"]
        if systemPrefixes.contains(where: { key.hasPrefix($0) }) { return true }
        if key == "savedServers.selectedID" { return true }
        if key.hasPrefix("ServerPasswordStore") { return true }
        if key.hasPrefix("profile.") { return true } // migration flags
        return bookmarkSuiteKeys.contains(key)
    }

    /// Duplicate `sourceSlug` into a new profile named `newDisplayName`.
    /// Returns the new registry entry. Caller should flush the live stores
    /// first (see `AppDelegate.flushPersistableStores`) when the source is the
    /// current profile, so the copy captures the latest edits.
    @discardableResult
    static func duplicate(sourceSlug: String, newDisplayName: String) throws -> ProfileRegistry.Entry {
        let srcSlug = ProfileContext.normalizeSlug(sourceSlug)

        // Step 0 — refuse a source running in another process (concurrent writes).
        if srcSlug != ProfileContext.defaultSlug,
           ProfileInstanceLock.isAnotherInstanceRunning(forSlug: srcSlug) {
            throw ProfileDuplicatorError.sourceIsRunningElsewhere
        }

        // Step 1 — register the target slug.
        guard let target = ProfileRegistry.shared.register(displayName: newDisplayName) else {
            throw ProfileDuplicatorError.invalidName
        }
        // `register` is idempotent: a name normalizing to the source's slug
        // returns the source entry itself. Copying onto it would corrupt the
        // source, so treat it as a hard error.
        guard target.slug != srcSlug else {
            throw ProfileDuplicatorError.slugCollision
        }

        // Step 2 — build source/destination contexts (without mutating `current`).
        let source: ProfileContext = (srcSlug == ProfileContext.defaultSlug)
            ? ProfileContext.defaultProfile()
            : ProfileContext.make(slug: srcSlug, displayName: srcSlug)
        let dest = ProfileContext.make(slug: target.slug, displayName: target.displayName)

        source.userDefaults.synchronize()

        // Step 3 — copy the UserDefaults suite (servers + all settings + volumes…).
        copyUserDefaultsSuite(from: source, to: dest)

        // Step 4 — copy per-server passwords (keychain). Best-effort.
        copyKeychainPasswords(from: source, to: dest)

        // Step 5 — copy files (chat history + custom sound packs). Best-effort.
        copyDirectory(from: source.channelChatHistoryDirectory, to: dest.channelChatHistoryDirectory)
        copyDirectory(from: source.customSoundPacksDirectory, to: dest.customSoundPacksDirectory)

        return target
    }

    // MARK: - UserDefaults suite

    private static func suiteName(for context: ProfileContext) -> String {
        context.isDefault
            ? ProfileContext.defaultSuiteName
            : ProfileContext.suiteName(forSlug: context.slug)
    }

    private static func copyUserDefaultsSuite(from source: ProfileContext, to dest: ProfileContext) {
        // `persistentDomain(forName:)` returns ONLY the keys actually written to
        // the suite, not the bundle-domain fall-through `dictionaryRepresentation`
        // would include.
        let srcSuite = suiteName(for: source)
        guard let domain = UserDefaults.standard.persistentDomain(forName: srcSuite) else { return }

        for (key, value) in domain {
            if shouldSkipSuiteKey(key) { continue }

            // Strip the security-scoped recording-folder bookmark from the
            // preferences blob (re-granted on first recording).
            if key == "appPreferences.value", let data = value as? Data {
                dest.userDefaults.set(strippedPreferencesData(data) ?? data, forKey: key)
                continue
            }

            dest.userDefaults.set(value, forKey: key)
        }
        dest.userDefaults.synchronize()
    }

    /// Re-encode the preferences blob with the recording-folder bookmark cleared.
    /// Returns nil when decoding fails (caller falls back to the raw bytes).
    private static func strippedPreferencesData(_ data: Data) -> Data? {
        guard var prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return nil }
        guard prefs.recordingFolderBookmark != nil else { return data }
        prefs.recordingFolderBookmark = nil
        return try? JSONEncoder().encode(prefs)
    }

    // MARK: - Keychain

    private static func copyKeychainPasswords(from source: ProfileContext, to dest: ProfileContext) {
        // Read the records we just wrote into the destination so the UUID set
        // matches the copied servers exactly.
        guard let data = dest.userDefaults.data(forKey: "savedServers.records"),
              let records = try? JSONDecoder().decode([SavedServerRecord].self, from: data),
              records.isEmpty == false else {
            return
        }

        let srcStore = ServerPasswordStore(serviceName: source.keychainServiceName, defaults: source.userDefaults)
        let dstStore = ServerPasswordStore(serviceName: dest.keychainServiceName, defaults: dest.userDefaults)

        for record in records {
            // Best-effort per item: a broken-ACL source item must not abort the
            // whole duplication. The new profile re-prompts on first connect.
            if let server = try? srcStore.password(for: record.id) {
                try? dstStore.setPassword(server, for: record.id)
            }
            if let channel = try? srcStore.channelPassword(for: record.id) {
                try? dstStore.setChannelPassword(channel, for: record.id)
            }
            if let channels = try? srcStore.allChannelPasswords(for: record.id), !channels.isEmpty {
                try? dstStore.setChannelPasswords(channels, for: record.id)
            }
        }
    }

    // MARK: - Files

    private static func copyDirectory(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return }
        // Target is a brand-new profile, so `dst` shouldn't exist; remove any
        // stray leftover then copy the whole tree.
        try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: src, to: dst)
    }
}
