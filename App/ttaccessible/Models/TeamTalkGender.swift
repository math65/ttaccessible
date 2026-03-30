//
//  TeamTalkGender.swift
//  ttaccessible
//

import Foundation

enum TeamTalkGender: Int, CaseIterable, Codable, Equatable {
    case male = 1
    case female = 2
    case neutral = 3

    private static let femaleFlag: Int32 = 0x00000100
    private static let neutralFlag: Int32 = 0x00001000
    private static let genderMask: Int32 = femaleFlag | neutralFlag

    init(ttFileValue: Int) {
        switch ttFileValue {
        case Self.female.rawValue:
            self = .female
        case Self.neutral.rawValue:
            self = .neutral
        default:
            self = .male
        }
    }

    init(statusBitmask: Int32) {
        if (statusBitmask & Self.neutralFlag) != 0 {
            self = .neutral
        } else if (statusBitmask & Self.femaleFlag) != 0 {
            self = .female
        } else {
            self = .male
        }
    }

    var localizationKey: String {
        switch self {
        case .male:
            return "teamTalk.gender.male"
        case .female:
            return "teamTalk.gender.female"
        case .neutral:
            return "teamTalk.gender.neutral"
        }
    }

    var statusFlag: Int32 {
        switch self {
        case .male:
            return 0
        case .female:
            return Self.femaleFlag
        case .neutral:
            return Self.neutralFlag
        }
    }

    func merged(with statusBitmask: Int32) -> Int32 {
        (statusBitmask & ~Self.genderMask) | statusFlag
    }
}
