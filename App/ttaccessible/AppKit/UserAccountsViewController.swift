//
//  UserAccountsViewController.swift
//  ttaccessible
//

import AppKit
import UniformTypeIdentifiers

// MARK: - Custom table to capture Enter / Delete

private final class AccountsTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var accessibilityActionsProvider: (() -> [NSAccessibilityCustomAction])?
    var accessibilityMenuHandler: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, numpad Enter
            onEnter?()
        case 51: // Delete
            onDelete?()
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

private final class AccountTableRowView: NSTableRowView {
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

private final class AccountTableCellView: NSTableCellView {
    var accessibilityMenuHandler: (() -> Bool)?

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }
}

private final class AccountTableTextField: NSTextField {
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

final class UserAccountsViewController: NSViewController {

    private var accounts: [UserAccountProperties] = []
    private weak var connectionController: TeamTalkConnectionController?
    private var tableView: AccountsTableView!
    private var refreshButton: NSButton!
    private var addButton: NSButton!
    private var editButton: NSButton!
    private var deleteButton: NSButton!
    private let ttFileService = TTFileService()

    init(connectionController: TeamTalkConnectionController) {
        self.connectionController = connectionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTable()
        setupButtons()
        setupLayout()
        updateButtonStates()
    }

    // MARK: - Setup

    private func setupTable() {
        tableView = AccountsTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.setAccessibilityLabel(L10n.text("accounts.table.accessibilityLabel"))
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onEnter = { [weak self] in self?.editSelected() }
        tableView.onDelete = { [weak self] in self?.confirmDeleteSelected() }
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(for: row)
        }
        tableView.accessibilityActionsProvider = { [weak self] in
            self?.accessibilityActionsForSelectedAccount() ?? []
        }
        tableView.accessibilityMenuHandler = { [weak self, weak tableView] in
            guard let self, let tableView else {
                return false
            }
            return self.showAccessibilityMenuForSelectedAccount(from: tableView)
        }

        let usernameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("username"))
        usernameCol.title = L10n.text("accounts.column.username")
        usernameCol.width = 180
        usernameCol.sortDescriptorPrototype = NSSortDescriptor(key: "username", ascending: true)

