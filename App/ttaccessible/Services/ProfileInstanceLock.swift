//
//  ProfileInstanceLock.swift
//  ttaccessible
//

import Darwin
import Foundation

/// Best-effort tracker for "which profile is already running in another
/// process." Each instance writes its PID to a per-slug file at launch and
/// removes it on graceful exit; the "New Instance" menu consults these files
/// before launching to refuse a second instance of the same profile.
///
/// Limitations:
/// - Crashes leave a stale PID file. Resolved on next check via `kill(pid, 0)`
///   liveness probe; if the original process is gone, the lock is treated as
///   free and overwritten.
/// - PID recycling is theoretically possible (a stale PID could be reused by
///   an unrelated process) — extremely unlikely on macOS within the
///   typical app session, and worst case the user sees a false "already
///   running" refusal and can remove the lock file manually.
/// - Two processes acquiring at exactly the same instant race; both succeed.
///   Not a correctness problem — UserDefaults writes are last-writer-wins per
///   key, which the per-profile isolation already tolerates.
enum ProfileInstanceLock {
    private static let queue = DispatchQueue(label: "com.math65.ttaccessible.profilelock")

    /// Write the current process's PID to this profile's lock file.
    static func acquire(for context: ProfileContext) {
        queue.async {
            let url = lockFileURL(forSlug: context.slug)
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let pid = ProcessInfo.processInfo.processIdentifier
            let body = "\(pid)\n"
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Remove this profile's lock file. Safe to call multiple times.
    static func release(for context: ProfileContext) {
        // Synchronous so it runs inside `applicationWillTerminate` before
        // the process actually exits.
        let url = lockFileURL(forSlug: context.slug)
        try? FileManager.default.removeItem(at: url)
    }

    /// Returns true if another live process holds the lock for the given
    /// profile slug. Stale locks (file present but PID dead) are cleared and
    /// reported as not-running.
    static func isAnotherInstanceRunning(forSlug rawSlug: String) -> Bool {
        let slug = ProfileContext.normalizeSlug(rawSlug)
        guard slug.isEmpty == false else { return false }
        let url = lockFileURL(forSlug: slug)
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        // kill(pid, 0) is the standard liveness probe: returns 0 if signalable,
        // -1 with errno == ESRCH if no such process.
        if kill(pid, 0) == 0 {
            // Don't refuse on ourselves — same PID means a relaunch that
            // didn't get a chance to release first.
            if pid == ProcessInfo.processInfo.processIdentifier {
                return false
            }
            return true
        }
        // Stale lock — file present but the PID is gone. Clean it up so the
        // next launch starts fresh.
        try? FileManager.default.removeItem(at: url)
        return false
    }

    private static func lockFileURL(forSlug slug: String) -> URL {
        ProfileContext.sharedCoordinationDirectory
            .appendingPathComponent("\(slug).pid", isDirectory: false)
    }
}
