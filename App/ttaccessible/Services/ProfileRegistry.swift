//
//  ProfileRegistry.swift
//  ttaccessible
//

import Foundation

/// Tracks the set of profiles known to ttaccessible. The registry lives in a
/// dedicated UserDefaults suite that every running instance can read, so a
/// profile created in one instance shows up in another's picker immediately.
///
/// Mutating calls hold an in-process lock and force the suite to sync after
/// writing. Cross-process simultaneous registrations could still race (two
/// instances each reading the suite, modifying, and writing back) — that's
/// inherent to UserDefaults and tolerable here because registrations are
/// user-initiated and rare.
final class ProfileRegistry {
    struct Entry: Codable, Equatable {
        var slug: String
        var displayName: String
    }

    static let shared = ProfileRegistry()

    private enum Keys {
        static let entries = "profiles.registry.entries"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = ProfileRegistry.makeSharedDefaults()) {
        self.defaults = defaults
    }

    static func makeSharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.math65.ttaccessible.profiles") ?? .standard
    }

    /// All profiles known to the app, including the synthetic "Default" entry.
    /// Sorted by display name (default first).
    func listAll() -> [Entry] {
        let custom = loadCustomEntries()
        let defaultEntry = Entry(slug: ProfileContext.defaultSlug, displayName: ProfileContext.defaultDisplayName)
        return [defaultEntry] + custom.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Custom (non-default) profiles only.
    func customProfiles() -> [Entry] {
        loadCustomEntries().sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Look up a profile by slug. Returns the synthetic default entry for the
    /// default slug; nil for unknown slugs.
    func entry(forSlug slug: String) -> Entry? {
        let normalized = ProfileContext.normalizeSlug(slug)
        if normalized == ProfileContext.defaultSlug {
            return Entry(slug: ProfileContext.defaultSlug, displayName: ProfileContext.defaultDisplayName)
        }
        return loadCustomEntries().first { $0.slug == normalized }
    }

    /// Register a new profile with the given display name. The display name is
    /// sanitized into a slug; if a profile with that slug already exists, this
    /// is a no-op and the existing entry is returned. Returns nil if the input
    /// is empty or collides with the reserved default slug.
    @discardableResult
    func register(displayName rawName: String) -> Entry? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let slug = ProfileContext.normalizeSlug(trimmed)
        guard slug.isEmpty == false, slug != ProfileContext.defaultSlug else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var entries = loadCustomEntriesLocked()
        if let existing = entries.first(where: { $0.slug == slug }) {
            return existing
        }
        let entry = Entry(slug: slug, displayName: trimmed)
        entries.append(entry)
        persistLocked(entries)
        return entry
    }

    /// Update the display name of an existing custom profile. The slug stays
    /// the same (it identifies on-disk paths and keychain items). Returns the
    /// updated entry on success.
    @discardableResult
    func rename(slug rawSlug: String, to rawName: String) -> Entry? {
        let slug = ProfileContext.normalizeSlug(rawSlug)
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard slug.isEmpty == false, slug != ProfileContext.defaultSlug, trimmed.isEmpty == false else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        var entries = loadCustomEntriesLocked()
        guard let index = entries.firstIndex(where: { $0.slug == slug }) else {
            return nil
        }
        entries[index].displayName = trimmed
        persistLocked(entries)
        return entries[index]
    }

    /// Drop the registry entry for a custom profile. Does NOT touch the
    /// on-disk data, UserDefaults suite, or keychain items — call
    /// `ProfileContext.purgeStorage(forSlug:)` for that. Returns true if an
    /// entry was removed.
    @discardableResult
    func remove(slug rawSlug: String) -> Bool {
        let slug = ProfileContext.normalizeSlug(rawSlug)
        guard slug.isEmpty == false, slug != ProfileContext.defaultSlug else { return false }

        lock.lock()
        defer { lock.unlock() }

        var entries = loadCustomEntriesLocked()
        let before = entries.count
        entries.removeAll { $0.slug == slug }
        guard entries.count != before else { return false }
        persistLocked(entries)
        return true
    }

    // MARK: - Storage

    private func loadCustomEntries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return loadCustomEntriesLocked()
    }

    private func loadCustomEntriesLocked() -> [Entry] {
        guard let data = defaults.data(forKey: Keys.entries),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded.filter { $0.slug != ProfileContext.defaultSlug }
    }

    private func persistLocked(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Keys.entries)
        defaults.synchronize()
    }
}
