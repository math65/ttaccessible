//
//  Localization.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

enum AppLanguagePreference: String, Codable, CaseIterable {
    case system
    case english
    case french

    var localizationKey: String {
        switch self {
        case .system:
            return "preferences.general.language.system"
        case .english:
            return "preferences.general.language.english"
        case .french:
            return "preferences.general.language.french"
        }
    }

    var languageCode: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .french:
            return "fr"
        }
    }
}

enum L10n {
    // `text`/`format` run on whichever thread is producing a status string or
    // announcement — including the real-time audio render thread — so reads
    // and the (rare) write from `configure` need a lock, not just `unsafe`.
    private static let lock = NSLock()
    private nonisolated(unsafe) static var overrideBundle: Bundle?

    nonisolated static func configure(languagePreference: AppLanguagePreference) {
        let newBundle: Bundle?
        if let languageCode = languagePreference.languageCode,
           let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") {
            newBundle = Bundle(path: path)
        } else {
            newBundle = nil
        }
        lock.lock()
        overrideBundle = newBundle
        lock.unlock()
    }

    nonisolated static func text(_ key: String) -> String {
        lock.lock()
        let bundle = overrideBundle
        lock.unlock()
        if let bundle {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return NSLocalizedString(key, comment: "")
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
