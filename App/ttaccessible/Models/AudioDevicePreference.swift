//
//  AudioDevicePreference.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct AudioDevicePreference: Codable, Equatable {
    var persistentID: String?
    var displayName: String?

    static let systemDefault = AudioDevicePreference(persistentID: nil, displayName: nil)

    nonisolated var usesSystemDefault: Bool {
        persistentID?.isEmpty != false
    }
}
