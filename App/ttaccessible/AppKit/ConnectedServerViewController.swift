//
//  ConnectedServerViewController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit
import UniformTypeIdentifiers

// MARK: - AudioGainControlView (see AudioGainControlView.swift)

// Row view qui ne remonte pas les custom actions de ses enfants vers VoiceOver.
final class ServerTreeRowView: NSTableRowView {
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? { nil }
}


final class ConnectedServerViewController: NSViewController {
    enum Column {
        static let main = NSUserInterfaceItemIdentifier("main")
        static let chat = NSUserInterfaceItemIdentifier("chat")
    }

    enum SelectionKey: Equatable {
        case channel(Int32)
        case user(Int32)
    }

    let preferencesStore: AppPreferencesStore
    let connectionController: TeamTalkConnectionController
    let menuState: SavedServersMenuState
    unowned let appDelegate: AppDelegate
    let outlineView = ConnectedServerOutlineView(frame: .zero)
    let chatTableView = NSTableView(frame: .zero)
    let historyTableView = NSTableView(frame: .zero)
    let channelsScrollView = NSScrollView(frame: .zero)
    let chatScrollView = NSScrollView(frame: .zero)
    let historyScrollView = NSScrollView(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let audioStatusLabel = NSTextField(labelWithString: "")
    let chatTitleLabel = NSTextField(labelWithString: "")
    let historyTitleLabel = NSTextField(labelWithString: "")
    let messageField = NSTextField(frame: .zero)
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let microphoneButton = NSButton(title: "", target: nil, action: nil)
    lazy var inputGainControl = AudioGainControlView(
        title: L10n.text("connectedServer.audio.inputGain.label"),
        accessibilityLabel: L10n.text("connectedServer.audio.inputGain.accessibilityLabel")
    ) { [weak self] value in
        self?.applyInputGain(value)
    }
    lazy var outputGainControl = AudioGainControlView(
        title: L10n.text("connectedServer.audio.outputGain.label"),
        accessibilityLabel: L10n.text("connectedServer.audio.outputGain.accessibilityLabel")
    ) { [weak self] value in
        self?.applyOutputGain(value)
    }
    lazy var contextMenu: NSMenu = makeContextMenu()

    var session: ConnectedServerSession
    var localMuteState: [Int32: Bool] = [:]
    var selectedKey: SelectionKey?
    var needsInitialFocus = true
    var lastAnnouncedChannelID: Int32 = 0
    var lastAnnouncedChannelMessageID: UUID?
    var lastAnnouncedHistoryEntryID: UUID?
    let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    func formattedTime(for date: Date) -> String {
        if preferencesStore.preferences.useRelativeTimestamps {
            return relativeTimeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return timeFormatter.string(from: date)
    }

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
        configureKeyViewLoop()
        focusOutlineIfNeeded()
        startRelativeTimestampTimerIfNeeded()
    }

    func configureKeyViewLoop() {
        outlineView.nextKeyView = chatTableView
        chatTableView.nextKeyView = messageField
        messageField.nextKeyView = sendButton
        sendButton.nextKeyView = historyTableView
        historyTableView.nextKeyView = outlineView
        view.window?.recalculateKeyViewLoop()
    }

    func update(session: ConnectedServerSession) {
        applySession(session, preserveSelection: true)
        startRelativeTimestampTimerIfNeeded()
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

    func configureUI() {
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

        let chatMenu = NSMenu()
        chatMenu.addItem(NSMenuItem(title: L10n.text("chat.contextMenu.copyMessage"), action: #selector(copySelectedChatMessage), keyEquivalent: "c"))
        chatTableView.menu = chatMenu

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

    func applySession(_ session: ConnectedServerSession, preserveSelection: Bool) {
        let previousSession = self.session
        if preserveSelection == false {
            selectedKey = nil
            localMuteState.removeAll()
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
            expandCurrentChannelPath()

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
            isNicknameLocked: session.isNicknameLocked,
            isStatusLocked: session.isStatusLocked,
            audioStatusText: update.audioStatusText,
            inputGainDB: session.inputGainDB,
            outputGainDB: session.outputGainDB,
            recordingActive: session.recordingActive
        )

        updateAudioControls()
        reloadVisibleUserRows(for: changedUserIDs)
        updateMenuState()
    }

    func updateMenuState() {
        let selectedUsers = selectedUserNodes()
            .filter { $0.isCurrentUser == false }
        let allSelectedUsers = selectedUserNodes()
        menuState.setConnectedState(
            hasSelectedChannel: selectedChannel != nil,
            isInChannel: session.currentChannelID > 0
        )
        let singleOtherUser = selectedUsers.count == 1 ? selectedUsers.first : nil
        let currentMuted: Bool = {
            guard let userID = singleOtherUser?.id else { return false }
            return localMuteState[userID] ?? singleOtherUser?.isMuted ?? false
        }()
        menuState.setSelectedUsersState(
            hasSelectedUsers: selectedUsers.isEmpty == false,
            hasSingleSelectedUser: allSelectedUsers.count == 1,
            hasSingleSelectedOtherUser: singleOtherUser != nil,
            isSelectedUserMuted: currentMuted,
            isSelectedUserChannelOperator: singleOtherUser?.isChannelOperator ?? false,
            states: Dictionary(
                uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
                    (option, selectedUsers.isEmpty == false && selectedUsers.allSatisfy { $0.isSubscriptionEnabled(option) })
                }
            )
        )
        menuState.setRecordingActive(session.recordingActive)
    }

    func updateChatInputState() {
        let isInChannel = session.currentChannelID > 0
        messageField.isEnabled = isInChannel
        sendButton.isEnabled = isInChannel && messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if isInChannel == false {
            messageField.stringValue = ""
        }
    }

    func updateAudioControls() {
        microphoneButton.title = session.voiceTransmissionEnabled
            ? L10n.text("connectedServer.audio.microphone.disable")
            : L10n.text("connectedServer.audio.microphone.enable")
        microphoneButton.isEnabled = session.currentChannelID > 0 || session.voiceTransmissionEnabled
        microphoneButton.setAccessibilityLabel(L10n.text("connectedServer.audio.microphone.accessibilityLabel"))
        microphoneButton.setAccessibilityValue(session.audioStatusText)
        inputGainControl.setValue(session.inputGainDB)
        outputGainControl.setValue(session.outputGainDB)
    }

    func applyIncrementalTableUpdate<T: Equatable>(
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

    func updateAudioState(
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

    func reloadVisibleUserRows(for userIDs: Set<Int32>) {
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

    func applyInputGain(_ value: Double) {
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
            isNicknameLocked: session.isNicknameLocked,
            isStatusLocked: session.isStatusLocked,
            audioStatusText: session.audioStatusText,
            inputGainDB: normalized,
            outputGainDB: session.outputGainDB,
            recordingActive: session.recordingActive
        )
        updateAudioControls()
    }

    func applyOutputGain(_ value: Double) {
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
            isNicknameLocked: session.isNicknameLocked,
            isStatusLocked: session.isStatusLocked,
            audioStatusText: session.audioStatusText,
            inputGainDB: session.inputGainDB,
            outputGainDB: normalized,
            recordingActive: session.recordingActive
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

    // MARK: - Announcements (see ConnectedServerViewController+Announcements.swift)

    func scrollChatToBottomIfNeeded() {
        let rowCount = session.channelChatHistory.count
        guard rowCount > 0 else {
            return
        }

        chatTableView.scrollRowToVisible(rowCount - 1)
    }

    func shouldScrollHistoryToBottomAfterReload() -> Bool {
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

    func scrollHistoryToBottomIfNeeded(shouldScroll: Bool) {
        guard shouldScroll else {
            return
        }

        let rowCount = session.sessionHistory.count
        guard rowCount > 0 else {
            return
        }

        historyTableView.scrollRowToVisible(rowCount - 1)
    }

    // MARK: - Table View Helpers (see ConnectedServerViewController+TableViewDataDelegate.swift)

    var selectedNode: ServerTreeNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else {
            return nil
        }
        return outlineView.item(atRow: row) as? ServerTreeNode
    }

    var selectedChannel: ConnectedServerChannel? {
        guard case .channel(let channel)? = selectedNode else {
            return nil
        }
        return channel
    }

    func makeContextMenu() -> NSMenu {
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

        let opItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.makeOperator"),
            action: #selector(toggleChannelOperatorAction),
            keyEquivalent: ""
        )
        opItem.target = self
        menu.addItem(opItem)

        let kickItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.kickUser"),
            action: #selector(kickUserAction),
            keyEquivalent: ""
        )
        kickItem.target = self
        menu.addItem(kickItem)

        let kickServerItem = NSMenuItem(
            title: L10n.text("connectedServer.menu.kickUserFromServer"),
            action: #selector(kickUserFromServerAction),
            keyEquivalent: ""
        )
        kickServerItem.target = self
        menu.addItem(kickServerItem)

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

    // MARK: - User Actions (see ConnectedServerViewController+UserActions.swift)

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
        case #selector(toggleChannelOperatorAction):
            if let user = selectedUser, isOther {
                menuItem.title = user.isChannelOperator
                    ? L10n.text("connectedServer.menu.revokeOperator")
                    : L10n.text("connectedServer.menu.makeOperator")
            }
            return isOther
        case #selector(kickUserAction):
            return isOther && canModerate
        case #selector(kickUserFromServerAction):
            return isOther && session.isAdministrator
        case #selector(kickBanUserAction):
            return isOther && session.isAdministrator
        case #selector(moveUserAction):
            // Current user can move themselves; otherwise admin/op required
            let selectedUsers = selectedUserNodes()
            guard !selectedUsers.isEmpty else { return false }
            let hasOthers = selectedUsers.contains { !$0.isCurrentUser }
            return !hasOthers || canModerate
        default:
            return true
        }
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

    // MARK: - Channel Actions (see ConnectedServerViewController+ChannelActions.swift)

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

    func expandCurrentChannelPath() {
        // Collapse everything first.
        outlineView.collapseItem(nil, collapseChildren: true)

        // Expand the path from root to the current channel.
        guard session.currentChannelID > 0 else { return }

        let path = channelPathToRoot(for: session.currentChannelID, in: session.rootChannels)
        for channelID in path {
            if let item = findOutlineItem(channelID: channelID) {
                outlineView.expandItem(item)
            }
        }
    }

    /// Returns the chain of channel IDs from root down to (and including) the target channel.
    private func channelPathToRoot(for targetID: Int32, in channels: [ConnectedServerChannel]) -> [Int32] {
        for channel in channels {
            if channel.id == targetID {
                return [channel.id]
            }
            let subPath = channelPathToRoot(for: targetID, in: channel.children)
            if !subPath.isEmpty {
                return [channel.id] + subPath
            }
        }
        return []
    }

    /// Finds the NSOutlineView item (ServerTreeNode) for a given channel ID.
    private func findOutlineItem(channelID: Int32) -> ServerTreeNode? {
        func search(parent: Any?) -> ServerTreeNode? {
            let count = outlineView.numberOfChildren(ofItem: parent)
            for i in 0..<count {
                guard let item = outlineView.child(i, ofItem: parent) as? ServerTreeNode else { continue }
                if case .channel(let ch) = item, ch.id == channelID {
                    return item
                }
                if let found = search(parent: item) {
                    return found
                }
            }
            return nil
        }
        return search(parent: nil)
    }

    func focusOutlineIfNeeded() {
        guard needsInitialFocus, view.window != nil else {
            return
        }

        needsInitialFocus = false
        view.window?.makeFirstResponder(outlineView)
    }

    func selectDefaultRow() {
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

    func restoreSelection(_ key: SelectionKey?) -> Bool {
        guard let key else {
            return false
        }

        return selectNode(matching: key)
    }

    func selectNode(matching key: SelectionKey) -> Bool {
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

    func currentSelectionKey() -> SelectionKey? {
        let row = outlineView.selectedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? ServerTreeNode else {
            return nil
        }

        return selectionKey(for: item)
    }

    func selectionKey(for node: ServerTreeNode) -> SelectionKey {
        switch node {
        case .channel(let channel):
            return .channel(channel.id)
        case .user(let user):
            return .user(user.id)
        }
    }

    // MARK: - Tree Navigation Helpers (see ConnectedServerViewController+OutlineDataSource.swift)

    // MARK: - Display Formatters (see ConnectedServerViewController+OutlineDelegate.swift)

    func selectedUserForInfo() -> ConnectedServerUser? {
        selectedUserNodes().first
    }

    func presentActionError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text("connectedServer.action.error.title")
        alert.informativeText = message
        alert.runModal()
        announce(message)
    }

    @objc
    func sendCurrentMessage(_ sender: Any? = nil) {
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
                if self.messageField.isEnabled {
                    self.view.window?.makeFirstResponder(self.messageField)
                }
                self.announce(L10n.text("connectedServer.chat.sent"))
            case .failure(let error):
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    @objc
    func toggleMicrophone(_ sender: Any? = nil) {
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

    var pendingAnnouncements = [String]()
    var announcementTimer: Timer?
    var relativeTimestampTimer: Timer?

    func startRelativeTimestampTimerIfNeeded() {
        relativeTimestampTimer?.invalidate()
        relativeTimestampTimer = nil
        guard preferencesStore.preferences.useRelativeTimestamps else { return }
        relativeTimestampTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.preferencesStore.preferences.useRelativeTimestamps else {
                self?.relativeTimestampTimer?.invalidate()
                self?.relativeTimestampTimer = nil
                return
            }
            self.chatTableView.reloadData()
            self.historyTableView.reloadData()
        }
    }
}

// MARK: - NSOutlineViewDataSource (see ConnectedServerViewController+OutlineDataSource.swift)
// MARK: - NSOutlineViewDelegate (see ConnectedServerViewController+OutlineDelegate.swift)
// MARK: - NSTableViewDataSource & NSTableViewDelegate (see ConnectedServerViewController+TableViewDataDelegate.swift)

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
