//
//  ConnectedUsersViewController.swift
//  ttaccessible
//
//  Lists every user connected to the server (server-wide, all channels),
//  the equivalent of the Qt client's "Online Users" dialog (Ctrl+Shift+U).
//

import AppKit

// MARK: - Custom table to capture Enter and expose VoiceOver actions

private final class ConnectedUsersTableView: NSTableView {
    var onEnter: (() -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var accessibilityActionsProvider: (() -> [NSAccessibilityCustomAction])?
    var accessibilityMenuHandler: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, numpad Enter
            onEnter?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else {
            return nil
        }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return contextMenuProvider?(row)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let actions = accessibilityActionsProvider?() ?? []
        return actions.isEmpty ? nil : actions
    }

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }
}

private final class ConnectedUsersRowView: NSTableRowView {
    var accessibilityActionsProvider: (() -> [NSAccessibilityCustomAction])?
    var accessibilityMenuHandler: (() -> Bool)?

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let actions = accessibilityActionsProvider?() ?? []
        return actions.isEmpty ? nil : actions
    }

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }
}

private final class ConnectedUsersCellView: NSTableCellView {
    var accessibilityMenuHandler: (() -> Bool)?

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }
}

private final class ConnectedUsersTextField: NSTextField {
    var accessibilityMenuHandler: (() -> Bool)?

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        lineBreakMode = .byTruncatingTail
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }
}

// MARK: - View controller

final class ConnectedUsersViewController: NSViewController {

    private var users: [ConnectedServerUser] = []
    private var lastSignature: [String] = []
    private var hasPopulated = false
    private weak var serverViewController: ConnectedServerViewController?
    private weak var appDelegate: AppDelegate?
    private var tableView: ConnectedUsersTableView!
    private var countLabel: NSTextField!

    private enum Column: String, CaseIterable {
        case nickname, status, username, channel, ip, version, id

        var titleKey: String { "connectedUsers.column.\(rawValue)" }
        var width: CGFloat {
            switch self {
            case .nickname: return 160
            case .status:   return 150
            case .username: return 120
            case .channel:  return 160
            case .ip:       return 120
            case .version:  return 90
            case .id:       return 50
            }
        }
    }

