//
//  UserAccountsViewController.swift
//  ttaccessible
//

import AppKit

// MARK: - Custom table to capture Enter / Delete

private final class AccountsTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?

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

        tableView.addTableColumn(usernameCol)
        tableView.addTableColumn(passwordCol)
        tableView.addTableColumn(typeCol)
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

        let alert = NSAlert()
        alert.messageText = L10n.format("accounts.delete.title", account.username)
        alert.informativeText = L10n.text("accounts.delete.message")
        alert.addButton(withTitle: L10n.text("accounts.delete.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.alertStyle = .warning

        alert.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.connectionController?.deleteUserAccount(username: account.username) { [weak self] result in
                if case .success = result {
                    self?.refresh()
                    self?.announce(L10n.format("accounts.announced.deleted", account.username))
                }
            }
        }
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
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < accounts.count else { return nil }
        let account = accounts[row]

        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cellID = NSUserInterfaceItemIdentifier("cell-\(identifier.rawValue)")

        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let textField = NSTextField(labelWithString: "")
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
        default:
            break
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

