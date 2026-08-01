//
//  HelpBook.swift
//  ttaccessible
//
//  Opens the bundled Apple Help Book (ttaccessible.help) in the system help
//  viewer. The guide always opens on its table of contents; navigation from
//  there is the reader's, not the app's.
//

import AppKit

@MainActor
enum HelpBook {
    /// Identifier of the help book, as declared in the app's Info.plist.
    static var bookName: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
    }

    /// The help book is a generated bundle committed to the repository; a build
    /// made before it was generated would otherwise trigger the system alert
    /// "Help isn't available for tt-Accessible".
    static var isAvailable: Bool {
        guard let folder = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookFolder") as? String,
              let resources = Bundle.main.resourceURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: resources.appendingPathComponent(folder).path)
    }

    /// Opens the guide on the page declared by the book's HPDBookAccessPath.
    static func open() {
        guard isAvailable, bookName != nil else {
            NSWorkspace.shared.open(URL(string: "https://github.com/math65/ttaccessible")!)
            return
        }
        NSApp.showHelp(nil)
    }
}
