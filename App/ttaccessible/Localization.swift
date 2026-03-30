//
//  Localization.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Foundation

enum L10n {
    nonisolated static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
