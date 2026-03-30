//
//  PrivateMessagesViewController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit

final class PrivateMessagesViewController: NSViewController {
    private enum ConversationColumn {
        static let main = NSUserInterfaceItemIdentifier("conversation")
    }

    private enum MessageColumn {
        static let main = NSUserInterfaceItemIdentifier("message")
    }

    var preferencesStore: AppPreferencesStore
    private let connectionController: TeamTalkConnectionController
    private let conversationsTableView = NSTableView(frame: .zero)
    private let messagesTableView = NSTableView(frame: .zero)
    private let conversationsScrollView = NSScrollView(frame: .zero)
    private let messagesScrollView = NSScrollView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private let messageField = NSTextField(frame: .zero)
    private let sendButton = NSButton(title: "", target: nil, action: nil)

    private var session: ConnectedServerSession
    private var selectedConversationUserID: Int32?
    private var knownPrivateMessageIDs = Set<UUID>()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(
        session: ConnectedServerSession,
        connectionController: TeamTalkConnectionController,
        preferencesStore: AppPreferencesStore
    ) {
        self.session = session
        self.preferencesStore = preferencesStore
        self.connectionController = connectionController
        self.selectedConversationUserID = session.selectedPrivateConversationUserID ?? session.privateConversations.first?.peerUserID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        configureUI()
        applySession(session, preserveSelection: false, markRead: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureKeyViewLoop()
        focusConversations()
        publishConsultationState()
        markSelectedConversationAsRead()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        connectionController.updatePrivateMessagesConsultation(isWindowVisible: false, selectedUserID: nil)
    }

    func update(session: ConnectedServerSession, markRead: Bool = false) {
        applySession(session, preserveSelection: true, markRead: markRead)
    }

    func selectConversation(userID: Int32?, markRead: Bool, focusInput: Bool = false) {
        selectedConversationUserID = userID ?? session.privateConversations.first?.peerUserID
        reloadConversationsSelection()
        reloadMessages()
        updateInputState()
        publishConsultationState()
        if markRead {
            markSelectedConversationAsRead()
        }
        if focusInput {
            DispatchQueue.main.async { [weak self] in
                self?.focusMessageInput()
            }
        }
    }

    func focusConversations() {
        view.window?.makeFirstResponder(conversationsTableView)
    }

    func focusHistory() {
        view.window?.makeFirstResponder(messagesTableView)
    }

    func focusMessageInput() {
        guard messageField.isEnabled else {
            return
        }
        view.window?.makeFirstResponder(messageField)
    }

    private func configureUI() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view = backgroundView

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.stringValue = L10n.text("privateMessages.window.title")

        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.stringValue = L10n.text("privateMessages.subtitle")

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.alignment = .center
        emptyLabel.stringValue = L10n.text("privateMessages.empty")

        let conversationsColumn = NSTableColumn(identifier: ConversationColumn.main)
        conversationsColumn.title = L10n.text("privateMessages.conversations.column")
        conversationsTableView.addTableColumn(conversationsColumn)
        conversationsTableView.headerView = nil
        if #available(macOS 11.0, *) {
            conversationsTableView.style = .sourceList
        }
        conversationsTableView.rowSizeStyle = .large
        conversationsTableView.delegate = self
        conversationsTableView.dataSource = self
        conversationsTableView.target = self
        conversationsTableView.action = #selector(conversationSelectionChanged)
        conversationsTableView.setAccessibilityLabel(L10n.text("privateMessages.conversations.accessibilityLabel"))

        conversationsScrollView.documentView = conversationsTableView
        conversationsScrollView.hasVerticalScroller = true
        conversationsScrollView.drawsBackground = false
        conversationsScrollView.borderType = .noBorder

