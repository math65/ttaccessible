//
//  AnnouncementService.swift
//  ttaccessible
//

import AppKit

/// Checks the app backend for an active announcement at launch and shows it
/// in an accessible alert. The `once` mode is enforced client-side (the server
/// always returns the live announcement): displayed `once` announcement IDs
/// are remembered in UserDefaults.
@MainActor
final class AnnouncementService {
    private static let installIDKey = "appBackendInstallID"
    private static let seenAnnouncementIDsKey = "appBackendSeenAnnouncementIDs"

    private let client = AppBackendClient()

    func checkAtLaunch() {
        guard AppBackendClient.isConfigured else {
            return
        }
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "fr" : "en"
        client.checkAnnouncement(installID: Self.installID, language: language) { [weak self] result in
            guard case .success(let announcement?) = result else {
                return
            }
            self?.presentIfNeeded(announcement)
        }
    }

    private func presentIfNeeded(_ announcement: AppBackendClient.Announcement) {
        let defaults = ProfileContext.current.userDefaults
        var seenIDs = defaults.stringArray(forKey: Self.seenAnnouncementIDsKey) ?? []
        if announcement.mode == "once", seenIDs.contains(announcement.id) {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = announcement.style == "warning" ? .warning : .informational
        alert.messageText = announcement.title
        alert.informativeText = announcement.body
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        if seenIDs.contains(announcement.id) == false {
            seenIDs.append(announcement.id)
            defaults.set(seenIDs, forKey: Self.seenAnnouncementIDsKey)
        }
        client.acknowledgeAnnouncement(installID: Self.installID, announcementID: announcement.id)
    }

    /// Stable per-install UUID. The server only stores a hash of it, for
    /// deduplicating the announcement reach counter.
    private static var installID: String {
        let defaults = ProfileContext.current.userDefaults
        if let existing = defaults.string(forKey: installIDKey), existing.isEmpty == false {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: installIDKey)
        return fresh
    }
}
