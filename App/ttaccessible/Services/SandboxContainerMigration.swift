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
//  Never clobbers: each item is copied only when it doesn't already exist at
//  the destination, so a user who ran unsandboxed first (fresh data) keeps it.
//

import Foundation

enum SandboxContainerMigration {

    private static let bundleIdentifier = "com.math65.ttaccessible"

    /// Runs at process start, before any UserDefaults access (the first read
    /// caches the domain, so preference plists must be in place first).
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
        let marker = supportRoot.appendingPathComponent(".sandbox-container-migrated")
        guard fileManager.fileExists(atPath: marker.path) == false else { return }

        var copied = 0

        // 1. Preference plists: the standard domain, the default-profile suite
        // and every custom profile suite all share the bundle-id prefix.
        let sourcePrefs = containerData.appendingPathComponent("Library/Preferences", isDirectory: true)
        let destinationPrefs = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        for name in (try? fileManager.contentsOfDirectory(atPath: sourcePrefs.path)) ?? []
        where name.hasPrefix(bundleIdentifier) && name.hasSuffix(".plist") {
            let destination = destinationPrefs.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: destination.path) == false else { continue }
            do {
                try fileManager.copyItem(at: sourcePrefs.appendingPathComponent(name), to: destination)
                copied += 1
            } catch {
                NSLog("SandboxContainerMigration: preferences copy failed for %@ — %@", name, error.localizedDescription)
            }
        }

        // 2. Application Support payload (saved-server registry files, chat
        // history, profiles, custom sound packs). The container's Application
        // Support holds only this app's data, so copy every top-level entry
        // that doesn't already exist outside.
        let sourceSupport = containerData.appendingPathComponent("Library/Application Support", isDirectory: true)
        let destinationSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        for name in (try? fileManager.contentsOfDirectory(atPath: sourceSupport.path)) ?? [] {
            let destination = destinationSupport.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: destination.path) == false else { continue }
            do {
                try fileManager.copyItem(at: sourceSupport.appendingPathComponent(name), to: destination)
                copied += 1
            } catch {
                NSLog("SandboxContainerMigration: support copy failed for %@ — %@", name, error.localizedDescription)
            }
        }

        do {
            try fileManager.createDirectory(at: supportRoot, withIntermediateDirectories: true)
            fileManager.createFile(atPath: marker.path, contents: Data())
        } catch {
            NSLog("SandboxContainerMigration: marker write failed — %@", error.localizedDescription)
        }
        NSLog("SandboxContainerMigration: imported %d item(s) from the sandbox container", copied)
    }
}