        let messagesColumn = NSTableColumn(identifier: MessageColumn.main)
        messagesColumn.title = L10n.text("privateMessages.messages.column")
        messagesTableView.addTableColumn(messagesColumn)
        messagesTableView.headerView = nil
        if #available(macOS 11.0, *) {
            messagesTableView.style = .inset
        }
        messagesTableView.rowSizeStyle = .large
        messagesTableView.allowsEmptySelection = true
        messagesTableView.delegate = self
        messagesTableView.dataSource = self
        messagesTableView.setAccessibilityLabel(L10n.text("privateMessages.messages.accessibilityLabel"))

        messagesScrollView.documentView = messagesTableView
        messagesScrollView.hasVerticalScroller = true
        messagesScrollView.drawsBackground = false
        messagesScrollView.borderType = .noBorder

        messageField.placeholderString = L10n.text("privateMessages.input.placeholder")
        messageField.delegate = self
        messageField.target = self
        messageField.action = #selector(sendCurrentMessage)
        messageField.setAccessibilityLabel(L10n.text("privateMessages.input.accessibilityLabel"))

        sendButton.title = L10n.text("privateMessages.send")
        sendButton.target = self
        sendButton.action = #selector(sendCurrentMessage)
        sendButton.setAccessibilityLabel(L10n.text("privateMessages.send.accessibilityLabel"))

        let inputStack = NSStackView(views: [messageField, sendButton])
        inputStack.orientation = .horizontal
        inputStack.alignment = .centerY
        inputStack.spacing = 12
        inputStack.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView(views: [titleLabel, subtitleLabel, conversationsScrollView])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 12
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [emptyLabel, messagesScrollView, inputStack])
        rightStack.orientation = .vertical
        rightStack.alignment = .leading
        rightStack.spacing = 12
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        let sidebarContainer = NSVisualEffectView()
        sidebarContainer.material = .sidebar
        sidebarContainer.blendingMode = .withinWindow
        sidebarContainer.state = .active
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false

        let contentContainer = NSVisualEffectView()
        contentContainer.material = .contentBackground
        contentContainer.blendingMode = .withinWindow
        contentContainer.state = .active
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        sidebarContainer.addSubview(leftStack)
        contentContainer.addSubview(rightStack)

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebarContainer)
        splitView.addArrangedSubview(contentContainer)

        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sidebarContainer.widthAnchor.constraint(equalToConstant: 300),
            leftStack.topAnchor.constraint(equalTo: sidebarContainer.topAnchor, constant: 20),
            leftStack.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 18),
            leftStack.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -18),
            leftStack.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor, constant: -18),

            rightStack.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 20),
            rightStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            rightStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            rightStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -20),

            conversationsScrollView.widthAnchor.constraint(equalTo: leftStack.widthAnchor),
            conversationsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            messagesScrollView.widthAnchor.constraint(equalTo: rightStack.widthAnchor),
            messagesScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            inputStack.widthAnchor.constraint(equalTo: rightStack.widthAnchor),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])

        titleLabel.setAccessibilityElement(false)
        subtitleLabel.setAccessibilityElement(false)
        emptyLabel.setAccessibilityElement(false)
        leftStack.setAccessibilityElement(false)
        rightStack.setAccessibilityElement(false)
        sidebarContainer.setAccessibilityElement(false)
        contentContainer.setAccessibilityElement(false)
        splitView.setAccessibilityElement(false)
        conversationsScrollView.setAccessibilityElement(false)
        messagesScrollView.setAccessibilityElement(false)
        view.setAccessibilityChildrenInNavigationOrder([
            conversationsTableView,
            messagesTableView,
            messageField,
            sendButton
        ])

        conversationsTableView.nextKeyView = messagesTableView
        messagesTableView.nextKeyView = messageField
        messageField.nextKeyView = sendButton
        sendButton.nextKeyView = conversationsTableView
    }

    private func configureKeyViewLoop() {
        guard let window = view.window else {
            return
        }
        window.initialFirstResponder = conversationsTableView
        window.recalculateKeyViewLoop()
    }

    private func applySession(_ session: ConnectedServerSession, preserveSelection: Bool, markRead: Bool) {
        let previousSession = self.session
        let previousMessageIDs = knownPrivateMessageIDs
        self.session = session
        let incomingMessages = session.privateConversations
            .flatMap(\.messages)
            .filter { $0.isOwnMessage == false && previousMessageIDs.contains($0.id) == false }
        knownPrivateMessageIDs = Set(session.privateConversations.flatMap(\.messages).map(\.id))

        if preserveSelection == false {
            selectedConversationUserID = session.selectedPrivateConversationUserID ?? session.privateConversations.first?.peerUserID
        } else if session.privateConversations.contains(where: { $0.peerUserID == selectedConversationUserID }) == false {
            selectedConversationUserID = session.selectedPrivateConversationUserID ?? session.privateConversations.first?.peerUserID
        }
        reloadConversationsSelection(previousConversations: previousSession.privateConversations)
        reloadMessages(previousMessages: previousMessages(in: previousSession))
        updateInputState()
        publishConsultationState()
        if markRead {
            markSelectedConversationAsRead()
        }
        if let latestIncomingMessage = incomingMessages.last,
           preferencesStore.preferences.voiceOverAnnouncements.privateMessagesEnabled,
           view.window?.isVisible == true,
           NSApp.isActive {
            let isCurrentConversationOpen = latestIncomingMessage.peerUserID == selectedConversationUserID
            let announcementKey = isCurrentConversationOpen
                ? "privateMessages.accessibility.messageSpoken"
                : "privateMessages.accessibility.newMessage"
            announce(
                L10n.format(
                    announcementKey,
                    latestIncomingMessage.senderDisplayName,
                    latestIncomingMessage.message
                )
            )
        }
    }

    private func reloadConversationsSelection(previousConversations: [PrivateConversation]? = nil) {
        if let previousConversations {
            applyIncrementalConversationUpdate(oldConversations: previousConversations, newConversations: session.privateConversations)
        } else {
            conversationsTableView.reloadData()
        }
        guard let selectedConversationUserID,
              let row = session.privateConversations.firstIndex(where: { $0.peerUserID == selectedConversationUserID }) else {
            conversationsTableView.deselectAll(nil)
            return
        }

        conversationsTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        conversationsTableView.scrollRowToVisible(row)
    }

    private func reloadMessages(previousMessages: [PrivateChatMessage]? = nil) {
        if let previousMessages {
            applyIncrementalMessageUpdate(oldMessages: previousMessages, newMessages: selectedConversation?.messages ?? [])
        } else {
            messagesTableView.reloadData()
        }
        let rowCount = selectedConversation?.messages.count ?? 0
        if rowCount > 0 {
            messagesTableView.scrollRowToVisible(rowCount - 1)
        }
        emptyLabel.isHidden = selectedConversation != nil
        messagesScrollView.isHidden = selectedConversation == nil
    }

    private func updateInputState() {
        let enabled = selectedConversation != nil
        messageField.isEnabled = enabled
        sendButton.isEnabled = enabled && messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if enabled == false {
            messageField.stringValue = ""
        }
    }

    private var selectedConversation: PrivateConversation? {
        guard let selectedConversationUserID else {
            return nil
        }
        return session.privateConversations.first(where: { $0.peerUserID == selectedConversationUserID })
    }

    private func markSelectedConversationAsRead() {
        guard view.window?.isVisible == true else {
            return
        }
        guard let selectedConversationUserID else {
            return
        }
        connectionController.markPrivateConversationAsRead(selectedConversationUserID)
    }

    private func previousMessages(in session: ConnectedServerSession) -> [PrivateChatMessage] {
        guard let selectedConversationUserID else {
            return []
        }
        return session.privateConversations.first(where: { $0.peerUserID == selectedConversationUserID })?.messages ?? []
    }

    private func applyIncrementalConversationUpdate(oldConversations: [PrivateConversation], newConversations: [PrivateConversation]) {
        let oldIDs = oldConversations.map(\.peerUserID)
        let newIDs = newConversations.map(\.peerUserID)
        guard oldIDs == newIDs else {
            conversationsTableView.reloadData()
            return
        }

        let changedRows = IndexSet(
            newConversations.indices.compactMap { index in
                oldConversations[index] == newConversations[index] ? nil : index
            }
        )

        if changedRows.isEmpty {
            return
        }

        conversationsTableView.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0))
    }

    private func applyIncrementalMessageUpdate(oldMessages: [PrivateChatMessage], newMessages: [PrivateChatMessage]) {
        if newMessages.count >= oldMessages.count,
           Array(newMessages.prefix(oldMessages.count)) == oldMessages {
            let inserted = IndexSet(integersIn: oldMessages.count ..< newMessages.count)
            if inserted.isEmpty == false {
                messagesTableView.beginUpdates()
                messagesTableView.insertRows(at: inserted, withAnimation: [])
                messagesTableView.endUpdates()
                return
            }
        }

        messagesTableView.reloadData()
    }

    private func announce(_ message: String) {
        let accessibilityElement = NSApp.accessibilityWindow() ?? view.window ?? view
        NSAccessibility.post(
            element: accessibilityElement,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func publishConsultationState() {
        let isVisible = view.window?.isVisible == true
        connectionController.updatePrivateMessagesConsultation(
            isWindowVisible: isVisible,
            selectedUserID: isVisible ? selectedConversationUserID : nil
        )
    }

    @objc
    private func conversationSelectionChanged() {
        let row = conversationsTableView.selectedRow
        guard row >= 0, session.privateConversations.indices.contains(row) else {
            return
        }
        selectedConversationUserID = session.privateConversations[row].peerUserID
        reloadMessages()
        updateInputState()
        publishConsultationState()
        markSelectedConversationAsRead()
    }

    @objc
    private func sendCurrentMessage() {
        guard let conversation = selectedConversation else {
            return
        }

        let trimmed = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        connectionController.sendPrivateMessage(toUserID: conversation.peerUserID, text: trimmed) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.messageField.stringValue = ""
                self.updateInputState()
                self.view.window?.makeFirstResponder(self.messageField)
            case .failure(let error):
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = L10n.text("privateMessages.error.title")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

extension PrivateMessagesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == conversationsTableView {
            return session.privateConversations.count
        }
        if tableView == messagesTableView {
            return selectedConversation?.messages.count ?? 0
        }
        return 0
    }
}

extension PrivateMessagesViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView == messagesTableView,
           let message = selectedConversation?.messages[row] {
            let senderName = message.isOwnMessage ? L10n.text("chat.sender.you") : message.senderDisplayName
            let senderHeight = NSAttributedString(
                string: "\(senderName), \(timeFormatter.string(from: message.receivedAt))",
                attributes: [.font: NSFont.preferredFont(forTextStyle: .subheadline)]
            ).boundingRect(
                with: NSSize(width: max(tableView.bounds.width - 20, 100), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            let messageHeight = NSAttributedString(
                string: message.message,
                attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
            ).boundingRect(
                with: NSSize(width: max(tableView.bounds.width - 20, 100), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            return ceil(senderHeight + messageHeight + 24)
        }
        return tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == conversationsTableView {
            guard session.privateConversations.indices.contains(row) else {
                return nil
            }
            let conversation = session.privateConversations[row]
            let identifier = NSUserInterfaceItemIdentifier("PrivateConversationCell")
            let textField: NSTextField
            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                textField = existing
            } else {
                textField = NSTextField(labelWithString: "")
                textField.identifier = identifier
                textField.lineBreakMode = .byTruncatingTail
                textField.maximumNumberOfLines = 2
            }

            let onlineText = conversation.isPeerCurrentlyOnline
                ? L10n.text("privateMessages.conversation.online")
                : L10n.text("privateMessages.conversation.offline")
            let unreadLabel = L10n.text("privateMessages.conversation.unread")
            let preview = conversation.lastMessagePreview.isEmpty ? onlineText : conversation.lastMessagePreview
            let secondaryLine = conversation.hasUnreadMessages
                ? "\(onlineText) • \(unreadLabel) • \(preview)"
                : "\(onlineText) • \(preview)"
            textField.stringValue = "\(conversation.peerDisplayName)\n\(secondaryLine)"
            textField.setAccessibilityLabel(
                conversation.hasUnreadMessages
                    ? "\(conversation.peerDisplayName), \(onlineText), \(unreadLabel), \(preview)"
                    : "\(conversation.peerDisplayName), \(onlineText), \(preview)"
            )
            return textField
        }

        if tableView == messagesTableView,
           let message = selectedConversation?.messages[row] {
            let identifier = NSUserInterfaceItemIdentifier("PrivateMessageCell")
            let view: ChannelChatTableCellView
            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? ChannelChatTableCellView {
                view = existing
            } else {
                view = ChannelChatTableCellView(frame: .zero)
                view.identifier = identifier
            }
            view.configure(with: message, formattedTime: timeFormatter.string(from: message.receivedAt))
            return view
        }

        return nil
    }
}

extension PrivateMessagesViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateInputState()
    }
}
