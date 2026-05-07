//
//  ConnectedServerViewController+UserActions.swift
//  ttaccessible
//

import AppKit

extension ConnectedServerViewController {
    @objc func adjustUserVolume(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              view.window != nil else { return }

        let storedVoiceVolume = connectionController.userVolumeStore.volume(forUsername: user.username)
        let storedMediaFileVolume = connectionController.userVolumeStore.mediaFileVolume(forUsername: user.username)
        let effectiveVoiceVolume = storedVoiceVolume ?? user.volumeVoice
        let effectiveMediaFileVolume = storedMediaFileVolume ?? user.volumeMediaFile
        let currentVoicePercent = TeamTalkConnectionController.percentFromUserVolume(effectiveVoiceVolume)
        let currentMediaFilePercent = TeamTalkConnectionController.percentFromUserVolume(effectiveMediaFileVolume)
        let originalVoiceVolume = effectiveVoiceVolume
        let originalMediaFileVolume = effectiveMediaFileVolume

        connectionController.getUserStereo(userID: user.id) { [weak self] currentLeft, currentRight in
            guard let self, let window = self.view.window else { return }
            let originalLeft = currentLeft
            let originalRight = currentRight

            let alert = NSAlert()
            alert.messageText = L10n.format("connectedServer.volume.title", user.displayName)
            alert.informativeText = L10n.text("connectedServer.volume.info")
            alert.addButton(withTitle: L10n.text("connectedServer.volume.ok"))
            alert.addButton(withTitle: L10n.text("connectedServer.volume.cancel"))

            let voiceHandler = VolumeSliderHandler(userID: user.id, stream: .voice, connectionController: self.connectionController)
            let voiceSlider = makeVolumeSlider(
                value: Double(currentVoicePercent),
                accessibilityLabel: L10n.text("connectedServer.volume.voiceSliderLabel"),
                handler: voiceHandler
            )
            let voiceValueLabel = makeVolumeValueLabel(value: voiceSlider.doubleValue)
            voiceHandler.valueLabel = voiceValueLabel

            let mediaFileHandler = VolumeSliderHandler(userID: user.id, stream: .mediaFile, connectionController: self.connectionController)
            let mediaFileSlider = makeVolumeSlider(
                value: Double(currentMediaFilePercent),
                accessibilityLabel: L10n.text("connectedServer.volume.mediaFileSliderLabel"),
                handler: mediaFileHandler
            )
            let mediaFileValueLabel = makeVolumeValueLabel(value: mediaFileSlider.doubleValue)
            mediaFileHandler.valueLabel = mediaFileValueLabel

            let leftCheck = NSButton(checkboxWithTitle: L10n.text("connectedServer.volume.leftSpeaker"), target: nil, action: nil)
            leftCheck.state = currentLeft ? .on : .off
            leftCheck.setAccessibilityLabel(L10n.text("connectedServer.volume.leftSpeaker"))

            let rightCheck = NSButton(checkboxWithTitle: L10n.text("connectedServer.volume.rightSpeaker"), target: nil, action: nil)
            rightCheck.state = currentRight ? .on : .off
            rightCheck.setAccessibilityLabel(L10n.text("connectedServer.volume.rightSpeaker"))

            let voiceRow = makeVolumeSliderRow(
                title: L10n.text("connectedServer.volume.voice"),
                slider: voiceSlider,
                valueLabel: voiceValueLabel
            )
            let mediaFileRow = makeVolumeSliderRow(
                title: L10n.text("connectedServer.volume.mediaFile"),
                slider: mediaFileSlider,
                valueLabel: mediaFileValueLabel
            )

            let container = NSStackView(views: [voiceRow, mediaFileRow, leftCheck, rightCheck])
            container.orientation = .vertical
            container.alignment = .leading
            container.spacing = 8
            container.frame = NSRect(x: 0, y: 0, width: 360, height: 124)

            alert.accessoryView = container
            alert.window.initialFirstResponder = voiceSlider

            objc_setAssociatedObject(alert, &VolumeSliderHandler.associatedKey, [voiceHandler, mediaFileHandler] as NSArray, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    let voiceVolume = TeamTalkConnectionController.userVolumeFromPercent(voiceSlider.doubleValue)
                    let mediaFileVolume = TeamTalkConnectionController.userVolumeFromPercent(mediaFileSlider.doubleValue)
                    self.connectionController.setUserVoiceVolume(userID: user.id, username: user.username, volume: voiceVolume)
                    self.connectionController.setUserMediaFileVolume(userID: user.id, username: user.username, volume: mediaFileVolume)
                    let newLeft = leftCheck.state == .on
                    let newRight = rightCheck.state == .on
                    self.connectionController.setUserStereo(
                        userID: user.id,
                        leftSpeaker: newLeft,
                        rightSpeaker: newRight
                    )
                    self.connectionController.userVolumeStore.setStereoBalance(
                        UserVolumeStore.StereoBalance(left: newLeft, right: newRight),
                        forUsername: user.username
                    )
                } else {
                    self.connectionController.setUserVoiceVolumeImmediate(userID: user.id, volume: originalVoiceVolume)
                    self.connectionController.setUserMediaFileVolumeImmediate(userID: user.id, volume: originalMediaFileVolume)
                    self.connectionController.setUserStereo(userID: user.id, leftSpeaker: originalLeft, rightSpeaker: originalRight)
                }
            }
        }
    }

    private func makeVolumeSlider(
        value: Double,
        accessibilityLabel: String,
        handler: VolumeSliderHandler
    ) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 100, target: handler, action: #selector(VolumeSliderHandler.sliderChanged(_:)))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.numberOfTickMarks = 0
        slider.altIncrementValue = 1
        slider.isContinuous = true
        slider.setAccessibilityLabel(accessibilityLabel)
        slider.setAccessibilityValueDescription(VolumeSliderHandler.formatPercent(slider.doubleValue))
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        slider.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return slider
    }

    private func makeVolumeValueLabel(value: Double) -> NSTextField {
        let valueLabel = NSTextField(labelWithString: VolumeSliderHandler.formatPercent(value))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setAccessibilityElement(false)
        valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return valueLabel
    }

    private func makeVolumeSliderRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true

        let row = NSStackView(views: [titleLabel, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc func toggleMuteUserAction(_ sender: Any? = nil) {
        guard case .user(let outlineUser)? = selectedNode, !outlineUser.isCurrentUser else { return }
        let userID = outlineUser.id
        let displayName = outlineUser.displayName
        let currentlyMuted = localMuteState[userID] ?? outlineUser.isMuted
        let newMuted = !currentlyMuted
        localMuteState[userID] = newMuted
        connectionController.muteUser(userID: userID, mute: newMuted)
        let announcement = newMuted
            ? L10n.format("connectedServer.mute.announced.muted", displayName)
            : L10n.format("connectedServer.mute.announced.unmuted", displayName)
        let element: Any = view.window ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: announcement,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
        updateMenuState()
        reloadVisibleUserRows(for: [userID])
    }

    @objc func toggleMuteUserMediaFileAction(_ sender: Any? = nil) {
        guard case .user(let outlineUser)? = selectedNode, !outlineUser.isCurrentUser else { return }
        let userID = outlineUser.id
        let displayName = outlineUser.displayName
        let currentlyMuted = localMediaFileMuteState[userID] ?? outlineUser.isMediaFileMuted
        let newMuted = !currentlyMuted
        localMediaFileMuteState[userID] = newMuted
        connectionController.muteUserMediaFile(userID: userID, mute: newMuted)
        let announcement = newMuted
            ? L10n.format("connectedServer.mediaFileMute.announced.muted", displayName)
            : L10n.format("connectedServer.mediaFileMute.announced.unmuted", displayName)
        let element: Any = view.window ?? NSApp as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: announcement,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
        updateMenuState()
        reloadVisibleUserRows(for: [userID])
    }

    @objc func toggleChannelOperatorAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode, !user.isCurrentUser else { return }
        let makeOp = !user.isChannelOperator
        let displayName = user.displayName

        let handleResult: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let key = makeOp ? "connectedServer.op.announced.promoted" : "connectedServer.op.announced.revoked"
                let announcement = L10n.format(key, displayName)
                let element: Any = self.view.window ?? NSApp as Any
                NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: announcement,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ])
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }

        if connectionController.hasOperatorEnableRight() || session.currentUser?.isAdministrator == true {
            connectionController.channelOp(userID: user.id, channelID: user.channelID, makeOperator: makeOp, completion: handleResult)
        } else {
            guard let window = view.window else { return }
            let alert = NSAlert()
            alert.messageText = L10n.text("connectedServer.op.passwordPrompt.title")
            alert.informativeText = L10n.text("connectedServer.op.passwordPrompt.message")
            alert.addButton(withTitle: L10n.text("connectedServer.volume.ok"))
            alert.addButton(withTitle: L10n.text("connectedServer.volume.cancel"))
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.placeholderString = L10n.text("connectedServer.op.passwordPrompt.placeholder")
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn, let self else { return }
                let password = field.stringValue
                self.connectionController.channelOpEx(userID: user.id, channelID: user.channelID, password: password, makeOperator: makeOp, completion: handleResult)
            }
        }
    }

    @objc func kickUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              !user.isCurrentUser else { return }

        if connectionController.preferencesStore.preferences.skipKickConfirmation {
            connectionController.kickUser(userID: user.id, channelID: user.channelID) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
            return
        }

        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.format("connectedServer.kick.title", user.displayName)
        alert.informativeText = L10n.text("connectedServer.kick.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("connectedServer.kick.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.connectionController.kickUser(userID: user.id, channelID: user.channelID) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
        }
    }

    @objc func kickUserFromServerAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              !user.isCurrentUser else { return }

        if connectionController.preferencesStore.preferences.skipKickConfirmation {
            connectionController.kickUser(userID: user.id, channelID: 0) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
            return
        }

        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.format("connectedServer.kickServer.title", user.displayName)
        alert.informativeText = L10n.text("connectedServer.kickServer.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("connectedServer.kick.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.connectionController.kickUser(userID: user.id, channelID: 0) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
        }
    }

    @objc func kickBanUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              !user.isCurrentUser,
              let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.format("bans.kickban.title", user.displayName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("bans.kickban.byIP"))
        alert.addButton(withTitle: L10n.text("bans.kickban.byUsername"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let banTypes: UInt32
            switch response {
            case .alertFirstButtonReturn:
                banTypes = UInt32(BANTYPE_IPADDR.rawValue)
            case .alertSecondButtonReturn:
                banTypes = UInt32(BANTYPE_USERNAME.rawValue)
            default:
                return
            }
            self.connectionController.kickAndBanUser(userID: user.id, banTypes: banTypes) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
        }
    }

    @objc func moveUserAction(_ sender: Any? = nil) {
        let users = selectedUserNodes()
        guard !users.isEmpty, let window = view.window else { return }

        // Available channels: all except the common channel if all users are in the same one
        let commonChannelID = users.count == 1 ? users[0].channelID : nil
        let allChannels = flatChannels(from: session.rootChannels)
        let channels = allChannels.filter { $0.id != commonChannelID }
        guard !channels.isEmpty else { return }

        let title = users.count == 1
            ? L10n.format("connectedServer.move.title", users[0].displayName)
            : L10n.format("connectedServer.move.title.multiple", users.count)

        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: L10n.text("connectedServer.move.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        channels.forEach { popup.addItem(withTitle: $0.name) }
        alert.accessoryView = popup
        alert.window.initialFirstResponder = popup

        alert.beginSheetModal(for: window) { [weak self] response in
            let selectedIndex = popup.indexOfSelectedItem
            guard response == .alertFirstButtonReturn, let self,
                  selectedIndex >= 0, selectedIndex < channels.count else { return }
            let target = channels[selectedIndex]
            for user in users {
                self.connectionController.moveUser(userID: user.id, toChannelID: target.id) { [weak self] result in
                    if case .failure(let error) = result {
                        self?.presentError(error)
                    }
                }
            }
        }
    }

    func selectedUserNodes() -> [ConnectedServerUser] {
        outlineView.selectedRowIndexes.compactMap { row in
            guard case .user(let user) = outlineView.item(atRow: row) as? ServerTreeNode else { return nil }
            return user
        }
    }

    func flatChannels(from channels: [ConnectedServerChannel]) -> [ConnectedServerChannel] {
        channels.flatMap { [$0] + flatChannels(from: $0.children) }
    }

    func setSelectedUsersSubscription(_ option: UserSubscriptionOption, enabled: Bool) {
        let users = selectedUserNodes().filter { $0.isCurrentUser == false }
        let userIDs = users.map(\.id)
        guard userIDs.isEmpty == false else {
            let element: Any = view.window ?? NSApp as Any
            NSAccessibility.post(
                element: element,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: L10n.text("subscriptions.error.noSelectedUser"),
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
            return
        }

        connectionController.setSubscription(option, forUserIDs: userIDs, enabled: enabled) { [weak self] result in
            if case .failure(let error) = result {
                self?.presentActionError(error.localizedDescription)
            }
        }
    }
}

private class VolumeSliderHandler: NSObject {
    enum Stream {
        case voice
        case mediaFile
    }

    static var associatedKey: UInt8 = 0
    let userID: Int32
    let stream: Stream
    let connectionController: TeamTalkConnectionController
    weak var valueLabel: NSTextField?

    init(userID: Int32, stream: Stream, connectionController: TeamTalkConnectionController) {
        self.userID = userID
        self.stream = stream
        self.connectionController = connectionController
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        let percent = sender.doubleValue.rounded()
        sender.doubleValue = percent
        let formatted = Self.formatPercent(percent)
        sender.setAccessibilityValueDescription(formatted)
        valueLabel?.stringValue = formatted
        let clamped = TeamTalkConnectionController.userVolumeFromPercent(percent)
        switch stream {
        case .voice:
            connectionController.setUserVoiceVolumeImmediate(userID: userID, volume: clamped)
        case .mediaFile:
            connectionController.setUserMediaFileVolumeImmediate(userID: userID, volume: clamped)
        }
    }

    static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", min(max(value.rounded(), 0), 100))
    }
}