        let passwordCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("password"))
        passwordCol.title = L10n.text("accounts.column.password")
        passwordCol.width = 150

        let typeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeCol.title = L10n.text("accounts.column.type")
        typeCol.width = 130

        let noteCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        noteCol.title = L10n.text("accounts.column.note")
        noteCol.minWidth = 100

        let lastLoginCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lastLogin"))
        lastLoginCol.title = L10n.text("accounts.column.lastLogin")
        lastLoginCol.width = 160

        tableView.addTableColumn(usernameCol)
        tableView.addTableColumn(passwordCol)
        tableView.addTableColumn(typeCol)
        tableView.addTableColumn(lastLoginCol)
        tableView.addTableColumn(noteCol)
    }

    private func setupButtons() {
        refreshButton = NSButton(title: L10n.text("accounts.button.refresh"), target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        addButton = NSButton(title: L10n.text("accounts.button.add"), target: self, action: #selector(addAccount))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false

        editButton = NSButton(title: L10n.text("accounts.button.edit"), target: self, action: #selector(editSelected))
        editButton.bezelStyle = .rounded
        editButton.translatesAutoresizingMaskIntoConstraints = false

        deleteButton = NSButton(title: L10n.text("accounts.button.delete"), target: self, action: #selector(confirmDeleteSelected))
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonStack = NSStackView(views: [refreshButton, spacer, addButton, editButton, deleteButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        view.addSubview(scrollView)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            buttonStack.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -8)
        ])
    }

    // MARK: - Public

    func update(accounts: [UserAccountProperties]) {
        self.accounts = accounts.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        tableView.reloadData()
        updateButtonStates()
    }

    // MARK: - Actions

    @objc private func refresh() {
        connectionController?.listUserAccounts()
    }

    @objc private func addAccount() {
        let formVC = UserAccountFormViewController(mode: .create, connectionController: connectionController) { [weak self] in
            self?.refresh()
        }
        presentAsSheet(formVC)
    }

    @objc private func editSelected() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < accounts.count else { return }
        let account = accounts[tableView.selectedRow]
        let formVC = UserAccountFormViewController(mode: .edit(account), connectionController: connectionController) { [weak self] in
            self?.refresh()
            self?.announce(L10n.format("accounts.announced.updated", account.username))
        }
        presentAsSheet(formVC)
    }

    @objc private func confirmDeleteSelected() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < accounts.count else { return }
        let account = accounts[tableView.selectedRow]
        confirmDelete(account)
    }

    @objc private func exportSelectedTTFile() {
        guard let account = selectedAccount else {
            return
        }
        exportTTFile(for: account)
    }

    @objc private func copySelectedTTLink() {
        guard let account = selectedAccount else {
            return
        }
        copyTTLink(for: account)
    }

    private var selectedAccount: UserAccountProperties? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < accounts.count else {
            return nil
        }
        return accounts[tableView.selectedRow]
    }

    private func accessibilityActionsForSelectedAccount() -> [NSAccessibilityCustomAction] {
        guard let account = selectedAccount else {
            return []
        }
        return accessibilityActions(for: account)
    }

    private func accessibilityActions(for account: UserAccountProperties) -> [NSAccessibilityCustomAction] {
        [
            NSAccessibilityCustomAction(name: L10n.text("serverExport.ttFile")) { [weak self] in
                self?.performAccountAction(account) { controller, currentAccount in
                    controller.exportTTFile(for: currentAccount)
                }
                return true
            },
            NSAccessibilityCustomAction(name: L10n.text("serverExport.link")) { [weak self] in
                self?.performAccountAction(account) { controller, currentAccount in
                    controller.copyTTLink(for: currentAccount)
                }
                return true
            },
            NSAccessibilityCustomAction(name: L10n.text("accounts.button.delete")) { [weak self] in
                self?.performAccountAction(account) { controller, currentAccount in
                    controller.confirmDelete(currentAccount)
                }
                return true
            }
        ]
    }

    private func performAccountAction(
        _ account: UserAccountProperties,
        action: (UserAccountsViewController, UserAccountProperties) -> Void
    ) {
        let currentAccount = selectAccount(account) ?? account
        action(self, currentAccount)
    }

    @discardableResult
    private func selectAccount(_ account: UserAccountProperties) -> UserAccountProperties? {
        guard let index = indexOfAccount(matching: account) else {
            return nil
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        return accounts[index]
    }

    private func indexOfAccount(matching account: UserAccountProperties) -> Int? {
        accounts.firstIndex { $0.username == account.username }
            ?? accounts.firstIndex {
                $0.username.localizedCaseInsensitiveCompare(account.username) == .orderedSame
            }
    }

    private func makeContextMenu(for row: Int) -> NSMenu? {
        guard row >= 0, row < accounts.count else {
            return nil
        }

        return makeContextMenu(for: accounts[row])
    }

    private func makeContextMenu(for account: UserAccountProperties) -> NSMenu {
        let menu = NSMenu(title: account.username)
        let exportTTItem = NSMenuItem(
            title: L10n.text("serverExport.ttFile"),
            action: #selector(exportSelectedTTFile),
            keyEquivalent: ""
        )
        exportTTItem.target = self
        menu.addItem(exportTTItem)

        let copyLinkItem = NSMenuItem(
            title: L10n.text("serverExport.link"),
            action: #selector(copySelectedTTLink),
            keyEquivalent: ""
        )
        copyLinkItem.target = self
        menu.addItem(copyLinkItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: L10n.text("accounts.button.delete"),
            action: #selector(confirmDeleteSelected),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    private func showAccessibilityMenuForSelectedAccount(from sourceView: NSView) -> Bool {
        guard let account = selectedAccount else {
            return false
        }
        return showAccessibilityMenu(for: account, from: sourceView)
    }

    private func showAccessibilityMenu(for account: UserAccountProperties, from sourceView: NSView) -> Bool {
        let currentAccount = selectAccount(account) ?? account
        let menu = makeContextMenu(for: currentAccount)
        let point = NSPoint(x: sourceView.bounds.midX, y: sourceView.bounds.midY)
        menu.popUp(positioning: nil, at: point, in: sourceView)
        return true
    }

    private func confirmDelete(_ account: UserAccountProperties) {
        guard let window = view.window else {
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.format("accounts.delete.title", account.username)
        alert.informativeText = L10n.text("accounts.delete.message")
        alert.addButton(withTitle: L10n.text("accounts.delete.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.alertStyle = .warning

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.connectionController?.deleteUserAccount(username: account.username) { [weak self] result in
                if case .success = result {
                    self?.refresh()
                    self?.announce(L10n.format("accounts.announced.deleted", account.username))
                }
            }
        }
    }

    private func serverRecord(for account: UserAccountProperties) -> SavedServerRecord? {
        guard let server = connectionController?.sessionSnapshot?.savedServer else {
            return nil
        }

        return SavedServerRecord(
            id: UUID(),
            name: server.name,
            host: server.host,
            tcpPort: server.tcpPort,
            udpPort: server.udpPort,
            encrypted: server.encrypted,
            nickname: "",
            username: account.username,
            initialChannelPath: account.initChannel.trimmingCharacters(in: .whitespacesAndNewlines),
            initialChannelPassword: ""
        )
    }

    private func exportTTFile(for account: UserAccountProperties) {
        guard let record = serverRecord(for: account) else {
            return
        }

        guard let data = ttFileService.generateFileContents(
            record: record,
            password: account.password,
            defaultJoinChannelPath: record.initialChannelPath.isEmpty ? nil : record.initialChannelPath
        ) else {
            presentError(L10n.text("ttFile.export.error.unreadable"))
            return
        }

        let panel = NSSavePanel()
        panel.title = L10n.text("ttFile.export.panel.title")
        panel.nameFieldStringValue = sanitizedTTFileName(serverName: record.name, username: account.username)
        panel.allowedContentTypes = [UTType(filenameExtension: "tt") ?? .data]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func copyTTLink(for account: UserAccountProperties) {
        guard let record = serverRecord(for: account) else {
            return
        }

        let link = record.generateLink(
            password: account.password,
            channelPath: record.initialChannelPath.isEmpty ? nil : record.initialChannelPath
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        announce(L10n.text("connectedServer.serverLink.copied"))
    }

    private func sanitizedTTFileName(serverName: String, username: String) -> String {
        let components = [serverName, username]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let baseName = components.isEmpty ? "server" : components.joined(separator: "-")
        return baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") + ".tt"
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text("savedServers.alert.error.title")
        alert.informativeText = message
        alert.runModal()
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

    private func updateButtonStates() {
        let hasSelection = tableView.selectedRow >= 0 && tableView.selectedRow < accounts.count
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }
}

// MARK: - NSTableViewDataSource

extension UserAccountsViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        accounts.count
    }
}

// MARK: - NSTableViewDelegate

extension UserAccountsViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = AccountTableRowView()
        rowView.accessibilityActionsProvider = { [weak self, weak rowView] in
            guard let self, let rowView else {
                return []
            }
            let currentRow = self.tableView.row(for: rowView)
            guard currentRow >= 0, currentRow < self.accounts.count else {
                return []
            }
            return self.accessibilityActions(for: self.accounts[currentRow])
        }
        rowView.accessibilityMenuHandler = { [weak self, weak rowView] in
            guard let self, let rowView else {
                return false
            }
            let currentRow = self.tableView.row(for: rowView)
            guard currentRow >= 0, currentRow < self.accounts.count else {
                return false
            }
            return self.showAccessibilityMenu(for: self.accounts[currentRow], from: rowView)
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < accounts.count else { return nil }
        let account = accounts[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellID = NSUserInterfaceItemIdentifier("cell-\(identifier.rawValue)")

        let cell: AccountTableCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? AccountTableCellView {
            cell = existing
        } else {
            cell = AccountTableCellView()
            cell.identifier = cellID
            let textField = AccountTableTextField()
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch identifier.rawValue {
        case "username":
            cell.textField?.stringValue = account.username
        case "password":
            cell.textField?.stringValue = account.password
        case "type":
            cell.textField?.stringValue = typeDisplayName(account.userType)
        case "note":
            cell.textField?.stringValue = account.note
        case "lastLogin":
            cell.textField?.stringValue = account.lastLoginTime
        default:
            break
        }
        let actions = accessibilityActions(for: account)
        cell.setAccessibilityCustomActions(actions)
        cell.textField?.setAccessibilityCustomActions(actions)
        cell.accessibilityMenuHandler = { [weak self, weak cell] in
            guard let self, let cell else {
                return false
            }
            return self.showAccessibilityMenu(for: account, from: cell)
        }
        if let textField = cell.textField as? AccountTableTextField {
            textField.accessibilityMenuHandler = { [weak self, weak textField] in
                guard let self, let textField else {
                    return false
                }
                return self.showAccessibilityMenu(for: account, from: textField)
            }
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }

    private func typeDisplayName(_ type: UserAccountType) -> String {
        switch type {
        case .defaultUser: return L10n.text("accounts.type.default")
        case .admin:       return L10n.text("accounts.type.admin")
        case .disabled:    return L10n.text("accounts.type.disabled")
        }
    }
}
