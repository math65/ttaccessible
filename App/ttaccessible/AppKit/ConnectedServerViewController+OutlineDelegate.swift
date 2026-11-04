//
//  ConnectedServerViewController+OutlineDelegate.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit

// MARK: - Display Formatters

extension ConnectedServerViewController {
    func displayText(for node: ServerTreeNode) -> String {
        switch node {
        case .channel(let channel):
            return visualChannelText(for: channel)
        case .user(let user):
            return visualUserText(for: user)
        }
    }

    func accessibilityText(for node: ServerTreeNode) -> String {
        switch node {
        case .channel(let channel):
            var parts = [visualChannelText(for: channel)]
            if channel.topic.isEmpty == false {
                parts.append(L10n.format("connectedServer.channel.topicOnlyFormat", channel.topic))
            }
            return parts.joined(separator: ", ")
        case .user(let user):
            return visualUserText(for: user)
        }
    }

    func visualChannelText(for channel: ConnectedServerChannel) -> String {
        let nameWithCount: String
        if channel.totalUserCount == 0 && channel.children.isEmpty {
            nameWithCount = channel.name
        } else if channel.children.isEmpty {
            nameWithCount = "\(channel.name) (\(channel.directUserCount))"
        } else {
            nameWithCount = "\(channel.name) (\(channel.directUserCount)/\(channel.totalUserCount))"
        }

        var parts = [nameWithCount]
        if channel.isCurrentChannel {
            parts.append(L10n.text("connectedServer.channel.currentSuffix"))
        }
        if channel.isPasswordProtected {
            parts.append(L10n.text("connectedServer.channel.passwordProtectedSuffix"))
        }
        if channel.isHidden {
            parts.append(L10n.text("connectedServer.channel.hiddenSuffix"))
        }
        return parts.joined(separator: ", ")
    }

