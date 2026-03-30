//
//  ChannelChatHistoryStore.swift
//  ttaccessible
//

import Foundation

final class ChannelChatHistoryStore {
    private let maxMessages = 300
    private let fileManager = FileManager.default

    private var storageDirectory: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ttaccessible/history", isDirectory: true)
    }

    func load(forKey key: String) -> [ChannelChatMessage] {
        guard let dir = storageDirectory,
              let url = fileURL(key: key, in: dir),
              let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([ChannelChatMessage].self, from: data) else {
            return []
        }
        return messages
    }

    func save(_ messages: [ChannelChatMessage], forKey key: String) {
        guard let dir = storageDirectory else { return }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let url = fileURL(key: key, in: dir) else { return }
        let trimmed = Array(messages.suffix(maxMessages))
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func fileURL(key: String, in dir: URL) -> URL? {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: ":", with: "_")
        guard !safe.isEmpty else { return nil }
        return dir.appendingPathComponent("\(safe).json")
    }
}
