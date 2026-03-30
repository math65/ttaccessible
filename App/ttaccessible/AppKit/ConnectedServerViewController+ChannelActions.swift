//
//  ConnectedServerViewController+ChannelActions.swift
//  ttaccessible
//

import AppKit

extension ConnectedServerViewController {
    @objc func createChannelAction(_ sender: Any? = nil) {
        promptCreateChannel()
    }

    @objc func editChannelAction(_ sender: Any? = nil) {
        promptUpdateChannel()
    }

    @objc func deleteChannelAction(_ sender: Any? = nil) {
        promptDeleteChannel()
    }

    func promptCreateChannel() {
        guard let window = view.window else { return }

        // Parent = selected channel, or current channel, or root
        let parentID: Int32
        if let channel = selectedChannel {
            parentID = channel.id
        } else if session.currentChannelID > 0 {
            parentID = session.currentChannelID
        } else if let root = session.rootChannels.first {
            parentID = root.id
        } else {
            return
        }

        let props = ChannelProperties(
            name: "", topic: "", password: "", maxUsers: 200,
            isPermanent: false, isSoloTransmit: false, isNoVoiceActivation: false, isNoRecording: false
        )

        presentChannelDialog(
            title: L10n.text("connectedServer.channel.create.title"),
            properties: props,
            isCreate: true,
            window: window
        ) { [weak self] result, joinChannel in
            guard let self else { return }
            self.connectionController.createChannel(
                parentID: parentID,
                properties: result,
                joinAfterCreate: joinChannel
            ) { [weak self] outcome in
                switch outcome {
                case .success:
                    self?.announce(L10n.text("connectedServer.channel.create.success"))
                case .failure(let error):
                    self?.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    func promptUpdateChannel() {
        guard let window = view.window,
              let channel = selectedChannel else { return }

        guard let info = connectionController.channelInfo(forChannelID: channel.id) else { return }

        let props = ChannelProperties(
            name: info.name, topic: info.topic, password: info.password,
            maxUsers: info.maxUsers, isPermanent: info.isPermanent,
            isSoloTransmit: info.isSoloTransmit, isNoVoiceActivation: info.isNoVoiceActivation,
            isNoRecording: info.isNoRecording
        )

        presentChannelDialog(
            title: L10n.format("connectedServer.channel.edit.title", info.name),
            properties: props,
            isCreate: false,
            window: window
        ) { [weak self] result, _ in
            guard let self else { return }
            self.connectionController.updateChannel(channelID: channel.id, properties: result) { [weak self] outcome in
                switch outcome {
                case .success:
                    self?.announce(L10n.text("connectedServer.channel.edit.success"))
                case .failure(let error):
                    self?.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    func promptDeleteChannel() {
        guard let window = view.window,
              let channel = selectedChannel else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.format("connectedServer.channel.delete.title", channel.name)
        alert.informativeText = L10n.text("connectedServer.channel.delete.message")
        alert.addButton(withTitle: L10n.text("connectedServer.channel.delete.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.connectionController.deleteChannel(channelID: channel.id) { [weak self] outcome in
                switch outcome {
                case .success:
                    self?.announce(L10n.text("connectedServer.channel.delete.success"))
                case .failure(let error):
                    self?.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    func presentChannelDialog(
        title: String,
        properties: ChannelProperties,
        isCreate: Bool,
        window: NSWindow,
        completion: @escaping (ChannelProperties, Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = ""
        alert.addButton(withTitle: L10n.text("common.ok"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 0))

        let nameLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.name"))
        let nameField = NSTextField(frame: .zero)
        nameField.stringValue = properties.name
        nameField.placeholderString = L10n.text("connectedServer.channel.form.name")
        nameField.setAccessibilityLabel(L10n.text("connectedServer.channel.form.name"))

        let topicLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.topic"))
        let topicField = NSTextField(frame: .zero)
        topicField.stringValue = properties.topic
        topicField.placeholderString = L10n.text("connectedServer.channel.form.topic")
        topicField.setAccessibilityLabel(L10n.text("connectedServer.channel.form.topic"))

        let passwordLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.password"))
        let passwordField = NSSecureTextField(frame: .zero)
        passwordField.stringValue = properties.password
        passwordField.placeholderString = L10n.text("connectedServer.channel.form.password")
        passwordField.setAccessibilityLabel(L10n.text("connectedServer.channel.form.password"))

        let maxUsersLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.maxUsers"))
        let maxUsersField = NSTextField(frame: .zero)
        maxUsersField.stringValue = String(properties.maxUsers)
        maxUsersField.placeholderString = "200"
        maxUsersField.setAccessibilityLabel(L10n.text("connectedServer.channel.form.maxUsers"))

        let permanentCheck = NSButton(checkboxWithTitle: L10n.text("connectedServer.channel.form.permanent"), target: nil, action: nil)
        permanentCheck.state = properties.isPermanent ? .on : .off
        permanentCheck.setAccessibilityLabel(L10n.text("connectedServer.channel.form.permanent"))

        let soloCheck = NSButton(checkboxWithTitle: L10n.text("connectedServer.channel.form.soloTransmit"), target: nil, action: nil)
        soloCheck.state = properties.isSoloTransmit ? .on : .off
        soloCheck.setAccessibilityLabel(L10n.text("connectedServer.channel.form.soloTransmit"))

        let noVoxCheck = NSButton(checkboxWithTitle: L10n.text("connectedServer.channel.form.noVoiceActivation"), target: nil, action: nil)
        noVoxCheck.state = properties.isNoVoiceActivation ? .on : .off
        noVoxCheck.setAccessibilityLabel(L10n.text("connectedServer.channel.form.noVoiceActivation"))

        let noRecCheck = NSButton(checkboxWithTitle: L10n.text("connectedServer.channel.form.noRecording"), target: nil, action: nil)
        noRecCheck.state = properties.isNoRecording ? .on : .off
        noRecCheck.setAccessibilityLabel(L10n.text("connectedServer.channel.form.noRecording"))

        var joinCheck: NSButton?
        if isCreate {
            let check = NSButton(checkboxWithTitle: L10n.text("connectedServer.channel.form.joinAfterCreate"), target: nil, action: nil)
            check.state = .on
            check.setAccessibilityLabel(L10n.text("connectedServer.channel.form.joinAfterCreate"))
            joinCheck = check
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for item in [nameLabel, nameField, topicLabel, topicField, passwordLabel, passwordField, maxUsersLabel, maxUsersField] {
            item.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(item)
            if item !== nameLabel, item !== topicLabel, item !== passwordLabel, item !== maxUsersLabel {
                NSLayoutConstraint.activate([item.widthAnchor.constraint(equalToConstant: 320)])
            }
        }

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 320)])

        for check in [permanentCheck, soloCheck, noVoxCheck, noRecCheck] {
            stack.addArrangedSubview(check)
        }

        if let joinCheck {
            let joinSeparator = NSBox()
            joinSeparator.boxType = .separator
            stack.addArrangedSubview(joinSeparator)
            NSLayoutConstraint.activate([joinSeparator.widthAnchor.constraint(equalToConstant: 320)])
            stack.addArrangedSubview(joinCheck)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let fittingSize = stack.fittingSize
        container.frame = NSRect(x: 0, y: 0, width: 340, height: fittingSize.height)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let maxUsers = Int32(maxUsersField.stringValue) ?? 200
            let result = ChannelProperties(
                name: nameField.stringValue,
                topic: topicField.stringValue,
                password: passwordField.stringValue,
                maxUsers: max(1, maxUsers),
                isPermanent: permanentCheck.state == .on,
                isSoloTransmit: soloCheck.state == .on,
                isNoVoiceActivation: noVoxCheck.state == .on,
                isNoRecording: noRecCheck.state == .on
            )
            completion(result, joinCheck?.state == .on)
        }
    }

    @objc
    func joinSelectedChannel(_ sender: Any? = nil) {
        guard let channel = selectedChannel else {
            return
        }

        if channel.isCurrentChannel {
            announce(L10n.format("connectedServer.action.alreadyInChannel", displayText(for: .channel(channel))))
            return
        }

        if channel.isPasswordProtected {
            let initialPassword = connectionController.rememberedChannelPassword(for: channel.id)
            promptAndJoinProtectedChannel(channel, initialPassword: initialPassword, errorMessage: nil)
            return
        }

        joinChannel(channel, password: "")
    }

    @objc
    func leaveCurrentChannel(_ sender: Any? = nil) {
        guard session.currentChannelID > 0 else {
            announce(L10n.text("connectedServer.action.notInChannel"))
            return
        }

        connectionController.leaveCurrentChannel { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.announce(L10n.text("connectedServer.action.left"))
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    func joinChannel(_ channel: ConnectedServerChannel, password: String) {
        connectionController.joinChannel(id: channel.id, password: password) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.announce(L10n.format("connectedServer.action.joined", self.displayText(for: .channel(channel))))
            case .failure(let error as TeamTalkConnectionError):
                switch error {
                case .incorrectChannelPassword(let message):
                    self.promptAndJoinProtectedChannel(
                        channel,
                        initialPassword: password,
                        errorMessage: message.isEmpty ? nil : message
                    )
                default:
                    self.presentActionError(error.localizedDescription)
                }
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    func promptAndJoinProtectedChannel(
        _ channel: ConnectedServerChannel,
        initialPassword: String,
        errorMessage: String?
    ) {
        guard let window = view.window else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.format("connectedServer.channelPassword.title", displayText(for: .channel(channel)))
        alert.informativeText = errorMessage ?? L10n.text("connectedServer.channelPassword.message")
        alert.addButton(withTitle: L10n.text("connectedServer.channelPassword.join"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        passwordField.placeholderString = L10n.text("connectedServer.channelPassword.placeholder")
        passwordField.stringValue = initialPassword
        passwordField.setAccessibilityLabel(L10n.text("connectedServer.channelPassword.accessibilityLabel"))
        alert.accessoryView = passwordField

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else {
            return
        }

        joinChannel(channel, password: passwordField.stringValue)
    }

    func performDefaultAction() {
        switch selectedNode {
        case .channel(let channel):
            if channel.isCurrentChannel {
                leaveCurrentChannel(nil)
            } else {
                joinSelectedChannel(nil)
            }
        case .user:
            openPrivateConversation(nil)
        case .none:
            return
        }
    }

    @objc
    func openPrivateConversation(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode else {
            return
        }

        appDelegate.openPrivateConversation(userID: user.id, displayName: user.displayName)
    }
}
