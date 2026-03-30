//
//  BannedUsersViewController.swift
//  ttaccessible
//

import AppKit

// MARK: - Custom table (Enter / Delete)

private final class BansTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 { // Delete
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - View controller

final class BannedUsersViewController: NSViewController {

    private var bans: [BannedUserProperties] = []
    private weak var connectionController: TeamTalkConnectionController?

    private var tableView: BansTableView!
    private var refreshButton: NSButton!
    private var unbanButton: NSButton!
    private var addButton: NSButton!

    init(connectionController: TeamTalkConnectionController) {
        self.connectionController = connectionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 460))
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
        tableView = BansTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.setAccessibilityLabel(L10n.text("bans.table.accessibilityLabel"))
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onDelete = { [weak self] in self?.confirmUnban() }

        let columns: [(String, String, CGFloat)] = [
            ("nickname", L10n.text("bans.column.nickname"),  120),
            ("username", L10n.text("bans.column.username"),  120),
            ("type",     L10n.text("bans.column.type"),       90),
            ("date",     L10n.text("bans.column.date"),       130),
            ("owner",    L10n.text("bans.column.owner"),       90),
            ("channel",  L10n.text("bans.column.channel"),    100),
            ("ip",       L10n.text("bans.column.ip"),         100),
        ]

        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            tableView.addTableColumn(col)
        }
    }

    private func setupButtons() {
        refreshButton = NSButton(title: L10n.text("bans.button.refresh"), target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        unbanButton = NSButton(title: L10n.text("bans.button.unban"), target: self, action: #selector(confirmUnban))
        unbanButton.bezelStyle = .rounded
        unbanButton.translatesAutoresizingMaskIntoConstraints = false

        addButton = NSButton(title: L10n.text("bans.button.add"), target: self, action: #selector(addBan))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonStack = NSStackView(views: [refreshButton, spacer, addButton, unbanButton])
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

    func update(bans: [BannedUserProperties]) {
        self.bans = bans.sorted { $0.banTime > $1.banTime }
        tableView.reloadData()
        updateButtonStates()
    }

    // MARK: - Actions

    @objc private func refresh() {
        connectionController?.listBans()
    }

    @objc private func confirmUnban() {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }
        let selectedBans = selectedRows.compactMap { $0 < bans.count ? bans[$0] : nil }
        guard !selectedBans.isEmpty else { return }

        let name = selectedBans.count == 1
            ? selectedBans[0].displayName
            : "\(selectedBans.count) utilisateurs"

        let alert = NSAlert()
        alert.messageText = L10n.format("bans.unban.title", name)
        alert.informativeText = L10n.text("bans.unban.message")
        alert.addButton(withTitle: L10n.text("bans.unban.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.alertStyle = .warning

        alert.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let group = DispatchGroup()
            for ban in selectedBans {
                group.enter()
                self.connectionController?.removeBan(ban) { _ in group.leave() }
            }
            group.notify(queue: .main) { [weak self] in
                self?.refresh()
                self?.announce(L10n.format("bans.announced.unbanned", name))
            }
        }
    }

    @objc private func addBan() {
        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.text("bans.add.title")
        alert.addButton(withTitle: L10n.text("common.save"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 66))

        let typeLabel = NSTextField(labelWithString: L10n.text("bans.add.type") + " :")
        typeLabel.frame = NSRect(x: 0, y: 42, width: 140, height: 20)
        container.addSubview(typeLabel)

        let typePopUp = NSPopUpButton(frame: NSRect(x: 145, y: 38, width: 170, height: 26))
        typePopUp.addItem(withTitle: L10n.text("bans.add.type.ip"))
        typePopUp.addItem(withTitle: L10n.text("bans.add.type.username"))
        container.addSubview(typePopUp)

        let valueLabel = NSTextField(labelWithString: L10n.text("bans.add.value") + " :")
        valueLabel.frame = NSRect(x: 0, y: 8, width: 140, height: 20)
        container.addSubview(valueLabel)

        let valueField = NSTextField(frame: NSRect(x: 145, y: 6, width: 170, height: 22))
        valueField.placeholderString = L10n.text("bans.add.value.placeholder")
        container.addSubview(valueField)

        alert.accessoryView = container
        alert.window.initialFirstResponder = valueField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let value = valueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }

            var ban = BannedUserProperties(ipAddress: "", channelPath: "", banTime: "",
                                           nickname: "", username: "", banTypes: 0, owner: "")
            if typePopUp.indexOfSelectedItem == 0 {
                ban.ipAddress = value
                ban.banTypes = UInt32(BANTYPE_IPADDR.rawValue)
            } else {
                ban.username = value
                ban.banTypes = UInt32(BANTYPE_USERNAME.rawValue)
            }

            self.connectionController?.addBan(ban) { [weak self] _ in
                self?.refresh()
                self?.announce(L10n.format("bans.announced.banned", value))
            }
        }
    }

    private func updateButtonStates() {
        let hasSelection = !tableView.selectedRowIndexes.isEmpty
        unbanButton.isEnabled = hasSelection
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

extension BannedUsersViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { bans.count }
}

// MARK: - NSTableViewDelegate

extension BannedUsersViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < bans.count else { return nil }
        let ban = bans[row]
        let id = tableColumn?.identifier.rawValue ?? ""
        let cellID = NSUserInterfaceItemIdentifier("ban-\(id)")

        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch id {
        case "nickname": cell.textField?.stringValue = ban.nickname
        case "username": cell.textField?.stringValue = ban.username
        case "type":     cell.textField?.stringValue = ban.displayBanType
        case "date":     cell.textField?.stringValue = ban.banTime
        case "owner":    cell.textField?.stringValue = ban.owner
        case "channel":  cell.textField?.stringValue = ban.channelPath
        case "ip":       cell.textField?.stringValue = ban.ipAddress
        default: break
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}
