//
//  HelpAnchors.swift
//  ttaccessible
//
//  Maps each window onto the topic of the user guide that describes it, so the
//  Help menu (and any help button) opens the page for what the user is looking
//  at rather than the table of contents.
//
//  The Preferences window declares its own anchor next to the pane it tracks
//  (see PreferencesWindowController.swift).
//

import AppKit

extension SavedServersWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .servers }
}

extension ConnectedServerViewController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .mainWindow }
}

extension PrivateMessagesWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .messages }
}

extension ChannelFilesWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .channels }
}

extension ConnectedUsersWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .users }
}

extension UserInfoWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .users }
}

extension UserAccountsWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .administration }
}

extension BannedUsersWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .administration }
}

extension ProfilesWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .profiles }
}

extension MediaStreamingPlayerViewController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .streaming }
}

extension FeedbackWindowController: HelpAnchorProviding {
    var helpAnchor: HelpAnchor { .troubleshooting }
}
