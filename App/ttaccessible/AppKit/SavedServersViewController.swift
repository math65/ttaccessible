//
//  SavedServersViewController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit
import UniformTypeIdentifiers

final class SavedServersViewController: NSViewController {
    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("name")
        static let host = NSUserInterfaceItemIdentifier("host")
        static let tcp = NSUserInterfaceItemIdentifier("tcp")
        static let udp = NSUserInterfaceItemIdentifier("udp")
        static let secure = NSUserInterfaceItemIdentifier("secure")
    }

    private let store: SavedServerStore
    private let passwordStore: ServerPasswordStore
    private let preferencesStore: AppPreferencesStore
    private let menuState: SavedServersMenuState
    private let connectionController: TeamTalkConnectionController
    private let configImporter = TeamTalkConfigImporter()
    private let ttFileService = TTFileService()

    private var records: [SavedServerRecord] = []
    private var isConnecting = false

    private let titleLabel = NSTextField(labelWithString: L10n.text("savedServers.title"))
    private let subtitleLabel = NSTextField(labelWithString: L10n.text("savedServers.subtitle"))
    private let hintLabel = NSTextField(labelWithString: L10n.text("savedServers.hint"))
    private let tableView = SavedServersTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let sortLabel = NSTextField(labelWithString: L10n.text("savedServers.sort.label"))
    private let sortFieldPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sortDirectionPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private lazy var contextMenu: NSMenu = makeContextMenu()

    init(
        store: SavedServerStore,
        passwordStore: ServerPasswordStore,
        preferencesStore: AppPreferencesStore,
        menuState: SavedServersMenuState,
        connectionController: TeamTalkConnectionController
    ) {
        self.store = store
        self.passwordStore = passwordStore
        self.preferencesStore = preferencesStore
        self.menuState = menuState
        self.connectionController = connectionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        configureUI()
        reloadRecords(selecting: store.selectedServerID())
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(tableView)
    }

    private func configureUI() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view = backgroundView

        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2
        configureSortControls()

        tableView.headerView = NSTableHeaderView()
        if #available(macOS 11.0, *) {
            tableView.style = .inset
        }
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowSizeStyle = .large
        tableView.intercellSpacing = NSSize(width: 8, height: 6)
        tableView.target = self
        tableView.doubleAction = #selector(editSelectedServer)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.actionDelegate = self
        tableView.setAccessibilityLabel(L10n.text("savedServers.table.accessibilityLabel"))
        tableView.menu = contextMenu

        addColumn(title: L10n.text("savedServers.column.name"), identifier: Column.name, width: 180)
        addColumn(title: L10n.text("savedServers.column.host"), identifier: Column.host, width: 220)
        addColumn(title: L10n.text("savedServers.column.tcp"), identifier: Column.tcp, width: 80)
        addColumn(title: L10n.text("savedServers.column.udp"), identifier: Column.udp, width: 80)
        addColumn(title: L10n.text("savedServers.column.secure"), identifier: Column.secure, width: 100)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let sortControlsStack = NSStackView(views: [sortLabel, sortFieldPopUp, sortDirectionPopUp])
        sortControlsStack.orientation = .horizontal
        sortControlsStack.alignment = .centerY
        sortControlsStack.spacing = 8
        sortControlsStack.translatesAutoresizingMaskIntoConstraints = false
        sortControlsStack.setContentHuggingPriority(.required, for: .horizontal)

        let headerSpacer = NSView()
        headerSpacer.translatesAutoresizingMaskIntoConstraints = false
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerRowStack = NSStackView(views: [headerStack, headerSpacer, sortControlsStack])
        headerRowStack.orientation = .horizontal
        headerRowStack.alignment = .top
        headerRowStack.spacing = 12
        headerRowStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [headerRowStack, scrollView, hintLabel])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 600),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])

        updateActionState()
    }

    private func configureSortControls() {
        sortLabel.textColor = .secondaryLabelColor

        sortFieldPopUp.removeAllItems()
        for field in AppPreferences.SavedServersSortField.allCases {
            sortFieldPopUp.addItem(withTitle: title(for: field))
            sortFieldPopUp.lastItem?.representedObject = field.rawValue
        }
        sortFieldPopUp.target = self
        sortFieldPopUp.action = #selector(sortFieldChanged(_:))
        sortFieldPopUp.setAccessibilityLabel(L10n.text("savedServers.sort.field.accessibilityLabel"))

        sortDirectionPopUp.removeAllItems()
        sortDirectionPopUp.addItem(withTitle: L10n.text("savedServers.sort.direction.ascending"))
        sortDirectionPopUp.lastItem?.representedObject = true
        sortDirectionPopUp.addItem(withTitle: L10n.text("savedServers.sort.direction.descending"))
        sortDirectionPopUp.lastItem?.representedObject = false
        sortDirectionPopUp.target = self
        sortDirectionPopUp.action = #selector(sortDirectionChanged(_:))
        sortDirectionPopUp.setAccessibilityLabel(L10n.text("savedServers.sort.direction.accessibilityLabel"))

        syncSortControlsFromPreferences()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.text("savedServers.menu.title"))

        let editItem = NSMenuItem(
            title: L10n.text("savedServers.menu.edit"),
            action: #selector(editSelectedServer),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        let deleteItem = NSMenuItem(
            title: L10n.text("savedServers.menu.delete"),
            action: #selector(deleteSelectedServer),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)

        let exportItem = NSMenuItem(
            title: L10n.text("savedServers.menu.exportTT"),
            action: #selector(exportSelectedTTFile),
            keyEquivalent: ""
        )
        exportItem.target = self
        menu.addItem(exportItem)

        return menu
    }

    private func addColumn(title: String, identifier: NSUserInterfaceItemIdentifier, width: CGFloat) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func reloadRecords(selecting id: UUID?) {
        records = sortedRecords(store.load())
        syncSortControlsFromPreferences()
        tableView.reloadData()
        selectRecord(id)
        updateEmptyStateAccessibility()
        updateActionState()
    }

    private func syncSortControlsFromPreferences() {
        let sort = preferencesStore.preferences.savedServersSort
        if let item = sortFieldPopUp.itemArray.first(where: {
            ($0.representedObject as? String) == sort.field.rawValue
        }) {
            sortFieldPopUp.select(item)
        }
        if let item = sortDirectionPopUp.itemArray.first(where: {
            ($0.representedObject as? Bool) == sort.ascending
        }) {
            sortDirectionPopUp.select(item)
        }
    }

    private func title(for field: AppPreferences.SavedServersSortField) -> String {
        switch field {
        case .manual:
            return L10n.text("savedServers.sort.field.manual")
        case .name:
            return L10n.text("savedServers.sort.field.name")
        case .host:
            return L10n.text("savedServers.sort.field.host")
        case .tcpPort:
            return L10n.text("savedServers.sort.field.tcp")
        case .udpPort:
            return L10n.text("savedServers.sort.field.udp")
        }
    }

    private func sortedRecords(_ source: [SavedServerRecord]) -> [SavedServerRecord] {
        let sort = preferencesStore.preferences.savedServersSort
        guard sort.field != .manual else {
            return sort.ascending ? source : Array(source.reversed())
        }

        return source.enumerated().sorted { lhs, rhs in
            let comparison = compare(lhs.element, rhs.element, by: sort.field)
            if comparison == .orderedSame {
                return lhs.offset < rhs.offset
            }
            return sort.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        .map(\.element)
    }

    private func compare(
        _ lhs: SavedServerRecord,
        _ rhs: SavedServerRecord,
        by field: AppPreferences.SavedServersSortField
    ) -> ComparisonResult {
        switch field {
        case .manual:
            return .orderedSame
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .host:
            return lhs.host.localizedCaseInsensitiveCompare(rhs.host)
        case .tcpPort:
            if lhs.tcpPort == rhs.tcpPort { return .orderedSame }
            return lhs.tcpPort < rhs.tcpPort ? .orderedAscending : .orderedDescending
        case .udpPort:
            if lhs.udpPort == rhs.udpPort { return .orderedSame }
            return lhs.udpPort < rhs.udpPort ? .orderedAscending : .orderedDescending
        }
    }

    private func selectRecord(_ id: UUID?) {
        guard let id, let row = records.firstIndex(where: { $0.id == id }) else {
            tableView.deselectAll(nil)
            store.setSelectedServer(id: nil)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        store.setSelectedServer(id: id)
    }

    private var selectedRow: Int? {
        let row = tableView.selectedRow
        return row >= 0 ? row : nil
    }

    private var selectedRecord: SavedServerRecord? {
        guard let row = selectedRow, records.indices.contains(row) else {
            return nil
        }
        return records[row]
    }

    private func updateActionState() {
        menuState.setHasSelection(selectedRecord != nil)
    }

    private func updateEmptyStateAccessibility() {
        if records.isEmpty {
            tableView.setAccessibilityHelp(L10n.text("savedServers.table.emptyHelp"))
        } else {
            tableView.setAccessibilityHelp(L10n.text("savedServers.table.help"))
        }
    }

    func connectSelectedServer() {
        guard let record = selectedRecord, isConnecting == false else {
            return
        }

        let password: String
        let channelPassword: String
        do {
            password = try passwordStore.password(for: record.id) ?? ""
            channelPassword = try passwordStore.channelPassword(for: record.id) ?? record.initialChannelPassword
        } catch {
            presentErrorAlert(message: error.localizedDescription)
            return
        }

        isConnecting = true
        let options = TeamTalkConnectOptions(
            initialChannelPath: record.initialChannelPath,
            initialChannelPassword: channelPassword
        )
        connectionController.connect(to: record, password: password, options: options) { [weak self] result in
            guard let self else {
                return
            }

            self.isConnecting = false

            switch result {
            case .success:
                return
            case .failure(let error):
                self.presentErrorAlert(message: error.localizedDescription)
            }
        }
    }

    func focusTable() {
        view.window?.makeFirstResponder(tableView)
    }

    @objc
    private func sortFieldChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let field = AppPreferences.SavedServersSortField(rawValue: rawValue) else {
            return
        }
        let selectedID = selectedRecord?.id ?? store.selectedServerID()
        preferencesStore.updateSavedServersSortField(field)
        reloadRecords(selecting: selectedID)
    }

    @objc
    private func sortDirectionChanged(_ sender: NSPopUpButton) {
        guard let ascending = sender.selectedItem?.representedObject as? Bool else {
            return
        }
        let selectedID = selectedRecord?.id ?? store.selectedServerID()
        preferencesStore.updateSavedServersSortAscending(ascending)
        reloadRecords(selecting: selectedID)
    }

    @objc
    func importTeamTalkServers(_ sender: Any? = nil) {
        let sourceURL: URL?
        if preferencesStore.preferences.prefersAutomaticTeamTalkConfigDetection {
            sourceURL = configImporter.defaultConfigURL() ?? promptForImportFile()
        } else {
            sourceURL = promptForImportFile()
        }
        guard let sourceURL else {
            return
        }

        do {
            let result = try configImporter.importServers(
                from: sourceURL,
                into: store,
                passwordStore: passwordStore
            )
            reloadRecords(selecting: store.selectedServerID())
            presentImportSummary(result)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    @objc
    func addServer(_ sender: Any? = nil) {
        let draft = SavedServerDraft(nickname: preferencesStore.preferences.defaultNickname)
        let controller = SavedServerEditorWindowController(mode: .add, draft: draft, parentWindow: view.window)

        guard let result = controller.runModal(),
              let record = result.makeRecord(id: UUID()) else {
            return
        }

        do {
            try passwordStore.setPassword(result.password, for: record.id)
            try passwordStore.setChannelPassword(result.initialChannelPassword, for: record.id)
            store.add(record)
            store.setSelectedServer(id: record.id)
            reloadRecords(selecting: record.id)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    @objc
    func editSelectedServer(_ sender: Any? = nil) {
        guard let record = selectedRecord else {
            return
        }

        let password: String
        let initialChannelPassword: String
        do {
            password = try passwordStore.password(for: record.id) ?? ""
            initialChannelPassword = try passwordStore.channelPassword(for: record.id) ?? record.initialChannelPassword
        } catch {
            presentErrorAlert(message: error.localizedDescription)
            return
        }

        let draft = SavedServerDraft(record: record, password: password, initialChannelPassword: initialChannelPassword)
        let controller = SavedServerEditorWindowController(mode: .edit, draft: draft, parentWindow: view.window)

        guard let result = controller.runModal(),
              let updatedRecord = result.makeRecord(id: record.id) else {
            return
        }

        do {
            try passwordStore.setPassword(result.password, for: record.id)
            try passwordStore.setChannelPassword(result.initialChannelPassword, for: record.id)
            store.update(updatedRecord)
            store.setSelectedServer(id: record.id)
            reloadRecords(selecting: record.id)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    @objc
    func deleteSelectedServer(_ sender: Any? = nil) {
        guard let record = selectedRecord,
              let row = selectedRow else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("savedServers.alert.delete.title")
        alert.informativeText = L10n.format("savedServers.alert.delete.message", record.name)
        alert.addButton(withTitle: L10n.text("savedServers.alert.delete.confirm"))
        alert.addButton(withTitle: L10n.text("savedServers.alert.delete.cancel"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        let nextSelectionID = nextRecordIDAfterDeletion(of: row)

        do {
            try passwordStore.deletePassword(for: record.id)
            try passwordStore.deleteChannelPassword(for: record.id)
            store.delete(id: record.id)
            store.setSelectedServer(id: nextSelectionID)
            reloadRecords(selecting: nextSelectionID)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    @objc
    func exportSelectedTTFile(_ sender: Any? = nil) {
        guard let record = selectedRecord else {
            return
        }

        let password: String
        let channelPassword: String
        do {
            password = try passwordStore.password(for: record.id) ?? ""
            channelPassword = try passwordStore.channelPassword(for: record.id) ?? record.initialChannelPassword
        } catch {
            presentErrorAlert(message: error.localizedDescription)
            return
        }

        guard let data = ttFileService.generateFileContents(
            record: record,
            password: password,
            defaultJoinChannelPath: record.initialChannelPath.isEmpty ? nil : record.initialChannelPath,
            defaultJoinPassword: channelPassword,
            defaultStatusMessage: preferencesStore.preferences.defaultStatusMessage,
            defaultGender: preferencesStore.preferences.defaultGender
        ) else {
            presentErrorAlert(message: L10n.text("ttFile.export.error.unreadable"))
            return
        }

        let panel = NSSavePanel()
        panel.title = L10n.text("ttFile.export.panel.title")
        panel.nameFieldStringValue = sanitizedTTFileName(for: record.name)
        panel.allowedContentTypes = [.init(filenameExtension: "tt") ?? .data]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    private func sanitizedTTFileName(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "server" : trimmed
        return baseName.replacingOccurrences(of: "/", with: "-") + ".tt"
    }

    private func nextRecordIDAfterDeletion(of row: Int) -> UUID? {
        if row + 1 < records.count {
            return records[row + 1].id
        }

        if row - 1 >= 0 {
            return records[row - 1].id
        }

        return nil
    }

    private func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text("savedServers.alert.error.title")
        alert.informativeText = message
        alert.runModal()
    }

    private func presentImportSummary(_ result: TeamTalkImportResult) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("teamTalkImport.alert.success.title")
        alert.informativeText = L10n.format(
            "teamTalkImport.alert.success.message",
            result.importedCount,
            result.skippedCount,
            result.sourceURL.lastPathComponent
        )
        alert.runModal()
    }

    private func promptForImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = L10n.text("teamTalkImport.openPanel.title")
        panel.message = L10n.text("teamTalkImport.openPanel.message")
        panel.prompt = L10n.text("teamTalkImport.openPanel.prompt")
        panel.allowedContentTypes = [.init(filenameExtension: "ini") ?? .data, .propertyList]
        panel.directoryURL = configImporter.defaultConfigDirectoryURL()
        panel.nameFieldStringValue = configImporter.defaultConfigURL()?.lastPathComponent ?? "TeamTalk5.ini"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        configImporter.rememberAccess(to: url)
        return url
    }
}

extension SavedServersViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        records.count
    }
}

extension SavedServersViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        store.setSelectedServer(id: selectedRecord?.id)
        updateActionState()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard records.indices.contains(row) else { return nil }
        return records[row].name
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard records.indices.contains(row), let tableColumn else {
            return nil
        }

        let value: String
        let record = records[row]

        switch tableColumn.identifier {
        case Column.name:
            value = record.name
        case Column.host:
            value = record.host
        case Column.tcp:
            value = String(record.tcpPort)
        case Column.udp:
            value = String(record.udpPort)
        case Column.secure:
            value = record.encrypted ? L10n.text("savedServers.secure.yes") : L10n.text("savedServers.secure.no")
        default:
            value = ""
        }

        let identifier = NSUserInterfaceItemIdentifier("SavedServersCell-\(tableColumn.identifier.rawValue)")
        let textField: NSTextField

        if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = cell
        } else {
            textField = NSTextField(labelWithString: value)
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingTail
        }

        textField.stringValue = value
        return textField
    }
}

extension SavedServersViewController: SavedServersTableViewActionDelegate {
    func savedServersTableViewDidRequestConnect(_ tableView: SavedServersTableView) {
        connectSelectedServer()
    }

    func savedServersTableViewDidRequestDelete(_ tableView: SavedServersTableView) {
        deleteSelectedServer(nil)
    }

    func savedServersTableView(_ tableView: SavedServersTableView, menuForRow row: Int) -> NSMenu? {
        contextMenu
    }
}

extension SavedServersViewController: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(editSelectedServer(_:)), #selector(deleteSelectedServer(_:)):
            return selectedRecord != nil
        case #selector(importTeamTalkServers(_:)):
            return true
        case #selector(addServer(_:)):
            return true
        default:
            return true
        }
    }
}
