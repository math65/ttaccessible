//
//  ConnectedServerViewController+TransmitControl.swift
//  ttaccessible
//
//  The "Transmit Control" submenu, as in the Qt client: in the User menu and in
//  the channel tree's context menu. For the selected user, one line per stream
//  (channel messages, voice, video, desktop, media file); in a classroom, the
//  same lines again for everyone. Selecting a channel row offers the "everyone"
//  lines alone.
//

import AppKit

/// The channel the submenu edits, and the user it is about (nil for a channel row).
struct TransmitControlTarget {
    let channel: ConnectedServerChannel
    let user: ConnectedServerUser?

    var menuState: TransmitControlMenuState {
        let list = channel.transmitUsers
        return TransmitControlMenuState(
            allowedForUser: user.map { user in
                Set(TransmitStream.allCases.filter { list.isAllowed($0, userID: user.id) })
            },
            allowedForEveryone: list.isClassroom
                ? Set(TransmitStream.allCases.filter { list.isAllowedForEveryone($0) })
                : nil
        )
    }
}

extension TransmitStream {
    var userMenuTitleKey: String {
        switch self {
        case .channelMessages: return "transmitControl.menu.user.channelMessages"
        case .voice: return "transmitControl.menu.user.voice"
        case .video: return "transmitControl.menu.user.video"
        case .desktop: return "transmitControl.menu.user.desktop"
        case .mediaFile: return "transmitControl.menu.user.mediaFile"
        }
    }

    var everyoneMenuTitleKey: String {
        switch self {
        case .channelMessages: return "transmitControl.menu.everyone.channelMessages"
        case .voice: return "transmitControl.menu.everyone.voice"
        case .video: return "transmitControl.menu.everyone.video"
        case .desktop: return "transmitControl.menu.everyone.desktop"
        case .mediaFile: return "transmitControl.menu.everyone.mediaFile"
        }
    }

    /// The phrase the confirmations slot in ("speak", "share their desktop"…).
    var announcementPhraseKey: String {
        switch self {
        case .channelMessages: return "transmitControl.stream.channelMessages"
        case .voice: return "transmitControl.stream.voice"
        case .video: return "transmitControl.stream.video"
        case .desktop: return "transmitControl.stream.desktop"
        case .mediaFile: return "transmitControl.stream.mediaFile"
        }
    }
}

extension ConnectedServerViewController: NSMenuDelegate {
    static let transmitControlMenuItemIdentifier = NSUserInterfaceItemIdentifier("transmitControl")

    /// What the submenu would act on right now, or nil when it doesn't apply:
    /// more than one row selected, no right to edit that channel's list, or a
    /// channel row outside a classroom (where only per-user lines exist).
    ///
    /// Reads the channel from the current session rather than from the outline
    /// item, which can be stale (see `localMuteState`).
    func transmitControlTarget() -> TransmitControlTarget? {
        guard outlineView.selectedRowIndexes.count == 1 else { return nil }
        switch selectedNode {
        case .user(let selected)?:
            let user = session.findUserByID(selected.id) ?? selected
            guard let channel = session.findChannelByID(user.channelID),
                  channel.canControlTransmission else { return nil }
            return TransmitControlTarget(channel: channel, user: user)
        case .channel(let selected)?:
            guard let channel = session.findChannelByID(selected.id),
                  channel.canControlTransmission,
                  channel.transmitUsers.isClassroom else { return nil }
            return TransmitControlTarget(channel: channel, user: nil)
        case nil:
            return nil
        }
    }

    func makeTransmitControlMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.text("transmitControl.menu.title"), action: nil, keyEquivalent: "")
        item.identifier = Self.transmitControlMenuItemIdentifier
        item.submenu = NSMenu(title: L10n.text("transmitControl.menu.title"))
        return item
    }

    /// The context menu is built once; the submenu's lines and checkmarks are
    /// rebuilt each time it opens. The whole item is hidden, not dimmed, where it
    /// doesn't apply — a dead entry is one more stop under VoiceOver.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === contextMenu,
              let item = menu.items.first(where: { $0.identifier == Self.transmitControlMenuItemIdentifier }),
              let submenu = item.submenu else { return }
        submenu.removeAllItems()
        guard let target = transmitControlTarget() else {
            item.isHidden = true
            return
        }
        item.isHidden = false
        let state = target.menuState
        if let allowed = state.allowedForUser {
            for stream in TransmitStream.allCases {
                let line = NSMenuItem(
                    title: L10n.text(stream.userMenuTitleKey),
                    action: #selector(toggleUserTransmissionAction(_:)),
                    keyEquivalent: ""
                )
                line.target = self
                line.tag = stream.rawValue
                line.state = allowed.contains(stream) ? .on : .off
                submenu.addItem(line)
            }
        }
        if let allowed = state.allowedForEveryone {
            if state.allowedForUser != nil {
                submenu.addItem(.separator())
            }
            for stream in TransmitStream.allCases {
                let line = NSMenuItem(
                    title: L10n.text(stream.everyoneMenuTitleKey),
                    action: #selector(toggleEveryoneTransmissionAction(_:)),
                    keyEquivalent: ""
                )
                line.target = self
                line.tag = stream.rawValue
                line.state = allowed.contains(stream) ? .on : .off
                submenu.addItem(line)
            }
        }
    }

    @objc func toggleUserTransmissionAction(_ sender: NSMenuItem) {
        guard let stream = TransmitStream(rawValue: sender.tag) else { return }
        setSelectionTransmission(stream, allowed: sender.state != .on, forEveryone: false)
    }

    @objc func toggleEveryoneTransmissionAction(_ sender: NSMenuItem) {
        guard let stream = TransmitStream(rawValue: sender.tag) else { return }
        setSelectionTransmission(stream, allowed: sender.state != .on, forEveryone: true)
    }

    /// Shared by the context menu and the User menu.
    func setSelectionTransmission(_ stream: TransmitStream, allowed: Bool, forEveryone: Bool) {
        guard let target = transmitControlTarget() else { return }
        let userID: Int32
        let announcement: String
        let phrase = L10n.text(stream.announcementPhraseKey)
        if forEveryone {
            guard target.channel.transmitUsers.isClassroom else { return }
            userID = TransmitUsersList.everyoneUserID
            announcement = L10n.format(
                allowed ? "transmitControl.announce.everyoneAllowed" : "transmitControl.announce.everyoneForbidden",
                phrase
            )
        } else {
            guard let user = target.user else { return }
            userID = user.id
            // In a classroom open to everyone for this stream, taking someone off
            // the list changes nothing they can hear or do: say so rather than
            // "can no longer speak", which would be false.
            let stillOpenToEveryone = target.channel.transmitUsers.isAllowedForEveryone(stream)
            let key: String
            if allowed {
                key = "transmitControl.announce.userAllowed"
            } else if stillOpenToEveryone {
                key = "transmitControl.announce.userUnlistedEveryoneAllowed"
            } else {
                key = "transmitControl.announce.userForbidden"
            }
            announcement = L10n.format(key, user.displayName, phrase)
        }
        connectionController.setTransmission(
            stream,
            allowed: allowed,
            userID: userID,
            channelID: target.channel.id
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.announce(announcement)
            case .failure(let error):
                self.presentActionError(error)
            }
        }
    }
}
