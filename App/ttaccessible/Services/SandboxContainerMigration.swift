//
//  SandboxContainerMigration.swift
//  ttaccessible
//
//  One-time import of the App Sandbox container's data after the app stops
//  being sandboxed. Sandboxed builds kept everything under
//  ~/Library/Containers/com.math65.ttaccessible/Data/…; an unsandboxed build
//  reads the real ~/Library — without this, every user's saved servers,
//  preferences, profiles, chat history and sound packs would silently vanish
//  on update. Keychain items need no migration: their ACLs bind to the app's
//  code signature, not the sandbox.
//
//  Preferences are migrated THROUGH the UserDefaults API, key by key, never
//  by copying plist files into ~/Library/Preferences: cfprefsd owns that
//  directory and serves domains from its own cache — a file copied behind its
//  back is ignored and then overwritten the first time the app writes a
//  default (which is how the first version of this migration lost the data it
//  had just copied).
//
//  Container values WIN over whatever is already in the unsandboxed domain:
//  the migration runs exactly once, at first unsandboxed launch, when the
//  real domain holds nothing but framework noise or debris from a fresh
//  launch — while the container holds the user's actual data.
//

import Foundation

enum SandboxContainerMigration {

    private static let bundleIdentifier = "com.math65.ttaccessible"
    /// v2: the v1 marker was written by the plist-file-copy version whose
    /// preference import silently failed (see header) — a fresh marker lets
    /// the corrected migration run again for anyone who launched v1.
    private static let markerName = ".sandbox-container-migrated-v2"

    /// Runs at process start, before any store reads its preferences.
    /// No-op when the process is still sandboxed, when there is no container,
    /// or when the migration already ran.
    static func migrateIfNeeded() {
        // Sandboxed processes carry the container id in their environment;
        // in that case ~/Library *is* the container and there is nothing to do.
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else { return }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let containerData = home
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        guard fileManager.fileExists(atPath: containerData.path) else { return }

        let supportRoot = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("ttaccessible", isDirectory: true)
        let marker = supportRoot.appendingPathComponent(markerName)
        guard fileManager.fileExists(atPath: marker.path) == false else { return }

        migratePreferences(containerData: containerData)
        migrateApplicationSupport(containerData: containerData, home: home, fileManager: fileManager)

        do {
            try fileManager.createDirectory(at: supportRoot, withIntermediateDirectories: true)
            fileManager.createFile(atPath: marker.path, contents: Data())
        } catch {
            NSLog("SandboxContainerMigration: marker write failed — %@", error.localizedDescription)
        }
    }

    /// Reads each of the app's preference domains straight from the container
    /// plists (plain file reads — cfprefsd doesn't serve the container to an
    /// unsandboxed process) and replays every key through UserDefaults, so the
    /// real domains are populated with cfprefsd fully in the loop.
    private static func migratePreferences(containerData: URL) {
        let sourcePrefs = containerData.appendingPathComponent("Library/Preferences", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sourcePrefs.path)) ?? []
        for name in names where name.hasPrefix(bundleIdentifier) && name.hasSuffix(".plist") {
            let domain = String(name.dropLast(".plist".count))
            guard let contents = NSDictionary(contentsOf: sourcePrefs.appendingPathComponent(name)) as? [String: Any],
                  contents.isEmpty == false else { continue }

            let defaults: UserDefaults?
            if domain == bundleIdentifier {
                defaults = .standard
            } else {
                defaults = UserDefaults(suiteName: domain)
            }
            guard let defaults else {
                NSLog("SandboxContainerMigration: could not open defaults domain %@", domain)
                continue
            }
            for (key, value) in contents {
                defaults.set(value, forKey: key)
            }
            NSLog("SandboxContainerMigration: imported %d preference key(s) into %@", contents.count, domain)
        }
    }

    /// Copies the container's Application Support payload (chat history,
    /// profiles, custom sound packs). Merges one level deep so a directory
    /// the app already recreated (e.g. ttaccessible/instance-locks) doesn't
    /// block the rest of its children; symlinks (AddressBook, iCloud, …
    /// system links inside containers) are skipped. Existing destination
    /// files are never overwritten.
    private static func migrateApplicationSupport(containerData: URL, home: URL, fileManager: FileManager) {
        let source = containerData.appendingPathComponent("Library/Application Support", isDirectory: true)
        let destination = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        mergeCopy(from: source, to: destination, depth: 3, fileManager: fileManager)
    }

    private static func mergeCopy(from source: URL, to destination: URL, depth: Int, fileManager: FileManager) {
        let names = (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []
        for name in names {
            let sourceItem = source.appendingPathComponent(name)
            let destinationItem = destination.appendingPathComponent(name)

            // Skip symlinks — containers hold system links (AddressBook, iCloud…)
            // that must not be replicated outside.
            if let attributes = try? fileManager.attributesOfItem(atPath: sourceItem.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                continue
            }

            var isDirectory: ObjCBool = false
            let destinationExists = fileManager.fileExists(atPath: destinationItem.path, isDirectory: &isDirectory)
            if destinationExists == false {
                do {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: sourceItem, to: destinationItem)
                } catch {
                    NSLog("SandboxContainerMigration: copy failed for %@ — %@", name, error.localizedDescription)
                }
                continue
            }
            // Destination exists: recurse into directories (up to depth) so an
            // already-recreated folder doesn't block missing children; leave
            // existing files alone.
            if isDirectory.boolValue, depth > 1 {
                mergeCopy(from: sourceItem, to: destinationItem, depth: depth - 1, fileManager: fileManager)
            }
        }
    }
}
