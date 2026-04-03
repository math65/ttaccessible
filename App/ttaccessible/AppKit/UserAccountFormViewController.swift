//
//  UserAccountFormViewController.swift
//  ttaccessible
//

import AppKit

// MARK: - Mode

enum UserAccountFormMode {
    case create
    case edit(UserAccountProperties)
}

// MARK: - Rights table row

private struct UserRightRow {
    let bit: UInt32
    let label: String
}

private let allUserRights: [UserRightRow] = [
    UserRightRow(bit: UInt32(USERRIGHT_MULTI_LOGIN.rawValue),              label: L10n.text("accounts.rights.multiLogin")),
    UserRightRow(bit: UInt32(USERRIGHT_VIEW_ALL_USERS.rawValue),           label: L10n.text("accounts.rights.viewAllUsers")),
    UserRightRow(bit: UInt32(USERRIGHT_CREATE_TEMPORARY_CHANNEL.rawValue), label: L10n.text("accounts.rights.createTemporaryChannel")),
    UserRightRow(bit: UInt32(USERRIGHT_MODIFY_CHANNELS.rawValue),          label: L10n.text("accounts.rights.modifyChannels")),
    UserRightRow(bit: UInt32(USERRIGHT_TEXTMESSAGE_BROADCAST.rawValue),    label: L10n.text("accounts.rights.broadcastMessage")),
    UserRightRow(bit: UInt32(USERRIGHT_KICK_USERS.rawValue),               label: L10n.text("accounts.rights.kickUsers")),
    UserRightRow(bit: UInt32(USERRIGHT_BAN_USERS.rawValue),                label: L10n.text("accounts.rights.banUsers")),
    UserRightRow(bit: UInt32(USERRIGHT_MOVE_USERS.rawValue),               label: L10n.text("accounts.rights.moveUsers")),
    UserRightRow(bit: UInt32(USERRIGHT_OPERATOR_ENABLE.rawValue),          label: L10n.text("accounts.rights.operatorEnable")),
    UserRightRow(bit: UInt32(USERRIGHT_UPLOAD_FILES.rawValue),             label: L10n.text("accounts.rights.uploadFiles")),
    UserRightRow(bit: UInt32(USERRIGHT_DOWNLOAD_FILES.rawValue),           label: L10n.text("accounts.rights.downloadFiles")),
    UserRightRow(bit: UInt32(USERRIGHT_UPDATE_SERVERPROPERTIES.rawValue),  label: L10n.text("accounts.rights.updateServerProperties")),
    UserRightRow(bit: UInt32(USERRIGHT_TRANSMIT_VOICE.rawValue),           label: L10n.text("accounts.rights.transmitVoice")),
    UserRightRow(bit: UInt32(USERRIGHT_TRANSMIT_VIDEOCAPTURE.rawValue),    label: L10n.text("accounts.rights.transmitVideoCapture")),
    UserRightRow(bit: UInt32(USERRIGHT_TRANSMIT_DESKTOP.rawValue),         label: L10n.text("accounts.rights.transmitDesktop")),
    UserRightRow(bit: UInt32(USERRIGHT_TRANSMIT_DESKTOPINPUT.rawValue),    label: L10n.text("accounts.rights.transmitDesktopInput")),
    UserRightRow(bit: UInt32(USERRIGHT_TRANSMIT_MEDIAFILE_AUDIO.rawValue), label: L10n.text("accounts.rights.transmitMediaFileAudio")),
    UserRightRow(bit: UInt32(USERRIGHT_TRANSMIT_MEDIAFILE_VIDEO.rawValue), label: L10n.text("accounts.rights.transmitMediaFileVideo")),
    UserRightRow(bit: UInt32(USERRIGHT_LOCKED_NICKNAME.rawValue),          label: L10n.text("accounts.rights.lockedNickname")),
    UserRightRow(bit: UInt32(USERRIGHT_LOCKED_STATUS.rawValue),            label: L10n.text("accounts.rights.lockedStatus")),
    UserRightRow(bit: UInt32(USERRIGHT_RECORD_VOICE.rawValue),             label: L10n.text("accounts.rights.recordVoice")),
    UserRightRow(bit: UInt32(USERRIGHT_VIEW_HIDDEN_CHANNELS.rawValue),     label: L10n.text("accounts.rights.viewHiddenChannels")),
    UserRightRow(bit: UInt32(USERRIGHT_TEXTMESSAGE_USER.rawValue),         label: L10n.text("accounts.rights.textMessageUser")),
    UserRightRow(bit: UInt32(USERRIGHT_TEXTMESSAGE_CHANNEL.rawValue),      label: L10n.text("accounts.rights.textMessageChannel")),
]

