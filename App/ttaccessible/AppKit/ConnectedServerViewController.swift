//
//  ConnectedServerViewController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import UniformTypeIdentifiers

final class AudioGainControlView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0, minValue: -24, maxValue: 24, target: nil, action: nil)
    private var valueDB: Double = 0
    private var onChange: ((Double) -> Void)?

    init(title: String, accessibilityLabel: String, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)

        titleLabel.stringValue = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setAccessibilityElement(false)

        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(handleSliderChanged(_:))
        slider.setAccessibilityElement(false)

        let stack = NSStackView(views: [titleLabel, slider, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(
                name: L10n.text("connectedServer.audio.gain.resetAccessibilityAction"),
                target: self,
                selector: #selector(resetToZeroAccessibilityAction)
            )
        ])

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        setValue(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setValue(_ value: Double) {
        valueDB = min(max(value.rounded(), -24), 24)
        slider.doubleValue = valueDB
        let text = Self.format(valueDB)
        valueLabel.stringValue = text
        setAccessibilityValue(text)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow, .downArrow:
            adjust(by: -1)
        case .rightArrow, .upArrow:
            adjust(by: 1)
        case .pageUp:
            adjust(by: 10)
        case .pageDown:
            adjust(by: -10)
        case .home:
            setAndNotify(-24)
        case .end:
            setAndNotify(24)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        adjust(by: 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        adjust(by: -1)
        return true
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        self
    }

    @objc
    func resetToZeroAccessibilityAction() -> Bool {
        setValue(0)
        onChange?(0)
        return true
    }

    @objc
    private func handleSliderChanged(_ sender: NSSlider) {
        let rounded = sender.doubleValue.rounded()
        setValue(rounded)
        onChange?(rounded)
    }

    private func adjust(by delta: Double) {
        let updated = min(max((valueDB + delta).rounded(), -24), 24)
        setAndNotify(updated)
    }

    private func setAndNotify(_ value: Double) {
        guard value != valueDB else {
            return
        }
        setValue(value)
        onChange?(valueDB)
    }

    private static func format(_ value: Double) -> String {
        if value > 0 {
            return String(format: "+%.0f dB", value)
        }
        return String(format: "%.0f dB", value)
    }
}

// Row view qui ne remonte pas les custom actions de ses enfants vers VoiceOver.
private final class ServerTreeRowView: NSTableRowView {
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? { nil }
}


final class ConnectedServerViewController: NSViewController {
    private enum Column {
        static let main = NSUserInterfaceItemIdentifier("main")
        static let chat = NSUserInterfaceItemIdentifier("chat")
    }

    private enum SelectionKey: Equatable {
        case channel(Int32)
        case user(Int32)
    }

    private let preferencesStore: AppPreferencesStore
    private let connectionController: TeamTalkConnectionController
    private let menuState: SavedServersMenuState
    private unowned let appDelegate: AppDelegate
    private let outlineView = ConnectedServerOutlineView(frame: .zero)
    private let chatTableView = NSTableView(frame: .zero)
    private let historyTableView = NSTableView(frame: .zero)
    private let channelsScrollView = NSScrollView(frame: .zero)
    private let chatScrollView = NSScrollView(frame: .zero)
    private let historyScrollView = NSScrollView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let audioStatusLabel = NSTextField(labelWithString: "")
    private let chatTitleLabel = NSTextField(labelWithString: "")
    private let historyTitleLabel = NSTextField(labelWithString: "")
    private let messageField = NSTextField(frame: .zero)
    private let sendButton = NSButton(title: "", target: nil, action: nil)
    private let microphoneButton = NSButton(title: "", target: nil, action: nil)
    private lazy var inputGainControl = AudioGainControlView(
        title: L10n.text("connectedServer.audio.inputGain.label"),
        accessibilityLabel: L10n.text("connectedServer.audio.inputGain.accessibilityLabel")
    ) { [weak self] value in
        self?.applyInputGain(value)
    }
    private lazy var outputGainControl = AudioGainControlView(
        title: L10n.text("connectedServer.audio.outputGain.label"),
        accessibilityLabel: L10n.text("connectedServer.audio.outputGain.accessibilityLabel")
    ) { [weak self] value in
        self?.applyOutputGain(value)
    }
    private lazy var contextMenu: NSMenu = makeContextMenu()

    private var session: ConnectedServerSession
    private var selectedKey: SelectionKey?
    private var needsInitialFocus = true
    private var lastAnnouncedChannelID: Int32 = 0
    private var lastAnnouncedChannelMessageID: UUID?
    private var lastAnnouncedHistoryEntryID: UUID?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(
        session: ConnectedServerSession,
        preferencesStore: AppPreferencesStore,
        connectionController: TeamTalkConnectionController,
        menuState: SavedServersMenuState,
        appDelegate: AppDelegate
    ) {
        self.session = session
        self.preferencesStore = preferencesStore
        self.connectionController = connectionController
        self.menuState = menuState
        self.appDelegate = appDelegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        configureUI()
        applySession(session, preserveSelection: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusOutlineIfNeeded()
    }

    func update(session: ConnectedServerSession) {
        applySession(session, preserveSelection: true)
    }

    func showReconnecting() {
        statusLabel.stringValue = L10n.text("connectedServer.reconnecting")
        NSAccessibility.post(element: statusLabel, notification: .valueChanged)
    }

    func focusChannels() {
        view.window?.makeFirstResponder(outlineView)
    }

    func focusChatHistory() {
        view.window?.makeFirstResponder(chatTableView)
    }

    func focusHistory() {
        view.window?.makeFirstResponder(historyTableView)
    }

    func focusMessageInput() {
        guard messageField.isEnabled else {
            return
        }
        view.window?.makeFirstResponder(messageField)
    }

    func performJoinShortcut() {
        joinSelectedChannel(nil)
    }

    func performLeaveShortcut() {
        leaveCurrentChannel(nil)
    }

    func performMessagesShortcut() {
        focusMessageInput()
    }

    func performToggleMicrophoneShortcut() {
        toggleMicrophone(nil)
    }

    func promptChangeNickname() {
        guard let window = view.window else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("connectedServer.identity.nickname.title")
        alert.informativeText = L10n.text("connectedServer.identity.nickname.message")
        alert.addButton(withTitle: L10n.text("common.save"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = session.currentNickname
        field.placeholderString = L10n.text("connectedServer.identity.nickname.placeholder")
        field.setAccessibilityLabel(L10n.text("connectedServer.identity.nickname.field"))
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        connectionController.changeNickname(to: field.stringValue) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.announce(L10n.text("connectedServer.identity.nickname.updated"))
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    func promptChangeStatus() {
        guard let window = view.window else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("connectedServer.identity.status.title")
        alert.informativeText = L10n.text("connectedServer.identity.status.message")
        alert.addButton(withTitle: L10n.text("common.save"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let modeButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        TeamTalkStatusMode.allCases.forEach { mode in
            modeButton.addItem(withTitle: L10n.text(mode.localizationKey))
            modeButton.lastItem?.representedObject = mode.rawValue
        }
        if let index = TeamTalkStatusMode.allCases.firstIndex(of: session.currentStatusMode) {
            modeButton.selectItem(at: index)
        }
        modeButton.setAccessibilityLabel(L10n.text("connectedServer.identity.status.mode"))

        let genderButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        TeamTalkGender.allCases.forEach { gender in
            genderButton.addItem(withTitle: L10n.text(gender.localizationKey))
            genderButton.lastItem?.representedObject = gender.rawValue
        }
        if let index = TeamTalkGender.allCases.firstIndex(of: session.currentGender) {
            genderButton.selectItem(at: index)
        }
        genderButton.setAccessibilityLabel(L10n.text("connectedServer.identity.status.gender"))

        let messageField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        messageField.stringValue = session.currentStatusMessage
        messageField.placeholderString = L10n.text("connectedServer.identity.status.placeholder")
        messageField.setAccessibilityLabel(L10n.text("connectedServer.identity.status.messageField"))

        let stack = NSStackView(views: [modeButton, genderButton, messageField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let selectedMode = TeamTalkStatusMode(
            rawValue: modeButton.selectedItem?.representedObject as? Int32 ?? TeamTalkStatusMode.available.rawValue
        ) ?? .available
        let selectedGender = TeamTalkGender(
            ttFileValue: genderButton.selectedItem?.representedObject as? Int ?? TeamTalkGender.neutral.rawValue
        )

        connectionController.changeStatus(mode: selectedMode, message: messageField.stringValue) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                if selectedGender != self.session.currentGender {
                    self.connectionController.changeGender(selectedGender) { [weak self] genderResult in
                        guard let self else {
                            return
                        }
                        switch genderResult {
                        case .success:
                            self.announce(L10n.text("connectedServer.identity.status.updated"))
                        case .failure(let error):
                            self.presentActionError(error.localizedDescription)
                        }
                    }
                } else {
                    self.announce(L10n.text("connectedServer.identity.status.updated"))
                }
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    private func configureUI() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view = backgroundView

        titleLabel.font = .preferredFont(forTextStyle: .title2)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        audioStatusLabel.textColor = .secondaryLabelColor
        audioStatusLabel.lineBreakMode = .byWordWrapping
        audioStatusLabel.maximumNumberOfLines = 2
        audioStatusLabel.setAccessibilityLabel(L10n.text("connectedServer.audio.status.accessibilityLabel"))

        chatTitleLabel.font = .preferredFont(forTextStyle: .headline)
        chatTitleLabel.stringValue = L10n.text("connectedServer.chat.title")

        historyTitleLabel.font = .preferredFont(forTextStyle: .headline)
        historyTitleLabel.stringValue = L10n.text("connectedServer.history.title")

        let column = NSTableColumn(identifier: Column.main)
        column.title = L10n.text("connectedServer.outline.column")
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        if #available(macOS 11.0, *) {
            outlineView.style = .sourceList
        }
        outlineView.rowSizeStyle = .default
        outlineView.focusRingType = .default
        outlineView.allowsMultipleSelection = true
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.actionDelegate = self
        outlineView.setAccessibilityLabel(L10n.text("connectedServer.outline.accessibilityLabel"))
        outlineView.menu = contextMenu

        channelsScrollView.documentView = outlineView
        channelsScrollView.hasVerticalScroller = true
        channelsScrollView.borderType = .noBorder
        channelsScrollView.drawsBackground = false

        let chatColumn = NSTableColumn(identifier: Column.chat)
        chatColumn.title = L10n.text("connectedServer.chat.column")
        chatTableView.addTableColumn(chatColumn)
        chatTableView.headerView = nil
        if #available(macOS 11.0, *) {
            chatTableView.style = .inset
        }
        chatTableView.usesAlternatingRowBackgroundColors = false
        chatTableView.selectionHighlightStyle = .regular
        chatTableView.focusRingType = .default
        chatTableView.allowsEmptySelection = true
        chatTableView.rowSizeStyle = .large
        chatTableView.delegate = self
        chatTableView.dataSource = self
        chatTableView.setAccessibilityLabel(L10n.text("connectedServer.chat.history.accessibilityLabel"))

        chatScrollView.documentView = chatTableView
        chatScrollView.hasVerticalScroller = true
        chatScrollView.borderType = .noBorder
        chatScrollView.drawsBackground = false

        let historyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        historyColumn.title = L10n.text("connectedServer.history.column")
        historyTableView.addTableColumn(historyColumn)
        historyTableView.headerView = nil
        if #available(macOS 11.0, *) {
            historyTableView.style = .inset
        }
        historyTableView.usesAlternatingRowBackgroundColors = false
        historyTableView.selectionHighlightStyle = .regular
        historyTableView.focusRingType = .default
        historyTableView.allowsEmptySelection = true
        historyTableView.rowSizeStyle = .default
        historyTableView.delegate = self
        historyTableView.dataSource = self
        historyTableView.setAccessibilityLabel(L10n.text("connectedServer.history.accessibilityLabel"))

        historyScrollView.documentView = historyTableView
        historyScrollView.hasVerticalScroller = true
        historyScrollView.borderType = .noBorder
        historyScrollView.drawsBackground = false

        messageField.placeholderString = L10n.text("connectedServer.chat.input.placeholder")
        messageField.delegate = self
        messageField.target = self
        messageField.action = #selector(sendCurrentMessage)
        messageField.setAccessibilityLabel(L10n.text("connectedServer.chat.input.accessibilityLabel"))

        sendButton.title = L10n.text("connectedServer.chat.send")
        sendButton.target = self
        sendButton.action = #selector(sendCurrentMessage)
        sendButton.setAccessibilityLabel(L10n.text("connectedServer.chat.send.accessibilityLabel"))

        microphoneButton.target = self
        microphoneButton.action = #selector(toggleMicrophone)
        microphoneButton.bezelStyle = .rounded

        // -- Layout en colonne unique --
        // Ordre : titre, statut, recherche, liste canaux, gains, audio, chat, message, historique

        let inputStack = NSStackView(views: [messageField, sendButton])
        inputStack.orientation = .horizontal
        inputStack.alignment = .centerY
        inputStack.spacing = 12
        inputStack.translatesAutoresizingMaskIntoConstraints = false

        channelsScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [
            titleLabel,
            statusLabel,
            audioStatusLabel,
            microphoneButton,
            channelsScrollView,
            outputGainControl,
            inputGainControl,
            chatTitleLabel,
            chatScrollView,
            inputStack,
            historyTitleLabel,
            historyScrollView
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            channelsScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            channelsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            outputGainControl.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            inputGainControl.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            chatScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            chatScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            inputStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            historyScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            historyScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            microphoneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
    }

    private func applySession(_ session: ConnectedServerSession, preserveSelection: Bool) {
        let previousSession = self.session
        if preserveSelection == false {
            selectedKey = nil
        }

        self.session = session
        titleLabel.stringValue = session.displayName
        statusLabel.stringValue = session.statusText
        audioStatusLabel.stringValue = session.audioStatusText

        // Only reload chat/history tables when their data actually changed.
        if previousSession.channelChatHistory != session.channelChatHistory {
            applyIncrementalTableUpdate(
                tableView: chatTableView,
                previousCount: previousSession.channelChatHistory.count,
                newItems: session.channelChatHistory,
                oldItems: previousSession.channelChatHistory
            )
            scrollChatToBottomIfNeeded()
        }
        if previousSession.sessionHistory != session.sessionHistory {
            let shouldScrollHistoryToBottom = shouldScrollHistoryToBottomAfterReload()
            applyIncrementalTableUpdate(
                tableView: historyTableView,
                previousCount: previousSession.sessionHistory.count,
                newItems: session.sessionHistory,
                oldItems: previousSession.sessionHistory
            )
            scrollHistoryToBottomIfNeeded(shouldScroll: shouldScrollHistoryToBottom)
        }
        updateChatInputState()
        updateAudioControls()

        // Only reload the outline when the channel tree or user list changed.
        let treeChanged = previousSession.rootChannels != session.rootChannels
        if treeChanged || !preserveSelection {
            let existingSelection = preserveSelection ? currentSelectionKey() ?? selectedKey : nil
            outlineView.reloadData()
            expandAllChannels()

            if restoreSelection(existingSelection) == false {
                selectDefaultRow()
            }
        }

        if preserveSelection == false {
            needsInitialFocus = true
        }
        updateMenuState()
        announceChannelChangeIfNeeded(previousChannelID: lastAnnouncedChannelID, newChannelID: session.currentChannelID)
        announceNewChannelMessageIfNeeded(previousSession: previousSession, newSession: session, preserveSelection: preserveSelection)
        announceNewHistoryEntryIfNeeded(previousSession: previousSession, newSession: session)
        lastAnnouncedChannelID = session.currentChannelID
        focusOutlineIfNeeded()
    }

    func applyAudioRuntimeUpdate(_ update: ConnectedServerAudioRuntimeUpdate) {
        var changedUserIDs = Set<Int32>()
        let updatedRoots = updateAudioState(
            in: session.rootChannels,
            updates: update.userAudioStates,
            changedUserIDs: &changedUserIDs
        )

        guard changedUserIDs.isEmpty == false
            || session.voiceTransmissionEnabled != update.voiceTransmissionEnabled
            || session.audioStatusText != update.audioStatusText
            || session.inputAudioReady != update.inputAudioReady
            || session.outputAudioReady != update.outputAudioReady else {
            return
        }

        session = ConnectedServerSession(
            savedServer: session.savedServer,
            displayName: session.displayName,
            currentNickname: session.currentNickname,
            currentStatusMode: session.currentStatusMode,
            currentStatusMessage: session.currentStatusMessage,
            currentGender: session.currentGender,
            statusText: session.statusText,
            currentChannelID: session.currentChannelID,
            isAdministrator: session.isAdministrator,
            rootChannels: updatedRoots,
            channelChatHistory: session.channelChatHistory,
            sessionHistory: session.sessionHistory,
            privateConversations: session.privateConversations,
            selectedPrivateConversationUserID: session.selectedPrivateConversationUserID,
            channelFiles: session.channelFiles,
            activeTransfers: session.activeTransfers,
            outputAudioReady: update.outputAudioReady,
            inputAudioReady: update.inputAudioReady,
            voiceTransmissionEnabled: update.voiceTransmissionEnabled,
            canSendBroadcast: session.canSendBroadcast,
            audioStatusText: update.audioStatusText,
            inputGainDB: session.inputGainDB,
            outputGainDB: session.outputGainDB
        )

        updateAudioControls()
        reloadVisibleUserRows(for: changedUserIDs)
    }

    private func updateMenuState() {
        let selectedUsers = selectedUserNodes()
            .filter { $0.isCurrentUser == false }
        let allSelectedUsers = selectedUserNodes()
        menuState.setConnectedState(
            hasSelectedChannel: selectedChannel != nil,
            isInChannel: session.currentChannelID > 0
        )
        menuState.setSelectedUsersState(
            hasSelectedUsers: selectedUsers.isEmpty == false,
            hasSingleSelectedUser: allSelectedUsers.count == 1,
            states: Dictionary(
                uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
                    (option, selectedUsers.isEmpty == false && selectedUsers.allSatisfy { $0.isSubscriptionEnabled(option) })
                }
            )
        )
    }

    private func updateChatInputState() {
        let isInChannel = session.currentChannelID > 0
        messageField.isEnabled = isInChannel
        sendButton.isEnabled = isInChannel && messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if isInChannel == false {
            messageField.stringValue = ""
        }
    }

    private func updateAudioControls() {
        microphoneButton.title = session.voiceTransmissionEnabled
            ? L10n.text("connectedServer.audio.microphone.disable")
            : L10n.text("connectedServer.audio.microphone.enable")
        microphoneButton.isEnabled = session.currentChannelID > 0 || session.voiceTransmissionEnabled
        microphoneButton.setAccessibilityLabel(L10n.text("connectedServer.audio.microphone.accessibilityLabel"))
        microphoneButton.setAccessibilityValue(session.audioStatusText)
        inputGainControl.setValue(session.inputGainDB)
        outputGainControl.setValue(session.outputGainDB)
    }

    private func applyIncrementalTableUpdate<T: Equatable>(
        tableView: NSTableView,
        previousCount: Int,
        newItems: [T],
        oldItems: [T]
    ) {
        if newItems.count >= oldItems.count,
           Array(newItems.prefix(oldItems.count)) == oldItems {
            let inserted = IndexSet(integersIn: oldItems.count ..< newItems.count)
            if inserted.isEmpty == false {
                tableView.beginUpdates()
                tableView.insertRows(at: inserted, withAnimation: [])
                tableView.endUpdates()
                return
            }
        }

        tableView.reloadData()
    }

    private func updateAudioState(
        in channels: [ConnectedServerChannel],
        updates: [Int32: ConnectedUserAudioState],
        changedUserIDs: inout Set<Int32>
    ) -> [ConnectedServerChannel] {
        channels.map { channel in
            let updatedUsers = channel.users.map { user in
                guard let update = updates[user.id] else {
                    return user
                }
                guard user.isTalking != update.isTalking || user.isMuted != update.isMuted else {
                    return user
                }
                changedUserIDs.insert(user.id)
                return ConnectedServerUser(
                    id: user.id,
                    username: user.username,
                    nickname: user.nickname,
                    channelID: user.channelID,
                    statusMode: user.statusMode,
                    statusMessage: user.statusMessage,
                    gender: user.gender,
                    isCurrentUser: user.isCurrentUser,
                    isAdministrator: user.isAdministrator,
                    isChannelOperator: user.isChannelOperator,
                    isTalking: update.isTalking,
                    isMuted: update.isMuted,
                    isAway: user.isAway,
                    isQuestion: user.isQuestion,
                    ipAddress: user.ipAddress,
                    clientName: user.clientName,
                    clientVersion: user.clientVersion,
                    volumeVoice: user.volumeVoice,
                    subscriptionStates: user.subscriptionStates,
                    channelPathComponents: user.channelPathComponents
                )
            }
            let updatedChildren = updateAudioState(in: channel.children, updates: updates, changedUserIDs: &changedUserIDs)
            return ConnectedServerChannel(
                id: channel.id,
                parentID: channel.parentID,
                name: channel.name,
                topic: channel.topic,
                isPasswordProtected: channel.isPasswordProtected,
                isHidden: channel.isHidden,
                isCurrentChannel: channel.isCurrentChannel,
                pathComponents: channel.pathComponents,
                children: updatedChildren,
                users: updatedUsers
            )
        }
    }

    private func reloadVisibleUserRows(for userIDs: Set<Int32>) {
        guard userIDs.isEmpty == false else {
            return
        }
        let rows = IndexSet(
            (0 ..< outlineView.numberOfRows).compactMap { row in
                guard case .user(let user) = outlineView.item(atRow: row) as? ServerTreeNode,
                      userIDs.contains(user.id) else {
                    return nil
                }
                return row
            }
        )
        guard rows.isEmpty == false else {
            return
        }
        outlineView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
    }

    private func applyInputGain(_ value: Double) {
        let normalized = AppPreferences.clampGainDB(value)
        preferencesStore.updateInputGainDB(normalized)
        connectionController.applyInputGainDB(normalized)
        session = ConnectedServerSession(
            savedServer: session.savedServer,
            displayName: session.displayName,
            currentNickname: session.currentNickname,
            currentStatusMode: session.currentStatusMode,
            currentStatusMessage: session.currentStatusMessage,
            currentGender: session.currentGender,
            statusText: session.statusText,
            currentChannelID: session.currentChannelID,
            isAdministrator: session.isAdministrator,
            rootChannels: session.rootChannels,
            channelChatHistory: session.channelChatHistory,
            sessionHistory: session.sessionHistory,
            privateConversations: session.privateConversations,
            selectedPrivateConversationUserID: session.selectedPrivateConversationUserID,
            channelFiles: session.channelFiles,
            activeTransfers: session.activeTransfers,
            outputAudioReady: session.outputAudioReady,
            inputAudioReady: session.inputAudioReady,
            voiceTransmissionEnabled: session.voiceTransmissionEnabled,
            canSendBroadcast: session.canSendBroadcast,
            audioStatusText: session.audioStatusText,
            inputGainDB: normalized,
            outputGainDB: session.outputGainDB
        )
        updateAudioControls()
    }

    private func applyOutputGain(_ value: Double) {
        let normalized = AppPreferences.clampGainDB(value)
        preferencesStore.updateOutputGainDB(normalized)
        connectionController.applyOutputGainDB(normalized)
        session = ConnectedServerSession(
            savedServer: session.savedServer,
            displayName: session.displayName,
            currentNickname: session.currentNickname,
            currentStatusMode: session.currentStatusMode,
            currentStatusMessage: session.currentStatusMessage,
            currentGender: session.currentGender,
            statusText: session.statusText,
            currentChannelID: session.currentChannelID,
            isAdministrator: session.isAdministrator,
            rootChannels: session.rootChannels,
            channelChatHistory: session.channelChatHistory,
            sessionHistory: session.sessionHistory,
            privateConversations: session.privateConversations,
            selectedPrivateConversationUserID: session.selectedPrivateConversationUserID,
            channelFiles: session.channelFiles,
            activeTransfers: session.activeTransfers,
            outputAudioReady: session.outputAudioReady,
            inputAudioReady: session.inputAudioReady,
            voiceTransmissionEnabled: session.voiceTransmissionEnabled,
            canSendBroadcast: session.canSendBroadcast,
            audioStatusText: session.audioStatusText,
            inputGainDB: session.inputGainDB,
            outputGainDB: normalized
        )
        updateAudioControls()
    }

    func promptBroadcastMessage() {
        guard let window = view.window else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("broadcast.prompt.title")
        alert.informativeText = L10n.text("broadcast.prompt.message")
        alert.addButton(withTitle: L10n.text("common.ok"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.placeholderString = L10n.text("broadcast.prompt.placeholder")
        textField.setAccessibilityLabel(L10n.text("broadcast.prompt.accessibilityLabel"))
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else {
                return
            }

            let message = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard message.isEmpty == false else {
                return
            }

            self.connectionController.sendBroadcastMessage(message) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    func setSelectedUsersSubscription(_ option: UserSubscriptionOption, enabled: Bool) {
        let users = selectedUserNodes().filter { $0.isCurrentUser == false }
        let userIDs = users.map(\.id)
        guard userIDs.isEmpty == false else {
            return
        }

        connectionController.setSubscription(option, forUserIDs: userIDs, enabled: enabled) { [weak self] result in
            if case .failure(let error) = result {
                self?.presentActionError(error.localizedDescription)
            }
        }
    }


    private func announceChannelChangeIfNeeded(previousChannelID: Int32, newChannelID: Int32) {
        guard previousChannelID != 0, previousChannelID != newChannelID else {
            return
        }

        if newChannelID > 0 {
            announce(L10n.text("connectedServer.accessibility.channelChanged"))
        } else {
            announce(L10n.text("connectedServer.accessibility.channelLeft"))
        }
    }

    private func announceNewChannelMessageIfNeeded(
        previousSession: ConnectedServerSession,
        newSession: ConnectedServerSession,
        preserveSelection: Bool
    ) {
        guard preferencesStore.preferences.voiceOverAnnouncements.channelMessagesEnabled else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        guard preserveSelection else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        let previousCount = previousSession.channelChatHistory.count
        let newCount = newSession.channelChatHistory.count

        guard newCount > previousCount else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        let appendedMessages = newSession.channelChatHistory.suffix(newCount - previousCount)
        guard let latestIncomingMessage = appendedMessages.reversed().first(where: { $0.isOwnMessage == false }) else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        guard latestIncomingMessage.id != lastAnnouncedChannelMessageID else {
            lastAnnouncedChannelMessageID = newSession.channelChatHistory.last?.id
            return
        }

        let isCurrentChannelChatVisible = isViewLoaded
            && view.window?.isVisible == true
            && NSApp.isActive
            && newSession.currentChannelID == latestIncomingMessage.channelID

        let announcementKey = isCurrentChannelChatVisible
            ? "connectedServer.chat.accessibility.messageSpoken"
            : "connectedServer.chat.accessibility.newMessage"

        announce(
            L10n.format(
                announcementKey,
                latestIncomingMessage.senderDisplayName,
                latestIncomingMessage.message
            )
        )
        lastAnnouncedChannelMessageID = latestIncomingMessage.id
    }


    private func scrollChatToBottomIfNeeded() {
        let rowCount = session.channelChatHistory.count
        guard rowCount > 0 else {
            return
        }

        chatTableView.scrollRowToVisible(rowCount - 1)
    }

    private func shouldScrollHistoryToBottomAfterReload() -> Bool {
        let rowCount = historyTableView.numberOfRows
        guard rowCount > 0 else {
            return true
        }

        if view.window?.firstResponder !== historyTableView {
            return true
        }

        let visibleRect = historyTableView.visibleRect
        return visibleRect.maxY >= historyTableView.bounds.maxY - 12
    }

    private func scrollHistoryToBottomIfNeeded(shouldScroll: Bool) {
        guard shouldScroll else {
            return
        }

        let rowCount = session.sessionHistory.count
        guard rowCount > 0 else {
            return
        }

        historyTableView.scrollRowToVisible(rowCount - 1)
    }

    private func announceNewHistoryEntryIfNeeded(previousSession: ConnectedServerSession, newSession: ConnectedServerSession) {
        guard preferencesStore.preferences.voiceOverAnnouncements.sessionHistoryEnabled else {
            lastAnnouncedHistoryEntryID = newSession.sessionHistory.last?.id
            return
        }

        guard let latestEntry = SessionHistoryAnnouncementHelper.latestAppendedEntry(
            previous: previousSession.sessionHistory,
            current: newSession.sessionHistory,
            filter: { [preferencesStore] entry in
                SessionHistoryAnnouncementHelper.shouldAnnounceForegroundHistoryEntry(
                    entry,
                    broadcastMessagesEnabled: preferencesStore.preferences.voiceOverAnnouncements.broadcastMessagesEnabled
                )
            }
        ) else {
            lastAnnouncedHistoryEntryID = newSession.sessionHistory.last?.id
            return
        }

        guard latestEntry.id != lastAnnouncedHistoryEntryID else {
            lastAnnouncedHistoryEntryID = newSession.sessionHistory.last?.id
            return
        }

        announce(latestEntry.message)
        lastAnnouncedHistoryEntryID = latestEntry.id
    }

    private func chatAccessibilityText(for message: ChannelChatMessage) -> String {
        let timestamp = timeFormatter.string(from: message.receivedAt)
        let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
        return "\(senderName) : \(message.message), \(timestamp)"
    }

    private func historyAccessibilityText(for entry: SessionHistoryEntry) -> String {
        "\(entry.message), \(timeFormatter.string(from: entry.timestamp))"
    }

    private func height(for message: ChannelChatMessage, width: CGFloat) -> CGFloat {
        let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
        let senderHeight = NSAttributedString(
            string: "\(senderName), \(timeFormatter.string(from: message.receivedAt))",
            attributes: [.font: NSFont.preferredFont(forTextStyle: .subheadline)]
        ).boundingRect(
            with: NSSize(width: max(width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        let messageHeight = NSAttributedString(
            string: message.message,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).boundingRect(
            with: NSSize(width: max(width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        return ceil(senderHeight + messageHeight + 24)
    }

    private func height(for entry: SessionHistoryEntry, width: CGFloat) -> CGFloat {
        let text = historyAccessibilityText(for: entry)
        let textHeight = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        ).boundingRect(
            with: NSSize(width: max(width - 20, 100), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height

        return ceil(textHeight + 20)
    }

    private var selectedNode: ServerTreeNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else {
            return nil
        }
        return outlineView.item(atRow: row) as? ServerTreeNode
    }

    private var selectedChannel: ConnectedServerChannel? {
        guard case .channel(let channel)? = selectedNode else {
            return nil
        }
        return channel
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.text("connectedServer.menu.contextTitle"))

        let joinItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.join"),
            action: #selector(joinSelectedChannel),
            keyEquivalent: ""
        )
        joinItem.target = self
        menu.addItem(joinItem)

        let leaveItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.leave"),
            action: #selector(leaveCurrentChannel),
            keyEquivalent: ""
        )
        leaveItem.target = self
        menu.addItem(leaveItem)

        let privateMessageItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.privateMessage"),
            action: #selector(openPrivateConversation),
            keyEquivalent: ""
        )
        privateMessageItem.target = self
        menu.addItem(privateMessageItem)

        let volumeItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.userVolume"),
            action: #selector(adjustUserVolume),
            keyEquivalent: ""
        )
        volumeItem.target = self
        menu.addItem(volumeItem)

        let muteItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.muteUser"),
            action: #selector(toggleMuteUserAction),
            keyEquivalent: ""
        )
        muteItem.target = self
        menu.addItem(muteItem)

        let kickItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.kickUser"),
            action: #selector(kickUserAction),
            keyEquivalent: ""
        )
        kickItem.target = self
        menu.addItem(kickItem)

        let kickBanItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.kickBanUser"),
            action: #selector(kickBanUserAction),
            keyEquivalent: ""
        )
        kickBanItem.target = self
        menu.addItem(kickBanItem)

        let moveItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.moveUser"),
            action: #selector(moveUserAction),
            keyEquivalent: ""
        )
        moveItem.target = self
        menu.addItem(moveItem)

        menu.addItem(.separator())

        let createItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.createChannel"),
            action: #selector(createChannelAction),
            keyEquivalent: ""
        )
        createItem.target = self
        menu.addItem(createItem)

        let editItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.editChannel"),
            action: #selector(editChannelAction),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        let deleteItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.deleteChannel"),
            action: #selector(deleteChannelAction),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func adjustUserVolume(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              let window = view.window else { return }

        let volDefault = Double(SOUND_VOLUME_DEFAULT.rawValue)
        let storedVolume = connectionController.userVolumeStore.volume(forUsername: user.username)
        let effectiveVolume = storedVolume ?? user.volumeVoice
        let currentPercent = Int(Double(effectiveVolume) / volDefault * 100)

        let alert = NSAlert()
        alert.messageText = L10n.format("connectedServer.volume.title", user.displayName)
        alert.informativeText = L10n.text("connectedServer.volume.info")
        alert.addButton(withTitle: L10n.text("connectedServer.volume.ok"))
        alert.addButton(withTitle: L10n.text("connectedServer.volume.cancel"))

        let slider = NSSlider(value: Double(currentPercent), minValue: 0, maxValue: 200, target: nil, action: nil)
        slider.numberOfTickMarks = 0
        slider.isContinuous = true
        slider.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        slider.setAccessibilityLabel(L10n.text("connectedServer.volume.sliderLabel"))
        alert.accessoryView = slider
        alert.window.initialFirstResponder = slider

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let percent = Int(slider.doubleValue)
            let raw = Int32(Double(percent) / 100.0 * Double(SOUND_VOLUME_DEFAULT.rawValue))
            let clamped = max(Int32(SOUND_VOLUME_MIN.rawValue), min(Int32(SOUND_VOLUME_MAX.rawValue), raw))
            self.connectionController.setUserVoiceVolume(userID: user.id, username: user.username, volume: clamped)
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isUser = { if case .user? = self.selectedNode { return true }; return false }()
        let selectedUser: ConnectedServerUser? = { if case .user(let u) = self.selectedNode { return u }; return nil }()
        let isOther = isUser && selectedUser?.isCurrentUser == false
        let canModerate: Bool = {
            guard let me = session.currentUser else { return false }
            return me.isAdministrator || me.isChannelOperator
        }()
        switch menuItem.action {
        case #selector(toggleMuteUserAction):
            let muted = selectedUser?.isMuted == true
            menuItem.title = muted ? L10n.text("connectedServer.menu.unmuteUser") : L10n.text("connectedServer.menu.muteUser")
            return isOther
        case #selector(kickUserAction):
            return isOther && canModerate
        case #selector(kickBanUserAction):
            return isOther && session.isAdministrator
        case #selector(moveUserAction):
            // L'utilisateur courant peut se déplacer lui-même ; sinon admin/op requis
            let selectedUsers = selectedUserNodes()
            guard !selectedUsers.isEmpty else { return false }
            let hasOthers = selectedUsers.contains { !$0.isCurrentUser }
            return !hasOthers || canModerate
        default:
            return true
        }
    }

    @objc private func toggleMuteUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode, !user.isCurrentUser else { return }
        connectionController.muteUser(userID: user.id, mute: !user.isMuted)
    }

    @objc private func kickUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              !user.isCurrentUser,
              let window = view.window else { return }

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

    @objc private func kickBanUserAction(_ sender: Any? = nil) {
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

    @objc private func moveUserAction(_ sender: Any? = nil) {
        let users = selectedUserNodes()
        guard !users.isEmpty, let window = view.window else { return }

        // Canaux disponibles : tous sauf le canal commun si tous les utilisateurs sont dans le même
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
            guard response == .alertFirstButtonReturn, let self else { return }
            let target = channels[popup.indexOfSelectedItem]
            for user in users {
                self.connectionController.moveUser(userID: user.id, toChannelID: target.id) { [weak self] result in
                    if case .failure(let error) = result {
                        self?.presentError(error)
                    }
                }
            }
        }
    }

    private func selectedUserNodes() -> [ConnectedServerUser] {
        outlineView.selectedRowIndexes.compactMap { row in
            guard case .user(let user) = outlineView.item(atRow: row) as? ServerTreeNode else { return nil }
            return user
        }
    }

    private func flatChannels(from channels: [ConnectedServerChannel]) -> [ConnectedServerChannel] {
        channels.flatMap { [$0] + flatChannels(from: $0.children) }
    }

    @objc func announceAudioStateAction(_ sender: Any? = nil) {
        announce(session.audioStatusText)
    }

    @objc func exportChatHistory(_ sender: Any? = nil) {
        guard !session.channelChatHistory.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("export.panel.title")
        panel.nameFieldStringValue = "chat-\(session.displayName).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = session.channelChatHistory.map { msg in
            let time = DateFormatter.localizedString(from: msg.receivedAt, dateStyle: .short, timeStyle: .short)
            return "[\(time)] \(msg.senderDisplayName) : \(msg.message)"
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @objc private func createChannelAction(_ sender: Any? = nil) {
        promptCreateChannel()
    }

    @objc private func editChannelAction(_ sender: Any? = nil) {
        promptUpdateChannel()
    }

    @objc private func deleteChannelAction(_ sender: Any? = nil) {
        promptDeleteChannel()
    }

    func promptServerProperties() {
        guard let window = view.window,
              let props = connectionController.getServerProperties() else { return }
        let vc = ServerPropertiesViewController(properties: props)
        vc.onSave = { [weak self] updated in
            self?.connectionController.updateServerProperties(updated) { [weak self] result in
                switch result {
                case .success:
                    self?.announce(L10n.text("serverProperties.announced.updated"))
                case .failure(let error):
                    self?.presentActionError(error.localizedDescription)
                }
            }
        }
        window.contentViewController?.presentAsSheet(vc)
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

    private func presentChannelDialog(
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

    private func expandAllChannels() {
        outlineView.expandItem(nil, expandChildren: true)
    }

    private func focusOutlineIfNeeded() {
        guard needsInitialFocus, view.window != nil else {
            return
        }

        needsInitialFocus = false
        view.window?.makeFirstResponder(outlineView)
    }

    private func selectDefaultRow() {
        if session.currentChannelID > 0,
           selectNode(matching: .channel(session.currentChannelID)) {
            return
        }

        guard outlineView.numberOfRows > 0 else {
            return
        }

        outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        outlineView.scrollRowToVisible(0)
    }

    private func restoreSelection(_ key: SelectionKey?) -> Bool {
        guard let key else {
            return false
        }

        return selectNode(matching: key)
    }

    private func selectNode(matching key: SelectionKey) -> Bool {
        for row in 0 ..< outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? ServerTreeNode else {
                continue
            }

            if selectionKey(for: item) == key {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                selectedKey = key
                return true
            }
        }

        return false
    }

    private func currentSelectionKey() -> SelectionKey? {
        let row = outlineView.selectedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? ServerTreeNode else {
            return nil
        }

        return selectionKey(for: item)
    }

    private func selectionKey(for node: ServerTreeNode) -> SelectionKey {
        switch node {
        case .channel(let channel):
            return .channel(channel.id)
        case .user(let user):
            return .user(user.id)
        }
    }

    private func rootNode(at index: Int) -> ServerTreeNode {
        .channel(session.rootChannels[index])
    }

    private func childNode(at index: Int, for node: ServerTreeNode) -> ServerTreeNode {
        switch node {
        case .channel(let channel):
            if index < channel.users.count {
                return .user(channel.users[index])
            }
            return .channel(channel.children[index - channel.users.count])
        case .user:
            fatalError("A user node has no children")
        }
    }

    private func numberOfChildren(for node: ServerTreeNode?) -> Int {
        guard let node else {
            return session.rootChannels.count
        }

        switch node {
        case .channel(let channel):
            return channel.children.count + channel.users.count
        case .user:
            return 0
        }
    }

    private func isExpandable(_ node: ServerTreeNode) -> Bool {
        switch node {
        case .channel(let channel):
            return channel.children.isEmpty == false || channel.users.isEmpty == false
        case .user:
            return false
        }
    }

    private func displayText(for node: ServerTreeNode) -> String {
        switch node {
        case .channel(let channel):
            return visualChannelText(for: channel)
        case .user(let user):
            return visualUserText(for: user)
        }
    }

    private func accessibilityText(for node: ServerTreeNode) -> String {
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

    private func visualChannelText(for channel: ConnectedServerChannel) -> String {
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

    private func visualUserText(for user: ConnectedServerUser) -> String {
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

    func selectedUserForInfo() -> ConnectedServerUser? {
        selectedUserNodes().first
    }

    @objc
    private func joinSelectedChannel(_ sender: Any? = nil) {
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
    private func leaveCurrentChannel(_ sender: Any? = nil) {
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

    @objc
    private func openPrivateConversation(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode else {
            return
        }

        appDelegate.openPrivateConversation(userID: user.id, displayName: user.displayName)
    }

    private func performDefaultAction() {
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

    private func presentActionError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text("connectedServer.action.error.title")
        alert.informativeText = message
        alert.runModal()
        announce(message)
    }

    private func joinChannel(_ channel: ConnectedServerChannel, password: String) {
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

    private func promptAndJoinProtectedChannel(
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

    @objc
    private func sendCurrentMessage(_ sender: Any? = nil) {
        let message = messageField.stringValue
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        connectionController.sendChannelMessage(trimmed) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.messageField.stringValue = ""
                self.updateChatInputState()
                self.view.window?.makeFirstResponder(self.messageField)
                self.announce(L10n.text("connectedServer.chat.sent"))
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    @objc
    private func toggleMicrophone(_ sender: Any? = nil) {
        if session.voiceTransmissionEnabled {
            connectionController.deactivateVoiceTransmission { [weak self] result in
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.announce(L10n.text("connectedServer.audio.voiceDisabled"))
                case .failure(let error):
                    self.presentActionError(error.localizedDescription)
                }
            }
            return
        }

        connectionController.requestMicrophoneAccess { [weak self] granted in
            guard let self else {
                return
            }

            guard granted else {
                self.presentActionError(L10n.text("connectedServer.audio.error.microphonePermissionDenied"))
                return
            }

            self.connectionController.activateVoiceTransmission { [weak self] result in
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.announce(L10n.text("connectedServer.audio.voiceEnabled"))
                case .failure(let error):
                    self.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    private var pendingAnnouncements = [String]()
    private var announcementTimer: Timer?

    private func announce(_ message: String) {
        pendingAnnouncements.append(message)
        scheduleAnnouncementFlush()
    }

    private func scheduleAnnouncementFlush() {
        guard announcementTimer == nil else { return }
        announcementTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.flushAnnouncements()
        }
    }

    private func flushAnnouncements() {
        announcementTimer = nil
        guard pendingAnnouncements.isEmpty == false else { return }
        let combined = pendingAnnouncements.joined(separator: ". ")
        pendingAnnouncements.removeAll()

        let accessibilityElement = NSApp.accessibilityWindow() ?? view.window ?? view
        NSAccessibility.post(
            element: accessibilityElement,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: combined,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

extension ConnectedServerViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        numberOfChildren(for: item as? ServerTreeNode)
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? ServerTreeNode {
            return childNode(at: index, for: node)
        }
        return rootNode(at: index)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? ServerTreeNode else {
            return false
        }
        return isExpandable(node)
    }
}

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
                let muteTitle = user.isMuted
                    ? L10n.text("connectedServer.menu.unmuteUser")
                    : L10n.text("connectedServer.menu.muteUser")
                actions.append(NSAccessibilityCustomAction(name: muteTitle) { [weak self] in
                    self?.connectionController.muteUser(userID: user.id, mute: !user.isMuted); return true
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

extension ConnectedServerViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == chatTableView {
            return session.channelChatHistory.count
        }
        if tableView == historyTableView {
            return session.sessionHistory.count
        }
        return 0
    }
}

extension ConnectedServerViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == chatTableView,
           session.channelChatHistory.indices.contains(row) {
            return height(for: session.channelChatHistory[row], width: tableView.bounds.width)
        }

        if tableView == historyTableView,
           session.sessionHistory.indices.contains(row) {
            return height(for: session.sessionHistory[row], width: tableView.bounds.width)
        }

        return tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == chatTableView,
           session.channelChatHistory.indices.contains(row) {
            let identifier = NSUserInterfaceItemIdentifier("ChannelChatCell")
            let view: ChannelChatTableCellView

            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? ChannelChatTableCellView {
                view = existing
            } else {
                view = ChannelChatTableCellView(frame: .zero)
                view.identifier = identifier
            }

            let message = session.channelChatHistory[row]
            view.configure(with: message, formattedTime: timeFormatter.string(from: message.receivedAt))
            return view
        }

        if tableView == historyTableView,
           session.sessionHistory.indices.contains(row) {
            let identifier = NSUserInterfaceItemIdentifier("SessionHistoryCell")
            let view: SessionHistoryTableCellView

            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? SessionHistoryTableCellView {
                view = existing
            } else {
                view = SessionHistoryTableCellView(frame: .zero)
                view.identifier = identifier
            }

            let entry = session.sessionHistory[row]
            view.configure(
                message: historyAccessibilityText(for: entry),
                accessibilityText: historyAccessibilityText(for: entry)
            )
            return view
        }

        return nil
    }
}

extension ConnectedServerViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateChatInputState()
    }
}

extension ConnectedServerViewController: ConnectedServerOutlineViewActionDelegate {
    func connectedServerOutlineViewDidRequestDefaultAction(_ outlineView: ConnectedServerOutlineView) {
        performDefaultAction()
    }

    func connectedServerOutlineView(_ outlineView: ConnectedServerOutlineView, menuForRow row: Int) -> NSMenu? {
        guard let node = outlineView.item(atRow: row) as? ServerTreeNode else {
            return nil
        }
        switch node {
        case .channel, .user:
            return contextMenu
        }
    }
}

extension ConnectedServerViewController: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(joinSelectedChannel(_:)):
            guard let channel = selectedChannel else {
                return false
            }
            return channel.isCurrentChannel == false
        case #selector(leaveCurrentChannel(_:)):
            return session.currentChannelID > 0
        case #selector(openPrivateConversation(_:)):
            if case .user = selectedNode {
                return true
            }
            return false
        default:
            return true
        }
    }
}
