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

        let parentCodec = connectionController.channelInfo(forChannelID: parentID)?.opusCodec
        let props = ChannelProperties(
            name: "", topic: "", password: "", maxUsers: 200,
            isPermanent: false, isSoloTransmit: false, isNoVoiceActivation: false, isNoRecording: false,
            opusCodec: parentCodec ?? OpusCodecSettings.defaultSettings,
            diskQuotaBytes: 0
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
            isNoRecording: info.isNoRecording,
            opusCodec: info.opusCodec,
            diskQuotaBytes: info.diskQuotaBytes
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

        // File-storage quota with a KB/MB/GB unit picker; converted to the raw
        // bytes the SDK's nDiskQuota expects. Opens showing the largest unit
        // that divides the current value cleanly, and switching units converts
        // the displayed number in place.
        let diskQuotaLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.diskQuota"))
        let diskQuotaField = NSTextField(frame: .zero)
        diskQuotaField.placeholderString = "0"
        diskQuotaField.setAccessibilityLabel(L10n.text("connectedServer.channel.form.diskQuota"))

        let diskQuotaUnitPopUp = NSPopUpButton()
        for key in ["common.unit.kb", "common.unit.mb", "common.unit.gb"] {
            diskQuotaUnitPopUp.addItem(withTitle: L10n.text(key))
        }
        diskQuotaUnitPopUp.setAccessibilityLabel(L10n.text("connectedServer.channel.form.diskQuota.unit"))

        let diskQuotaConverter = DiskQuotaUnitConverter(
            field: diskQuotaField,
            popup: diskQuotaUnitPopUp,
            initialBytes: properties.diskQuotaBytes
        )

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

        // Audio codec controls
        let codecLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.codec.title"))
        codecLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let channelsLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.codec.channels"))
        let channelsPopUp = NSPopUpButton()
        channelsPopUp.addItem(withTitle: L10n.text("connectedServer.channel.form.codec.channels.mono"))
        channelsPopUp.lastItem?.tag = 1
        channelsPopUp.addItem(withTitle: L10n.text("connectedServer.channel.form.codec.channels.stereo"))
        channelsPopUp.lastItem?.tag = 2
        channelsPopUp.setAccessibilityLabel(L10n.text("connectedServer.channel.form.codec.channels"))
        if let codec = properties.opusCodec {
            channelsPopUp.selectItem(withTag: Int(codec.channels))
        }

        let sampleRateLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.codec.sampleRate"))
        let sampleRatePopUp = NSPopUpButton()
        for rate in OpusCodecSettings.supportedSampleRates {
            sampleRatePopUp.addItem(withTitle: "\(rate) Hz")
            sampleRatePopUp.lastItem?.tag = Int(rate)
        }
        sampleRatePopUp.setAccessibilityLabel(L10n.text("connectedServer.channel.form.codec.sampleRate"))
        if let codec = properties.opusCodec {
            sampleRatePopUp.selectItem(withTag: Int(codec.sampleRate))
        }

        let bitrateLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.codec.bitrate"))
        let bitrateField = NSTextField(frame: .zero)
        bitrateField.stringValue = properties.opusCodec.map { String($0.bitrate / 1000) } ?? "64"
        bitrateField.placeholderString = "64"
        bitrateField.setAccessibilityLabel(L10n.text("connectedServer.channel.form.codec.bitrate"))

        let applicationLabel = NSTextField(labelWithString: L10n.text("connectedServer.channel.form.codec.application"))
        let applicationPopUp = NSPopUpButton()
        applicationPopUp.addItem(withTitle: L10n.text("connectedServer.channel.form.codec.application.voip"))
        applicationPopUp.lastItem?.tag = 2048 // OPUS_APPLICATION_VOIP
        applicationPopUp.addItem(withTitle: L10n.text("connectedServer.channel.form.codec.application.music"))
        applicationPopUp.lastItem?.tag = 2049 // OPUS_APPLICATION_AUDIO
        applicationPopUp.setAccessibilityLabel(L10n.text("connectedServer.channel.form.codec.application"))
        if let codec = properties.opusCodec {
            applicationPopUp.selectItem(withTag: Int(codec.application))
        }

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

        diskQuotaLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(diskQuotaLabel)
        let diskQuotaRow = NSStackView(views: [diskQuotaField, diskQuotaUnitPopUp])
        diskQuotaRow.orientation = .horizontal
        diskQuotaRow.spacing = 8
        diskQuotaField.translatesAutoresizingMaskIntoConstraints = false
        diskQuotaUnitPopUp.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            diskQuotaField.widthAnchor.constraint(equalToConstant: 232),
            diskQuotaUnitPopUp.widthAnchor.constraint(equalToConstant: 80)
        ])
        stack.addArrangedSubview(diskQuotaRow)

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 320)])

        for check in [permanentCheck, soloCheck, noVoxCheck, noRecCheck] {
            stack.addArrangedSubview(check)
        }

        // Codec section
        let codecSeparator = NSBox()
        codecSeparator.boxType = .separator
        stack.addArrangedSubview(codecSeparator)
        NSLayoutConstraint.activate([codecSeparator.widthAnchor.constraint(equalToConstant: 320)])

        stack.addArrangedSubview(codecLabel)
        for (lbl, control) in [(channelsLabel, channelsPopUp), (sampleRateLabel, sampleRatePopUp), (applicationLabel, applicationPopUp)] as [(NSTextField, NSPopUpButton)] {
            let row = NSStackView(views: [lbl, control])
            row.orientation = .horizontal
            row.spacing = 8
            lbl.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([lbl.widthAnchor.constraint(equalToConstant: 120)])
            stack.addArrangedSubview(row)
        }
        let bitrateRow = NSStackView(views: [bitrateLabel, bitrateField])
        bitrateRow.orientation = .horizontal
        bitrateRow.spacing = 8
        bitrateLabel.translatesAutoresizingMaskIntoConstraints = false
        bitrateField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bitrateLabel.widthAnchor.constraint(equalToConstant: 120),
            bitrateField.widthAnchor.constraint(equalToConstant: 80)
        ])
        stack.addArrangedSubview(bitrateRow)

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

        alert.beginSheetModal(for: window) { [weak self] response in
            _ = self
            guard response == .alertFirstButtonReturn else { return }
            let maxUsers = Int32(maxUsersField.stringValue) ?? 200
            let bitrateKbps = Int32(bitrateField.stringValue) ?? 64
            let codec = OpusCodecSettings(
                channels: Int32(channelsPopUp.selectedItem?.tag ?? 1),
                sampleRate: Int32(sampleRatePopUp.selectedItem?.tag ?? 48000),
                bitrate: max(6000, min(510000, bitrateKbps * 1000)),
                application: Int32(applicationPopUp.selectedItem?.tag ?? 2048)
            )
            let diskQuotaBytes = diskQuotaConverter.currentBytes
            let result = ChannelProperties(
                name: nameField.stringValue,
                topic: topicField.stringValue,
                password: passwordField.stringValue,
                maxUsers: max(1, maxUsers),
                isPermanent: permanentCheck.state == .on,
                isSoloTransmit: soloCheck.state == .on,
                isNoVoiceActivation: noVoxCheck.state == .on,
                isNoRecording: noRecCheck.state == .on,
                opusCodec: codec,
                diskQuotaBytes: diskQuotaBytes
            )
            completion(result, joinCheck?.state == .on)
        }
    }

    @objc
    func joinSelectedChannel(_ sender: Any? = nil) {
        guard let channel = selectedChannel else {
            return
        }
        join(channel)
    }

    func join(_ channel: ConnectedServerChannel) {
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
        guard let node = selectedNode else {
            return
        }
        performDefaultAction(for: node)
    }

    // Action par défaut sur un nœud explicite (la ligne sous le curseur VoiceOver),
    // sans dépendre de la sélection : sans interaction le tableau n'a aucune ligne
    // sélectionnée, mais VO-Espace doit quand même agir sur la ligne pressée.
    func performDefaultAction(for node: ServerTreeNode) {
        switch node {
        case .channel(let channel):
            if channel.isCurrentChannel {
                leaveCurrentChannel(nil)
            } else {
                join(channel)
            }
        case .user(let user):
            appDelegate.openPrivateConversation(userID: user.id, displayName: user.displayName)
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

/// Keeps the channel disk-quota field and its KB/MB/GB popup in sync: switching
/// units converts the displayed number in place, while the underlying byte
/// value stays exact — display rounding never drifts the stored quota unless
/// the user actually edits the text. Retained by the dialog's completion
/// closure for the lifetime of the sheet.
private final class DiskQuotaUnitConverter: NSObject {
    private let field: NSTextField
    private let popup: NSPopUpButton
    private let multipliers: [Int64] = [1 << 10, 1 << 20, 1 << 30]
    private var trueBytes: Int64
    private var lastRenderedText = ""
    private var lastUnitIndex: Int

    init(field: NSTextField, popup: NSPopUpButton, initialBytes: Int64) {
        self.field = field
        self.popup = popup
        self.trueBytes = max(0, initialBytes)
        // Largest unit that divides the value cleanly.
        if trueBytes > 0, trueBytes % (1 << 30) == 0 {
            lastUnitIndex = 2
        } else if trueBytes > 0, trueBytes % (1 << 20) == 0 {
            lastUnitIndex = 1
        } else {
            lastUnitIndex = 0
        }
        super.init()
        popup.target = self
        popup.action = #selector(unitChanged)
        render()
    }

    /// The quota in bytes as currently shown: the exact original value while
    /// the text is untouched, otherwise the edited number times the unit.
    var currentBytes: Int64 {
        bytesParsingField(withUnit: lastUnitIndex)
    }

    @objc private func unitChanged() {
        let newIndex = max(0, min(popup.indexOfSelectedItem, multipliers.count - 1))
        guard newIndex != lastUnitIndex else { return }
        // Absorb any manual edit in the old unit before converting the display.
        trueBytes = bytesParsingField(withUnit: lastUnitIndex)
        lastUnitIndex = newIndex
        render()
    }

    private func bytesParsingField(withUnit index: Int) -> Int64 {
        if field.stringValue == lastRenderedText {
            return trueBytes
        }
        // Accept a decimal comma (French keyboards) as well as a point.
        let normalized = field.stringValue
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else {
            return trueBytes
        }
        let bytes = (value * Double(multipliers[index])).rounded()
        return bytes >= Double(Int64.max) ? Int64.max : Int64(bytes)
    }

    private func render() {
        let multiplier = multipliers[lastUnitIndex]
        let text: String
        if trueBytes % multiplier == 0 {
            text = String(trueBytes / multiplier)
        } else {
            text = String(format: "%.2f", Double(trueBytes) / Double(multiplier))
        }
        field.stringValue = text
        lastRenderedText = text
        popup.selectItem(at: lastUnitIndex)
    }
}
