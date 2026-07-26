//
//  AppSandboxState.swift
//  ttaccessible
//
//  Whether this process is running inside the App Sandbox, and the file-access
//  helpers that have to behave differently either way.
//
//  Security-scoped bookmarks only exist for sandboxed apps. Outside the sandbox
//  `bookmarkData(options: .withSecurityScope)` throws, and
//  `startAccessingSecurityScopedResource()` returns false for an ordinary URL —
//  which is *not* a failure, it simply means no scope is needed. Code that
//  treats that false as "access denied" breaks in an unsandboxed build even
//  though the file is perfectly readable.
//

import Foundation

enum AppSandboxState {
    /// Sandboxed processes carry their container id in the environment.
    static let isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Bookmark options appropriate to the current process: security-scoped when
    /// sandboxed, plain otherwise.
    static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        isSandboxed ? [.withSecurityScope] : []
    }

    static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        isSandboxed ? [.withSecurityScope] : []
    }

    /// Begin access to a user-selected location. Returns whether the caller must
    /// later balance it with `endAccess`. Unsandboxed this is a no-op that
    /// reports success, because no scope is required to read the file.
    @discardableResult
    static func beginAccess(_ url: URL) -> Bool {
        guard isSandboxed else { return false }
        return url.startAccessingSecurityScopedResource()
    }

    static func endAccess(_ url: URL, didAccess: Bool) {
        guard isSandboxed, didAccess else { return }
        url.stopAccessingSecurityScopedResource()
    }

    /// Whether a user-selected location is usable. Sandboxed this requires the
    /// security scope to open; unsandboxed the path alone is enough.
    static func canAccess(_ url: URL) -> Bool {
        guard isSandboxed else { return FileManager.default.fileExists(atPath: url.path) }
        return url.startAccessingSecurityScopedResource()
    }
}