    init(serverViewController: ConnectedServerViewController?, appDelegate: AppDelegate?) {
        self.serverViewController = serverViewController
        self.appDelegate = appDelegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTable()
        setupLayout()
        refreshCountLabel(announce: false)
        observeWindowFocus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Menu-state ownership

    /// While this window is key, it drives the per-user fields of the shared menu
    /// state so the User-menu keyboard shortcuts (Cmd+I, Cmd+Shift+M, …) act on the
    /// selection here. On resign-key the main outline view reclaims ownership.
    private func observeWindowFocus() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidResignKey(_:)), name: NSWindow.didResignKeyNotification, object: nil)
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard (note.object as? NSWindow) === view.window else { return }
        pushMenuState()
    }

    @objc private func windowDidResignKey(_ note: Notification) {
        guard (note.object as? NSWindow) === view.window else { return }
        serverViewController?.updateMenuState()
    }

    /// Mirrors `ConnectedServerViewController.updateMenuState()` for the row selected
    /// here. No-op unless this window is key, so it never clobbers the main outline's
    /// state while in the background.
    func pushMenuState() {
        guard view.window?.isKeyWindow == true else { return }
        let menuState = SavedServersMenuState.shared
        guard let user = selectedUser() else {
            menuState.setSelectedUsersState(
                hasSelectedUsers: false,
                hasSingleSelectedUser: false,
                hasSingleSelectedOtherUser: false,
                isSelectedUserMuted: false,
                isSelectedUserMediaFileMuted: false,
                isSelectedUserChannelOperator: false,
                states: [:]
            )
            return
        }
        let isOther = !user.isCurrentUser
        let muted = serverViewController?.localMuteState[user.id] ?? user.isMuted
        let mediaMuted = serverViewController?.localMediaFileMuteState[user.id] ?? user.isMediaFileMuted
        menuState.setSelectedUsersState(
            hasSelectedUsers: isOther,
            hasSingleSelectedUser: true,
            hasSingleSelectedOtherUser: isOther,
            isSelectedUserMuted: isOther ? muted : false,
            isSelectedUserMediaFileMuted: isOther ? mediaMuted : false,
            isSelectedUserChannelOperator: isOther ? user.isChannelOperator : false,
            states: Dictionary(
                uniqueKeysWithValues: UserSubscriptionOption.allCases.map { option in
                    (option, isOther && user.isSubscriptionEnabled(option))
                }
            )
        )
    }

    // MARK: - Keyboard-shortcut entry points (routed from AppDelegate when key)

    func keyShowInfoSelectedUser() {
        selectedUser().map { appDelegate?.openUserInfo(for: $0) }
    }

    func keyMuteSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performToggleMute(user, presentingWindow: presentingWindow)
    }

    func keyMuteMediaFileSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performToggleMuteMediaFile(user, presentingWindow: presentingWindow)
    }

    func keyAdjustVolumeSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performAdjustVolume(user, presentingWindow: presentingWindow)
    }

    func keyToggleOperatorSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performToggleOperator(user, presentingWindow: presentingWindow)
    }

    func keyKickSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performKick(user, fromServer: false, presentingWindow: presentingWindow)
    }

    func keyKickFromServerSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performKick(user, fromServer: true, presentingWindow: presentingWindow)
    }

    func keyKickBanSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performKickBan(user, presentingWindow: presentingWindow)
    }

    func keyMoveSelectedUser() {
        guard let user = selectedUser() else { return }
        serverViewController?.performMove([user], presentingWindow: presentingWindow)
    }

    func keySetSubscription(_ option: UserSubscriptionOption, enabled: Bool) {
        guard let user = selectedUser(), !user.isCurrentUser else { return }
        serverViewController?.setSubscription(option, enabled: enabled, forUserIDs: [user.id])
    }

    // MARK: - Setup

    private func setupTable() {
        tableView = ConnectedUsersTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.setAccessibilityLabel(L10n.text("connectedUsers.table.accessibilityLabel"))
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onEnter = { [weak self] in self?.openInfoForSelected() }
        tableView.contextMenuProvider = { [weak self] row in self?.makeContextMenu(for: row) }
        tableView.accessibilityActionsProvider = { [weak self] in
            self?.accessibilityActionsForSelectedUser() ?? []
        }
        tableView.accessibilityMenuHandler = { [weak self, weak tableView] in
            guard let self, let tableView else { return false }
            return self.showAccessibilityMenuForSelectedUser(from: tableView)
        }

        for column in Column.allCases {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            col.title = L10n.text(column.titleKey)
            col.width = column.width
            col.minWidth = 40
            tableView.addTableColumn(col)
        }
    }

    private func setupLayout() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        countLabel = NSTextField(labelWithString: "")
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(countLabel)

        NSLayoutConstraint.activate([
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            countLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -8)
        ])
    }

    // MARK: - Public

    func update(users newUsers: [ConnectedServerUser]) {
        let sorted = newUsers.sorted {
            $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
        // Skip the reload when nothing the table displays has changed. This avoids
        // disturbing the VoiceOver cursor on every unrelated session publish.
        let signature = sorted.map(displaySignature)
        guard signature != lastSignature else { return }
        let countChanged = sorted.count != users.count
        lastSignature = signature

        let previousID = selectedUser()?.id
        self.users = sorted
        tableView.reloadData()
        refreshCountLabel(announce: countChanged && hasPopulated)
        hasPopulated = true
        if let previousID, let index = users.firstIndex(where: { $0.id == previousID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    /// Projection of the fields the table renders — used to detect real changes.
    private func displaySignature(_ u: ConnectedServerUser) -> String {
        "\(u.id)|\(u.nickname)|\(u.username)|\(channelPath(for: u))|\(u.statusMessage)|\(u.isChannelOperator)|\(u.isAdministrator)|\(u.clientVersion)|\(u.ipAddress)"
    }

    private func refreshCountLabel(announce shouldAnnounce: Bool) {
        let count = users.count
        let key = count == 1 ? "connectedUsers.count.one" : "connectedUsers.count"
        let text = L10n.format(key, count)
        countLabel.stringValue = text
        if shouldAnnounce {
            announce(text)
        }
    }

    // MARK: - Selection helpers

    func selectedUser() -> ConnectedServerUser? {
        let row = tableView.selectedRow
        guard row >= 0, row < users.count else { return nil }
        return users[row]
    }

    @discardableResult
    private func selectUser(_ user: ConnectedServerUser) -> ConnectedServerUser? {
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return nil }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        return users[index]
    }

    private var presentingWindow: NSWindow? { view.window }

    /// Mirrors the gating in `ConnectedServerViewController.validateMenuItem` /
    /// `+OutlineDelegate`: moderation actions require the right privileges.
    private var currentUserRights: (canModerate: Bool, canKickFromServer: Bool, canBan: Bool) {
        guard let session = serverViewController?.session, let me = session.currentUser else {
            return (false, false, false)
        }
        // Kicking off the server and banning are separate server-side RIGHTS
        // (USERRIGHT_KICK_USERS / USERRIGHT_BAN_USERS), not an admin account —
        // see ServerNode::UserKick and ::UserBan.
        return (me.isAdministrator || me.isChannelOperator, session.canKickUsers, session.canBanUsers)
    }

    // MARK: - Actions

    private func openInfoForSelected() {
        guard let user = selectedUser() else { return }
        appDelegate?.openUserInfo(for: user)
    }

    private func openPrivateMessage(_ user: ConnectedServerUser) {
        guard !user.isCurrentUser else { return }
        appDelegate?.openPrivateConversation(userID: user.id, displayName: user.displayName)
    }

    private func copyUser(_ user: ConnectedServerUser) {
        let lines = Column.allCases.map { "\(L10n.text($0.titleKey)): \(text(for: user, column: $0))" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        announce(L10n.text("connectedUsers.copied"))
    }

    // MARK: - Accessibility custom actions / context menu

    private func accessibilityActionsForSelectedUser() -> [NSAccessibilityCustomAction] {
        guard let user = selectedUser() else { return [] }
        return accessibilityActions(for: user)
    }

    private func accessibilityActions(for user: ConnectedServerUser) -> [NSAccessibilityCustomAction] {
        var actions: [NSAccessibilityCustomAction] = [
            NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.info")) { [weak self] in
                self?.perform(user) { $0.appDelegate?.openUserInfo(for: $1) }
                return true
            },
            NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.copy")) { [weak self] in
                self?.perform(user) { $0.copyUser($1) }
                return true
            }
        ]
        guard !user.isCurrentUser else { return actions }
        let rights = currentUserRights

        actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.message")) { [weak self] in
            self?.perform(user) { $0.openPrivateMessage($1) }
            return true
        })

        // Operator toggle is offered for any other user (matching validateMenuItem's
        // `isOther`-only gate): performToggleOperator falls back to a channel-op
        // password prompt when the local user lacks the operator-enable right.
        let opTitle = user.isChannelOperator
            ? L10n.text("connectedServer.menu.revokeOperator")
            : L10n.text("connectedServer.menu.makeOperator")
        actions.append(NSAccessibilityCustomAction(name: opTitle) { [weak self] in
            self?.perform(user) { ctrl, u in ctrl.serverViewController?.performToggleOperator(u, presentingWindow: ctrl.presentingWindow) }
            return true
        })

        if rights.canModerate {
            actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.move")) { [weak self] in
                self?.perform(user) { ctrl, u in ctrl.presentingWindow.map { ctrl.serverViewController?.performMove([u], presentingWindow: $0) } }
                return true
            })
            actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.kickChannel")) { [weak self] in
                self?.perform(user) { ctrl, u in ctrl.presentingWindow.map { ctrl.serverViewController?.performKick(u, fromServer: false, presentingWindow: $0) } }
                return true
            })
        }
        if rights.canKickFromServer {
            actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.kickServer")) { [weak self] in
                self?.perform(user) { ctrl, u in ctrl.presentingWindow.map { ctrl.serverViewController?.performKick(u, fromServer: true, presentingWindow: $0) } }
                return true
            })
        }
        if rights.canBan {
            actions.append(NSAccessibilityCustomAction(name: L10n.text("connectedUsers.action.kickBan")) { [weak self] in
                self?.perform(user) { ctrl, u in ctrl.presentingWindow.map { ctrl.serverViewController?.performKickBan(u, presentingWindow: $0) } }
                return true
            })
        }
        return actions
    }

    private func perform(_ user: ConnectedServerUser, _ action: (ConnectedUsersViewController, ConnectedServerUser) -> Void) {
        let current = selectUser(user) ?? user
        action(self, current)
    }

    private func makeContextMenu(for row: Int) -> NSMenu? {
        guard row >= 0, row < users.count else { return nil }
        return makeContextMenu(for: users[row])
    }

    private func makeContextMenu(for user: ConnectedServerUser) -> NSMenu {
        let menu = NSMenu(title: user.displayName)

        let infoItem = NSMenuItem(title: L10n.text("connectedUsers.action.info"), action: #selector(menuInfo), keyEquivalent: "")
        infoItem.target = self
        menu.addItem(infoItem)

        let copyItem = NSMenuItem(title: L10n.text("connectedUsers.action.copy"), action: #selector(menuCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        guard !user.isCurrentUser else { return menu }
        let rights = currentUserRights

        menu.addItem(.separator())

        let messageItem = NSMenuItem(title: L10n.text("connectedUsers.action.message"), action: #selector(menuMessage), keyEquivalent: "")
        messageItem.target = self
        menu.addItem(messageItem)

        // Operator toggle is offered for any other user (matching validateMenuItem);
        // performToggleOperator falls back to a channel-op password prompt.
        let opTitle = user.isChannelOperator
            ? L10n.text("connectedServer.menu.revokeOperator")
            : L10n.text("connectedServer.menu.makeOperator")
        let opItem = NSMenuItem(title: opTitle, action: #selector(menuOp), keyEquivalent: "")
        opItem.target = self
        menu.addItem(opItem)

        if rights.canModerate || rights.canKickFromServer || rights.canBan {
            menu.addItem(.separator())
        }
        if rights.canModerate {
            let moveItem = NSMenuItem(title: L10n.text("connectedUsers.action.move"), action: #selector(menuMove), keyEquivalent: "")
            moveItem.target = self
            menu.addItem(moveItem)

            let kickChannelItem = NSMenuItem(title: L10n.text("connectedUsers.action.kickChannel"), action: #selector(menuKickChannel), keyEquivalent: "")
            kickChannelItem.target = self
            menu.addItem(kickChannelItem)
        }
        if rights.canKickFromServer {
            let kickServerItem = NSMenuItem(title: L10n.text("connectedUsers.action.kickServer"), action: #selector(menuKickServer), keyEquivalent: "")
            kickServerItem.target = self
            menu.addItem(kickServerItem)
        }
        if rights.canBan {
            let kickBanItem = NSMenuItem(title: L10n.text("connectedUsers.action.kickBan"), action: #selector(menuKickBan), keyEquivalent: "")
            kickBanItem.target = self
            menu.addItem(kickBanItem)
        }

        return menu
    }

    @objc private func menuInfo() { selectedUser().map { appDelegate?.openUserInfo(for: $0) } }
    @objc private func menuCopy() { selectedUser().map { copyUser($0) } }
    @objc private func menuMessage() { selectedUser().map { openPrivateMessage($0) } }
    @objc private func menuOp() {
        guard let user = selectedUser(), let window = presentingWindow else { return }
        serverViewController?.performToggleOperator(user, presentingWindow: window)
    }
    @objc private func menuMove() {
        guard let user = selectedUser(), let window = presentingWindow else { return }
        serverViewController?.performMove([user], presentingWindow: window)
    }
    @objc private func menuKickChannel() {
        guard let user = selectedUser(), let window = presentingWindow else { return }
        serverViewController?.performKick(user, fromServer: false, presentingWindow: window)
    }
    @objc private func menuKickServer() {
        guard let user = selectedUser(), let window = presentingWindow else { return }
        serverViewController?.performKick(user, fromServer: true, presentingWindow: window)
    }
    @objc private func menuKickBan() {
        guard let user = selectedUser(), let window = presentingWindow else { return }
        serverViewController?.performKickBan(user, presentingWindow: window)
    }

    private func showAccessibilityMenuForSelectedUser(from sourceView: NSView) -> Bool {
        guard let user = selectedUser() else { return false }
        return showAccessibilityMenu(for: user, from: sourceView)
    }

    private func showAccessibilityMenu(for user: ConnectedServerUser, from sourceView: NSView) -> Bool {
        let current = selectUser(user) ?? user
        let menu = makeContextMenu(for: current)
        let point = NSPoint(x: sourceView.bounds.midX, y: sourceView.bounds.midY)
        menu.popUp(positioning: nil, at: point, in: sourceView)
        return true
    }

    // MARK: - Cell content

    private func text(for user: ConnectedServerUser, column: Column) -> String {
        switch column {
        case .nickname: return user.nickname
        case .status:   return user.statusMessage
        case .username: return user.username
        case .channel:  return channelPath(for: user)
        case .ip:       return user.ipAddress
        case .version:  return user.clientVersion
        case .id:       return String(user.id)
        }
    }

    private func channelPath(for user: ConnectedServerUser) -> String {
        // channelPathComponents[0] is the synthetic root whose name is the server
        // display name; drop it so the root reads as "/" and sub-channels as "/Sub".
        guard !user.channelPathComponents.isEmpty else { return "" }
        let components = user.channelPathComponents.dropFirst()
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }

    private func announce(_ message: String) {
        let element = NSApp.accessibilityWindow() ?? view.window ?? (view as Any)
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

// MARK: - NSTableViewDataSource

extension ConnectedUsersViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        users.count
    }
}

// MARK: - NSTableViewDelegate

extension ConnectedUsersViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        pushMenuState()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ConnectedUsersRowView()
        rowView.accessibilityActionsProvider = { [weak self, weak rowView] in
            guard let self, let rowView else { return [] }
            let currentRow = self.tableView.row(for: rowView)
            guard currentRow >= 0, currentRow < self.users.count else { return [] }
            return self.accessibilityActions(for: self.users[currentRow])
        }
        rowView.accessibilityMenuHandler = { [weak self, weak rowView] in
            guard let self, let rowView else { return false }
            let currentRow = self.tableView.row(for: rowView)
            guard currentRow >= 0, currentRow < self.users.count else { return false }
            return self.showAccessibilityMenu(for: self.users[currentRow], from: rowView)
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < users.count else { return nil }
        let user = users[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellID = NSUserInterfaceItemIdentifier("cell-\(identifier.rawValue)")

        let cell: ConnectedUsersCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? ConnectedUsersCellView {
            cell = existing
        } else {
            cell = ConnectedUsersCellView()
            cell.identifier = cellID
            let textField = ConnectedUsersTextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        if let column = Column(rawValue: identifier.rawValue) {
            cell.textField?.stringValue = text(for: user, column: column)
        }

        let actions = accessibilityActions(for: user)
        cell.setAccessibilityCustomActions(actions)
        cell.textField?.setAccessibilityCustomActions(actions)
        cell.accessibilityMenuHandler = { [weak self, weak cell] in
            guard let self, let cell else { return false }
            return self.showAccessibilityMenu(for: user, from: cell)
        }
        if let textField = cell.textField as? ConnectedUsersTextField {
            textField.accessibilityMenuHandler = { [weak self, weak textField] in
                guard let self, let textField else { return false }
                return self.showAccessibilityMenu(for: user, from: textField)
            }
        }
        return cell
    }
}
