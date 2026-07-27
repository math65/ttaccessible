//
//  HelpBook.swift
//  ttaccessible
//
//  Opens the bundled Apple Help Book (ttaccessible.help) in the system help
//  viewer. Anchors are declared in the Markdown sources under Help/Source and
//  indexed by scripts/build-help-book.sh, so every case below must match an
//  `anchor:` in the front matter or an explicit <a id="…"> in a topic body.
//

import AppKit

/// A topic of the user guide. The raw value is the HTML anchor, except for
/// `index`, which is the book's home page and is opened through its access path.
enum HelpAnchor: String, CaseIterable {
    case index = "help-index"
    case gettingStarted = "getting-started"
    case servers = "servers"
    case mainWindow = "main-window"
    case channels = "channels"
    case talking = "talking"
    case messages = "messages"
    case mixer = "mixer"
    case audioSetup = "audio-setup"
    case recording = "recording"
    case streaming = "streaming"
    case users = "users"
    case administration = "administration"
    case preferences = "preferences"
    case soundsAndAnnouncements = "sounds-announcements"
    case profiles = "profiles"
    case shortcuts = "shortcuts"
    case troubleshooting = "troubleshooting"

    // Sub-anchors inside the Preferences topic, one per pane, so a help button
    // in Preferences lands on the pane the user is actually looking at.
    case preferencesGeneral = "prefs-general"
    case preferencesConnection = "prefs-connection"
    case preferencesBearWare = "prefs-bearware"
    case preferencesAudio = "prefs-audio"
    case preferencesSounds = "prefs-sounds"
    case preferencesAnnouncements = "prefs-announcements"
    case preferencesRecording = "prefs-recording"
}

/// A window or view controller that knows which help topic describes it.
@MainActor
protocol HelpAnchorProviding: AnyObject {
    var helpAnchor: HelpAnchor { get }
}

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

    static func open(_ anchor: HelpAnchor = .index) {
        guard isAvailable, let bookName else {
            NSWorkspace.shared.open(URL(string: "https://github.com/math65/ttaccessible")!)
            return
        }
        if anchor == .index {
            // The home page carries no anchor (it is excluded from the search
            // index), so it is reached through the book's access path.
            NSApp.showHelp(nil)
        } else {
            NSHelpManager.shared.openHelpAnchor(anchor.rawValue, inBook: bookName)
        }
    }

    /// Opens the topic that describes the frontmost window, falling back to the
    /// table of contents.
    static func openForKeyWindow() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            open()
            return
        }

        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if let provider = current as? HelpAnchorProviding {
                open(provider.helpAnchor)
                return
            }
            responder = current.nextResponder
        }

        if let provider = window.windowController as? HelpAnchorProviding {
            open(provider.helpAnchor)
            return
        }
        if let provider = window.contentViewController as? HelpAnchorProviding {
            open(provider.helpAnchor)
            return
        }
        open()
    }
}