    func visualUserText(for user: ConnectedServerUser) -> String {
        var parts = [user.displayName]
        parts.append(L10n.text(user.statusMode.localizationKey))
        if user.isCurrentUser {
            parts.append(L10n.text("connectedServer.user.currentSuffix"))
        }
        if user.isAdministrator {
            parts.append(L10n.text("connectedServer.user.administratorSuffix"))
        }
        if user.isChannelOperator {
            parts.append(L10n.text("connectedServer.user.channelOperatorSuffix"))
        }
        if user.isTalking {
            parts.append(L10n.text("connectedServer.user.talkingSuffix"))
        }
        parts.append(L10n.text(user.gender.localizationKey))
        if user.statusMessage.isEmpty == false {
            parts.append(user.statusMessage)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - NSOutlineViewDelegate

extension ConnectedServerViewController: NSOutlineViewDelegate {
    func outlineViewSelectionDidChange(_ notification: Notification) {
        selectedKey = currentSelectionKey()
        updateMenuState()
        updateVideoSelectionFromTree()
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if case .channel(let ch) = item as? ServerTreeNode, !ch.topic.isEmpty {
            return 34
        }
        return outlineView.rowHeight
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        ServerTreeRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard var node = item as? ServerTreeNode else { return nil }
        // The outline hands back the value it cached at the last full reload. A row redrawn
        // in place (reloadVisibleUserRows: talking, muted, video) must draw the user as the
        // session has them now, or your own row keeps its old "talking" after a mic toggle.
        if case .user(let cached) = node, let current = session.findUserByID(cached.id) {
            node = .user(current)
        }

        let identifier = NSUserInterfaceItemIdentifier("ConnectedServerCell")
        let textField: PressActionTextField

        if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? PressActionTextField {
            textField = cell
        } else {
            textField = PressActionTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingTail
        }

        let defaultActionName: String
        switch node {
        case .channel(let channel):
            defaultActionName = L10n.text(channel.isCurrentChannel
                ? "connectedServer.voAction.leave" : "connectedServer.voAction.join")
        case .user:
            defaultActionName = L10n.text("connectedServer.voAction.privateMessage")
        }
        let defaultAction = rowAccessibilityAction(name: defaultActionName, node: node) { controller, current in
            controller.performDefaultAction(for: current)
        }
        textField.onPress = { _ = defaultAction.handler?() }
        let serverID = session.savedServer.id
        textField.onShowMenu = { [weak self] in
            guard let self, self.session.savedServer.id == serverID,
                  let current = self.currentAccessibilityNode(matching: node),
                  self.selectNode(matching: self.selectionKey(for: current)) else { return false }
            return self.outlineView.accessibilityPerformShowMenu()
        }

        let accessLabel = accessibilityText(for: node)
        textField.toolTip = accessLabel
        textField.speaksToolTipAsHelp = false
        textField.readsLabelAsValue = true
        textField.setAccessibilityLabel(accessLabel)

        switch node {
        case .channel(let channel):
            let nameText = visualChannelText(for: channel)
            let nameFont: NSFont = channel.isCurrentChannel
                ? .boldSystemFont(ofSize: NSFont.systemFontSize)
                : .systemFont(ofSize: NSFont.systemFontSize)
            if channel.topic.isEmpty {
                textField.font = nameFont
                textField.stringValue = nameText
                textField.maximumNumberOfLines = 1
            } else {
                let attr = NSMutableAttributedString(
                    string: nameText,
                    attributes: [.font: nameFont]
                )
                attr.append(NSAttributedString(
                    string: "\n\(channel.topic)",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                ))
                textField.attributedStringValue = attr
                textField.maximumNumberOfLines = 2
            }
            var channelActions: [NSAccessibilityCustomAction] = [defaultAction]
            if !channel.users.isEmpty, canMoveUsers(from: channel) {
                channelActions.append(rowAccessibilityAction(
                    name: L10n.text("connectedServer.voAction.moveChannelUsers"), node: node
                ) { controller, current in
                    guard case .channel(let target) = current,
                          controller.canMoveUsers(from: target) else { return }
                    controller.presentMoveUsers(in: target)
                })
            }
            textField.setAccessibilityCustomActions(channelActions)
        case .user(let user):
            textField.font = user.isTalking
                ? .boldSystemFont(ofSize: NSFont.systemFontSize)
                : .systemFont(ofSize: NSFont.systemFontSize)
            textField.stringValue = visualUserText(for: user)
            textField.maximumNumberOfLines = 1
            var actions: [NSAccessibilityCustomAction] = [defaultAction]
            if !user.isCurrentUser {
                let isMuted = localMuteState[user.id] ?? user.isMuted
                let muteTitle = L10n.text(isMuted
                    ? "connectedServer.menu.unmuteUser" : "connectedServer.menu.muteUser")
                actions.append(rowAccessibilityAction(name: muteTitle, node: node) { controller, current in
                    guard case .user(let target) = current else { return }
                    controller.performToggleMute(target, presentingWindow: controller.view.window)
                })
                let mediaMuted = localMediaFileMuteState[user.id] ?? user.isMediaFileMuted
                let mediaTitle = L10n.text(mediaMuted
                    ? "connectedServer.menu.unmuteMediaFile" : "connectedServer.menu.muteMediaFile")
                actions.append(rowAccessibilityAction(name: mediaTitle, node: node) { controller, current in
                    guard case .user(let target) = current else { return }
                    controller.performToggleMuteMediaFile(target, presentingWindow: controller.view.window)
                })
                let me = session.currentUser
                if me?.isAdministrator == true || me?.isChannelOperator == true {
                    actions.append(rowAccessibilityAction(
                        name: L10n.text("connectedServer.menu.kickUser"), node: node
                    ) { controller, current in
                        guard case .user(let target) = current else { return }
                        controller.performKick(target, fromServer: false, presentingWindow: controller.view.window)
                    })
                    actions.append(rowAccessibilityAction(
                        name: L10n.text("connectedServer.menu.moveUser"), node: node
                    ) { controller, current in
                        guard case .user(let target) = current else { return }
                        controller.performMove([target], presentingWindow: controller.view.window)
                    })
                }
            }
            textField.setAccessibilityCustomActions(actions)
        }

        return textField
    }
}
