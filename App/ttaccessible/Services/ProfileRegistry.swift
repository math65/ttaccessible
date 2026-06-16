//
//  ProfileRegistry.swift
//  ttaccessible
//

import Foundation

/// Tracks the set of profiles known to ttaccessible. The registry lives in a
/// dedicated UserDefaults suite that every running instance can read, so a
/// profile created in one instance shows up in another's picker immediately.
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

        var entries = loadCustomEntries()
        if let existing = entries.first(where: { $0.slug == slug }) {
            return existing
        }
        let entry = Entry(slug: slug, displayName: trimmed)
        entries.append(entry)
        persist(entries)
        return entry
    }

    private func loadCustomEntries() -> [Entry] {
        guard let data = defaults.data(forKey: Keys.entries),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded.filter { $0.slug != ProfileContext.defaultSlug }
    }

    private func persist(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Keys.entries)
    }
}