// MARK: - Form view controller

final class UserAccountFormViewController: NSViewController {

    private let mode: UserAccountFormMode
    private weak var connectionController: TeamTalkConnectionController?
    private let onSave: () -> Void

    // Essential fields
    private var usernameField: NSTextField!
    private var passwordField: NSTextField!
    private var typePopUp: NSPopUpButton!
    private var initChannelField: NSTextField!
    private var noteField: NSTextField!

    // Rights table
    private var rightsTableView: NSTableView!
    private var userRights: UInt32 = UserAccountProperties.defaultUserRights

    // Advanced fields
    private var audioBpsField: NSTextField!
    private var commandsLimitField: NSTextField!
    private var commandsIntervalField: NSTextField!

    init(mode: UserAccountFormMode, connectionController: TeamTalkConnectionController?, onSave: @escaping () -> Void) {
        self.mode = mode
        self.connectionController = connectionController
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 440))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFields()
        setupTabView()
        setupButtons()
        populate()
    }

    // MARK: - Setup

    private func setupFields() {
        usernameField = NSTextField()
        usernameField.placeholderString = L10n.text("accounts.form.username")
        usernameField.setAccessibilityLabel(L10n.text("accounts.form.username"))

        passwordField = NSTextField()
        passwordField.placeholderString = L10n.text("accounts.form.password")
        passwordField.setAccessibilityLabel(L10n.text("accounts.form.password"))

        typePopUp = NSPopUpButton()
        typePopUp.addItem(withTitle: L10n.text("accounts.type.default"))
        typePopUp.addItem(withTitle: L10n.text("accounts.type.admin"))
        typePopUp.addItem(withTitle: L10n.text("accounts.type.disabled"))
        typePopUp.setAccessibilityLabel(L10n.text("accounts.form.type"))

        initChannelField = NSTextField()
        initChannelField.placeholderString = L10n.text("accounts.form.initChannel")
        initChannelField.setAccessibilityLabel(L10n.text("accounts.form.initChannel"))

        noteField = NSTextField()
        noteField.placeholderString = L10n.text("accounts.form.note")
        noteField.setAccessibilityLabel(L10n.text("accounts.form.note"))

        audioBpsField = NSTextField()
        audioBpsField.placeholderString = "0"
        audioBpsField.setAccessibilityLabel(L10n.text("accounts.form.audioBpsLimit"))

        commandsLimitField = NSTextField()
        commandsLimitField.placeholderString = "0"
        commandsLimitField.setAccessibilityLabel(L10n.text("accounts.form.commandsLimit"))

        commandsIntervalField = NSTextField()
        commandsIntervalField.placeholderString = "0"
        commandsIntervalField.setAccessibilityLabel(L10n.text("accounts.form.commandsInterval"))

        rightsTableView = NSTableView()
        rightsTableView.headerView = nil
        let checkCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkCol.width = 24
        let labelCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelCol.minWidth = 200
        rightsTableView.addTableColumn(checkCol)
        rightsTableView.addTableColumn(labelCol)
        rightsTableView.delegate = self
        rightsTableView.dataSource = self
        rightsTableView.allowsMultipleSelection = false
    }

    private func setupTabView() {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // Tab 1 — Essential
        let essentialItem = NSTabViewItem()
        essentialItem.label = L10n.text("accounts.form.tab.essential")
        essentialItem.view = makeEssentialTabView()
        tabView.addTabViewItem(essentialItem)

        // Tab 2 — Rights
        let rightsItem = NSTabViewItem()
        rightsItem.label = L10n.text("accounts.form.tab.rights")
        rightsItem.view = makeRightsTabView()
        tabView.addTabViewItem(rightsItem)

        // Tab 3 — Advanced
        let advancedItem = NSTabViewItem()
        advancedItem.label = L10n.text("accounts.form.tab.advanced")
        advancedItem.view = makeAdvancedTabView()
        tabView.addTabViewItem(advancedItem)

        view.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -52)
        ])
    }

    private func makeEssentialTabView() -> NSView {
        let container = NSView()

        for field in [usernameField, passwordField, initChannelField, noteField] as [NSView] {
            field.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(field)
        }
        typePopUp.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(typePopUp)

        let usernameLabel = label(L10n.text("accounts.form.username"))
        let passwordLabel = label(L10n.text("accounts.form.password"))
        let typeLabel = label(L10n.text("accounts.form.type"))
        let initLabel = label(L10n.text("accounts.form.initChannel"))
        let noteLabel = label(L10n.text("accounts.form.note"))

        let stackItems: [(NSView, NSView)] = [
            (usernameLabel, usernameField),
            (passwordLabel, passwordField),
            (typeLabel, typePopUp),
            (initLabel, initChannelField),
            (noteLabel, noteField)
        ]

        var previousBottom = container.topAnchor
        for (lbl, field) in stackItems {
            lbl.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(lbl)
            NSLayoutConstraint.activate([
                lbl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                lbl.topAnchor.constraint(equalTo: previousBottom, constant: 12),
                lbl.widthAnchor.constraint(equalToConstant: 160),
                field.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                field.centerYAnchor.constraint(equalTo: lbl.centerYAnchor)
            ])
            previousBottom = lbl.bottomAnchor
        }

        return container
    }

    private func makeRightsTabView() -> NSView {
        let container = NSView()

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = rightsTableView
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)

        let enableAllBtn = NSButton(title: L10n.text("accounts.form.rights.enableAll"), target: self, action: #selector(enableAllRights))
        enableAllBtn.bezelStyle = .rounded
        let disableAllBtn = NSButton(title: L10n.text("accounts.form.rights.disableAll"), target: self, action: #selector(disableAllRights))
        disableAllBtn.bezelStyle = .rounded
        let defaultBtn = NSButton(title: L10n.text("accounts.form.rights.defaultRights"), target: self, action: #selector(defaultRights))
        defaultBtn.bezelStyle = .rounded

        let btnStack = NSStackView(views: [enableAllBtn, disableAllBtn, defaultBtn])
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        container.addSubview(btnStack)

        NSLayoutConstraint.activate([
            btnStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            btnStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.topAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    private func makeAdvancedTabView() -> NSView {
        let container = NSView()

        let audioLabel = label(L10n.text("accounts.form.audioBpsLimit"))
        let cmdLimitLabel = label(L10n.text("accounts.form.commandsLimit"))
        let cmdIntervalLabel = label(L10n.text("accounts.form.commandsInterval"))

        for field in [audioBpsField, commandsLimitField, commandsIntervalField] as [NSView] {
            field.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(field)
        }

        let stackItems: [(NSView, NSView)] = [
            (audioLabel, audioBpsField),
            (cmdLimitLabel, commandsLimitField),
            (cmdIntervalLabel, commandsIntervalField)
        ]

        var previousBottom = container.topAnchor
        for (lbl, field) in stackItems {
            lbl.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(lbl)
            NSLayoutConstraint.activate([
                lbl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                lbl.topAnchor.constraint(equalTo: previousBottom, constant: 12),
                lbl.widthAnchor.constraint(equalToConstant: 200),
                field.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 8),
                field.widthAnchor.constraint(equalToConstant: 100),
                field.centerYAnchor.constraint(equalTo: lbl.centerYAnchor)
            ])
            previousBottom = lbl.bottomAnchor
        }

        return container
    }

    private func setupButtons() {
        let cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: L10n.text("common.save"), target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(cancelButton)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            saveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Populate

    private func populate() {
        switch mode {
        case .create:
            userRights = UserAccountProperties.defaultUserRights
            typePopUp.selectItem(at: 0)
            usernameField.isEditable = true
        case .edit(let account):
            usernameField.stringValue = account.username
            passwordField.stringValue = account.password
            initChannelField.stringValue = account.initChannel
            noteField.stringValue = account.note
            switch account.userType {
            case .defaultUser: typePopUp.selectItem(at: 0)
            case .admin:       typePopUp.selectItem(at: 1)
            case .disabled:    typePopUp.selectItem(at: 2)
            }
            userRights = account.userRights
            audioBpsField.stringValue = account.audioBpsLimit == 0 ? "" : "\(account.audioBpsLimit)"
            commandsLimitField.stringValue = account.commandsLimit == 0 ? "" : "\(account.commandsLimit)"
            commandsIntervalField.stringValue = account.commandsIntervalMSec == 0 ? "" : "\(account.commandsIntervalMSec)"
        }
        rightsTableView.reloadData()
    }

    // MARK: - Rights actions

    @objc private func enableAllRights() {
        userRights = allUserRights.reduce(0) { $0 | $1.bit }
        rightsTableView.reloadData()
    }

    @objc private func disableAllRights() {
        userRights = 0
        rightsTableView.reloadData()
    }

    @objc private func defaultRights() {
        userRights = UserAccountProperties.defaultUserRights
        rightsTableView.reloadData()
    }

    // MARK: - Form actions

    @objc private func cancel() {
        dismiss(nil)
    }

    @objc private func save() {
        var account = UserAccountProperties()
        account.username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        account.password = passwordField.stringValue
        switch typePopUp.indexOfSelectedItem {
        case 0: account.userType = .defaultUser
        case 1: account.userType = .admin
        default: account.userType = .disabled
        }
        account.userRights = userRights
        account.initChannel = initChannelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        account.note = noteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        account.audioBpsLimit = Int32(audioBpsField.stringValue) ?? 0
        account.commandsLimit = Int32(commandsLimitField.stringValue) ?? 0
        account.commandsIntervalMSec = Int32(commandsIntervalField.stringValue) ?? 0

        guard account.username.isEmpty == false else { return }

        dismiss(nil)

        switch mode {
        case .create:
            connectionController?.createUserAccount(account) { [weak self] _ in
                self?.onSave()
            }
        case .edit(let original):
            connectionController?.updateUserAccount(originalUsername: original.username, updated: account) { [weak self] _ in
                self?.onSave()
            }
        }
    }

    // MARK: - Helpers

    private func label(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.lineBreakMode = .byTruncatingTail
        return lbl
    }
}

// MARK: - NSTableViewDataSource

extension UserAccountFormViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        allUserRights.count
    }
}

// MARK: - NSTableViewDelegate

extension UserAccountFormViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < allUserRights.count else { return nil }
        let right = allUserRights[row]

        switch tableColumn?.identifier.rawValue {
        case "check":
            let cellID = NSUserInterfaceItemIdentifier("rightCheck")
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = existing
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID
                let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                checkbox.translatesAutoresizingMaskIntoConstraints = false
                checkbox.tag = row
                checkbox.target = self
                checkbox.action = #selector(toggleRight(_:))
                cell.addSubview(checkbox)
                NSLayoutConstraint.activate([
                    checkbox.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            if let checkbox = cell.subviews.first(where: { $0 is NSButton }) as? NSButton {
                checkbox.state = (userRights & right.bit) != 0 ? .on : .off
                checkbox.tag = row
            }
            return cell

        case "label":
            let cellID = NSUserInterfaceItemIdentifier("rightLabel")
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
            cell.textField?.stringValue = right.label
            return cell

        default:
            return nil
        }
    }

    @objc private func toggleRight(_ sender: NSButton) {
        let row = sender.tag
        guard row < allUserRights.count else { return }
        let bit = allUserRights[row].bit
        if sender.state == .on {
            userRights |= bit
        } else {
            userRights &= ~bit
        }
    }
}
