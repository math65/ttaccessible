//
//  TeamTalkStatusMode.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

enum TeamTalkStatusMode: Int32, CaseIterable, Equatable {
    case available = 0x00000000
    case away = 0x00000001
    case question = 0x00000002

    private static let modeMask: Int32 = 0x000000FF

    init(bitmask: Int32) {
        switch bitmask & Self.modeMask {
        case Self.away.rawValue:
            self = .away
        case Self.question.rawValue:
            self = .question
        default:
            self = .available
        }
    }

    func merged(with bitmask: Int32) -> Int32 {
        (bitmask & ~Self.modeMask) | rawValue
    }

    var localizationKey: String {
        switch self {
        case .available:
            return "connectedServer.statusMode.available"
        case .away:
            return "connectedServer.statusMode.away"
        case .question:
            return "connectedServer.statusMode.question"
        }
    }
}
