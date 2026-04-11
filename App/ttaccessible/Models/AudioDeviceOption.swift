//
//  AudioDeviceOption.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct AudioDeviceOption: Identifiable, Equatable {
    let id: String
    let persistentID: String
    let displayName: String
}

struct AudioDeviceCatalog: Equatable {
    let inputDevices: [AudioDeviceOption]
    let outputDevices: [AudioDeviceOption]

    static let empty = AudioDeviceCatalog(inputDevices: [], outputDevices: [])
}
