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
        guard let node = item as? ServerTreeNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("ConnectedServerCell")
        let textField: NSTextField

        if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = cell
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingTail
        }

        let accessLabel = accessibilityText(for: node)
        textField.toolTip = accessLabel
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
            let joinActionName = channel.isCurrentChannel
                ? L10n.text("connectedServer.voAction.leave")
                : L10n.text("connectedServer.voAction.join")
            textField.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: joinActionName) { [weak self] in
                    self?.performDefaultAction(); return true
                }
            ])
        case .user(let user):
            textField.font = user.isTalking
                ? .boldSystemFont(ofSize: NSFont.systemFontSize)
                : .systemFont(ofSize: NSFont.systemFontSize)
            textField.stringValue = visualUserText(for: user)
            textField.maximumNumberOfLines = 1
            var actions: [NSAccessibilityCustomAction] = [
                NSAccessibilityCustomAction(name: L10n.text("connectedServer.voAction.privateMessage")) { [weak self] in
                    self?.openPrivateConversation(nil); return true
                }
            ]
            if !user.isCurrentUser {
                let isMuted = localMuteState[user.id] ?? user.isMuted
                let muteTitle = isMuted
                    ? L10n.text("connectedServer.menu.unmuteUser")
                    : L10n.text("connectedServer.menu.muteUser")
                actions.append(NSAccessibilityCustomAction(name: muteTitle) { [weak self] in
                    self?.toggleMuteUserAction(); return true
                })
                let me = session.currentUser
                if me?.isAdministrator == true || me?.isChannelOperator == true {
                    actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedServer.menu.kickUser")) { [weak self] in
                        self?.kickUserAction(nil); return true
                    })
                    actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedServer.menu.moveUser")) { [weak self] in
                        self?.moveUserAction(nil); return true
                    })
                }
            }
            textField.setAccessibilityCustomActions(actions)
        }

        return textField
    }
}
