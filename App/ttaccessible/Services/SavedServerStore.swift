//
//  SavedServerStore.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

final class SavedServerStore {
    private enum Keys {
        static let records = "savedServers.records"
        static let selectedID = "savedServers.selectedID"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedRecords: [SavedServerRecord]
    private var cachedSelectedID: UUID?
    private var pendingPersistWorkItem: DispatchWorkItem?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Keys.records),
           let decoded = try? decoder.decode([SavedServerRecord].self, from: data) {
            cachedRecords = decoded
        } else {
            cachedRecords = []
        }
        if let value = userDefaults.string(forKey: Keys.selectedID) {
            cachedSelectedID = UUID(uuidString: value)
        } else {
            cachedSelectedID = nil
        }
    }

    func load() -> [SavedServerRecord] {
        cachedRecords
    }

    func saveAll(_ records: [SavedServerRecord]) {
        cachedRecords = records
        schedulePersist()
    }

    func add(_ record: SavedServerRecord) {
        var records = load()
        records.append(record)
        saveAll(records)
    }

    func update(_ record: SavedServerRecord) {
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return
        }
        records[index] = record
        saveAll(records)
    }

    func delete(id: UUID) {
        var records = load()
        records.removeAll { $0.id == id }
        saveAll(records)
        if selectedServerID() == id {
            setSelectedServer(id: nil)
        }
    }

    func setSelectedServer(id: UUID?) {
        cachedSelectedID = id
        userDefaults.set(id?.uuidString, forKey: Keys.selectedID)
    }

    func selectedServerID() -> UUID? {
        cachedSelectedID
    }

    private func schedulePersist() {
        pendingPersistWorkItem?.cancel()
        let snapshot = cachedRecords
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(snapshot)
                self.userDefaults.set(data, forKey: Keys.records)
            } catch {
                self.userDefaults.removeObject(forKey: Keys.records)
            }
        }
        pendingPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }
}
