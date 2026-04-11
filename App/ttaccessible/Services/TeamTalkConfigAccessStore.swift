//
//  TeamTalkConfigAccessStore.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

final class TeamTalkConfigAccessStore {
    private enum Keys {
        static let bookmarkData = "teamTalkImport.bookmarkData"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        userDefaults.set(data, forKey: Keys.bookmarkData)
    }

    func resolveURL() -> URL? {
        guard let data = userDefaults.data(forKey: Keys.bookmarkData) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            userDefaults.removeObject(forKey: Keys.bookmarkData)
            return nil
        }

        if isStale {
            try? saveBookmark(for: url)
        }

        return url
    }
}
