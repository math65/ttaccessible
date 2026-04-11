//
//  ChannelFilesViewController.swift
//  ttaccessible
//

import AppKit

// MARK: - Table subclass pour capturer Return/Delete

private final class FilesTableView: NSTableView {
    var onReturnKey: (() -> Void)?
    var onDeleteKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturnKey?()
        case 51:     onDeleteKey?()
        default:     super.keyDown(with: event)
        }
    }
}

// MARK: - ViewController

final class ChannelFilesViewController: NSViewController {
    private enum Col {
        static let name     = NSUserInterfaceItemIdentifier("fileName")
        static let size     = NSUserInterfaceItemIdentifier("fileSize")
        static let uploader = NSUserInterfaceItemIdentifier("fileUploader")
    }

    private let connectionController: TeamTalkConnectionController
    private var session: ConnectedServerSession
    private var sortDescriptors: [NSSortDescriptor] = []

    // Calcul vitesse de transfert
    private var lastTransferID: Int32 = 0
    private var speedSampleTransferred: Int64 = 0
    private var speedSampleDate = Date()
    private var speedBytesPerSecond: Double = 0
    private var cancelledTransferIDs: Set<Int32> = []

    private var sortedFiles: [ChannelFile] {
        guard !sortDescriptors.isEmpty else { return session.channelFiles }
        return session.channelFiles.sorted { a, b in
            for descriptor in sortDescriptors {
                let result: ComparisonResult
                switch descriptor.key {
                case "name":     result = a.name.compare(b.name, options: .caseInsensitive)
                case "size":     result = a.size < b.size ? .orderedAscending : a.size > b.size ? .orderedDescending : .orderedSame
                case "uploader": result = a.uploader.compare(b.uploader, options: .caseInsensitive)
                default: continue
                }
                if result != .orderedSame {
                    return descriptor.ascending ? result == .orderedAscending : result == .orderedDescending
                }
            }
            return false
        }
    }

    private var activeUploadTransfers: [FileTransferProgress] {
        session.activeTransfers.filter { transfer in
            !transfer.isDownload && !session.channelFiles.contains { $0.name == transfer.fileName }
        }
    }

    private let filesTableView    = FilesTableView(frame: .zero)
    private let filesScrollView   = NSScrollView(frame: .zero)
    private let titleLabel        = NSTextField(labelWithString: "")
    private let emptyLabel        = NSTextField(labelWithString: "")
    private let uploadButton      = NSButton(title: "", target: nil, action: nil)
    private let downloadButton    = NSButton(title: "", target: nil, action: nil)
    private let deleteButton      = NSButton(title: "", target: nil, action: nil)

    // Footer de progression (style Finder)
    private let transferFooterView  = NSView()
    private let transferProgressBar = NSProgressIndicator()
    private let transferNameLabel   = NSTextField(labelWithString: "")
    private let transferStatsLabel  = NSTextField(labelWithString: "")
    private let transferCancelButton = NSButton(title: "", target: nil, action: nil)

    init(session: ConnectedServerSession, connectionController: TeamTalkConnectionController) {
        self.session = session
        self.connectionController = connectionController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        configureUI()
        reloadFiles(previousFiles: nil, previousUploads: nil)
        updateTransferFooter()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(filesTableView)
        view.window?.initialFirstResponder = filesTableView
    }

    func update(session: ConnectedServerSession) {
        let oldFiles = self.session.channelFiles
        let oldUploads = activeUploadTransfers
        let oldUploadIDs = Set(activeUploadTransfers.map(\.transferID))

        self.session = session

        let newUploadIDs = Set(activeUploadTransfers.map(\.transferID))
        if session.channelFiles != oldFiles || newUploadIDs != oldUploadIDs {
            reloadFiles(previousFiles: oldFiles, previousUploads: oldUploads)
        }

        updateTransferFooter()
    }

    func updateActiveTransfers(_ transfers: [FileTransferProgress], currentChannelID: Int32) {
        guard currentChannelID == session.currentChannelID else {
            return
        }

        let oldFiles = session.channelFiles
        let oldUploads = activeUploadTransfers
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
            activeTransfers: transfers,
            outputAudioReady: session.outputAudioReady,
            inputAudioReady: session.inputAudioReady,
            voiceTransmissionEnabled: session.voiceTransmissionEnabled,
            canSendBroadcast: session.canSendBroadcast,
            audioStatusText: session.audioStatusText,
            inputGainDB: session.inputGainDB,
            outputGainDB: session.outputGainDB,
            recordingActive: session.recordingActive
        )
        if oldUploads != activeUploadTransfers {
            reloadFiles(previousFiles: oldFiles, previousUploads: oldUploads)
        }
        updateTransferFooter()
    }

    func announceTransferResult(fileName: String, isDownload: Bool, success: Bool) {
        guard view.window?.isVisible == true else { return }
        let key: String
        if success {
            key = isDownload ? "files.transfer.downloaded" : "files.transfer.uploaded"
        } else {
            key = isDownload ? "files.transfer.downloadFailed" : "files.transfer.uploadFailed"
        }
        announce(L10n.format(key, fileName))
    }

    func performUpload() {
        promptUpload()
    }

    // MARK: - UI

    private func configureUI() {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view = backgroundView

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.stringValue = L10n.text("files.window.title")
        titleLabel.setAccessibilityElement(false)

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.alignment = .center
        emptyLabel.stringValue = L10n.text("files.empty")
        emptyLabel.setAccessibilityElement(false)

        let nameColumn = NSTableColumn(identifier: Col.name)
        nameColumn.title = L10n.text("files.column.name")
        nameColumn.width = 280
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)

        let sizeColumn = NSTableColumn(identifier: Col.size)
        sizeColumn.title = L10n.text("files.column.size")
        sizeColumn.width = 90
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)

        let uploaderColumn = NSTableColumn(identifier: Col.uploader)
        uploaderColumn.title = L10n.text("files.column.uploader")
        uploaderColumn.width = 160
        uploaderColumn.resizingMask = .autoresizingMask
        uploaderColumn.sortDescriptorPrototype = NSSortDescriptor(key: "uploader", ascending: true)

        filesTableView.addTableColumn(nameColumn)
        filesTableView.addTableColumn(sizeColumn)
        filesTableView.addTableColumn(uploaderColumn)
        if #available(macOS 11.0, *) {
            filesTableView.style = .inset
        }
        filesTableView.rowSizeStyle = .default
        filesTableView.allowsEmptySelection = true
        filesTableView.delegate = self
        filesTableView.dataSource = self
        filesTableView.target = self
        filesTableView.doubleAction = #selector(downloadSelectedFile)
        filesTableView.setAccessibilityLabel(L10n.text("files.table.accessibilityLabel"))
        filesTableView.onReturnKey = { [weak self] in self?.downloadSelectedFile() }
        filesTableView.onDeleteKey = { [weak self] in self?.deleteSelectedFile() }

        filesScrollView.documentView = filesTableView
        filesScrollView.hasVerticalScroller = true
        filesScrollView.drawsBackground = false
        filesScrollView.borderType = .noBorder

        uploadButton.title   = L10n.text("files.action.upload")
        uploadButton.target  = self
        uploadButton.action  = #selector(promptUpload)
        uploadButton.setAccessibilityLabel(L10n.text("files.action.upload.accessibilityLabel"))

        downloadButton.title  = L10n.text("files.action.download")
        downloadButton.target = self
        downloadButton.action = #selector(downloadSelectedFile)
        downloadButton.setAccessibilityLabel(L10n.text("files.action.download.accessibilityLabel"))
        downloadButton.isEnabled = false

        deleteButton.title  = L10n.text("files.action.delete")
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedFile)
        deleteButton.setAccessibilityLabel(L10n.text("files.action.delete.accessibilityLabel"))
        deleteButton.isEnabled = false

        let buttonStack = NSStackView(views: [uploadButton, downloadButton, deleteButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment   = .centerY
        buttonStack.spacing     = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        configureTransferFooter()

        let mainStack = NSStackView(views: [titleLabel, filesScrollView, emptyLabel, buttonStack, transferFooterView])
        mainStack.orientation = .vertical
        mainStack.alignment   = .leading
        mainStack.spacing     = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            filesScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            filesScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            buttonStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            transferFooterView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        view.setAccessibilityChildrenInNavigationOrder([filesTableView, uploadButton, downloadButton, deleteButton, transferFooterView])
        filesTableView.nextKeyView = uploadButton
        uploadButton.nextKeyView   = downloadButton
        downloadButton.nextKeyView = deleteButton
        deleteButton.nextKeyView   = filesTableView
    }

    private func configureTransferFooter() {
        transferFooterView.wantsLayer = true
        transferFooterView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
        transferFooterView.layer?.cornerRadius = 8
        transferFooterView.translatesAutoresizingMaskIntoConstraints = false
        transferFooterView.isHidden = true
        transferFooterView.setAccessibilityRole(.group)

        transferProgressBar.style = .bar
        transferProgressBar.isIndeterminate = false
        transferProgressBar.minValue = 0
        transferProgressBar.maxValue = 100
        transferProgressBar.doubleValue = 0
        transferProgressBar.translatesAutoresizingMaskIntoConstraints = false
        transferProgressBar.setAccessibilityElement(false)

        transferNameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        transferNameLabel.textColor = .labelColor
        transferNameLabel.lineBreakMode = .byTruncatingMiddle
        transferNameLabel.translatesAutoresizingMaskIntoConstraints = false
        transferNameLabel.setAccessibilityElement(false)

        transferStatsLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        transferStatsLabel.textColor = .secondaryLabelColor
        transferStatsLabel.translatesAutoresizingMaskIntoConstraints = false
        transferStatsLabel.setAccessibilityElement(false)

        transferCancelButton.title = L10n.text("files.transfer.cancel")
        transferCancelButton.bezelStyle = .inline
        transferCancelButton.controlSize = .small
        transferCancelButton.target = self
        transferCancelButton.action = #selector(cancelActiveTransfer)
        transferCancelButton.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [transferNameLabel, transferStatsLabel, transferCancelButton])
        topRow.orientation = .horizontal
        topRow.alignment   = .centerY
        topRow.spacing     = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false
        // Le nom prend tout l'espace disponible
        topRow.setHuggingPriority(.defaultLow, for: .horizontal)
        transferNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        transferStatsLabel.setContentHuggingPriority(.required, for: .horizontal)
        transferCancelButton.setContentHuggingPriority(.required, for: .horizontal)

        transferFooterView.addSubview(topRow)
        transferFooterView.addSubview(transferProgressBar)

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: transferFooterView.topAnchor, constant: 10),
            topRow.leadingAnchor.constraint(equalTo: transferFooterView.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: transferFooterView.trailingAnchor, constant: -12),

            transferProgressBar.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 6),
            transferProgressBar.leadingAnchor.constraint(equalTo: transferFooterView.leadingAnchor, constant: 12),
            transferProgressBar.trailingAnchor.constraint(equalTo: transferFooterView.trailingAnchor, constant: -12),
            transferProgressBar.bottomAnchor.constraint(equalTo: transferFooterView.bottomAnchor, constant: -10),
        ])
    }

    private func updateTransferFooter() {
        // Clean up cancelled transfer IDs that are no longer in the session
        cancelledTransferIDs = cancelledTransferIDs.filter { id in
            session.activeTransfers.contains { $0.transferID == id }
        }

        guard let transfer = session.activeTransfers.first(where: { !cancelledTransferIDs.contains($0.transferID) }) else {
            transferFooterView.isHidden = true
            lastTransferID = 0
            speedBytesPerSecond = 0
            return
        }

        // Calcul vitesse
        let now = Date()
        if transfer.transferID != lastTransferID {
            lastTransferID = transfer.transferID
            speedSampleTransferred = transfer.transferred
            speedSampleDate = now
            speedBytesPerSecond = 0
        } else {
            let elapsed = now.timeIntervalSince(speedSampleDate)
            if elapsed >= 0.75 {
                let delta = transfer.transferred - speedSampleTransferred
                speedBytesPerSecond = elapsed > 0 ? Double(delta) / elapsed : 0
                speedSampleTransferred = transfer.transferred
                speedSampleDate = now
            }
        }

        let pct = transfer.percent
        transferProgressBar.doubleValue = Double(pct)

        let direction = transfer.isDownload
            ? L10n.text("files.transfer.footer.download")
            : L10n.text("files.transfer.footer.upload")
        transferNameLabel.stringValue = "\(direction) : \(transfer.fileName)"

        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        let done  = fmt.string(fromByteCount: transfer.transferred)
        let total = fmt.string(fromByteCount: transfer.total)
        let speed = fmt.string(fromByteCount: Int64(speedBytesPerSecond))

        var statsText = "\(done) / \(total)  ·  \(speed)/s  ·  \(pct) %"
        var remainingText = ""
        if speedBytesPerSecond > 0, transfer.transferred < transfer.total {
            let secondsLeft = Double(transfer.total - transfer.transferred) / speedBytesPerSecond
            let timeFmt = DateComponentsFormatter()
            timeFmt.unitsStyle = .abbreviated
            timeFmt.allowedUnits = secondsLeft >= 3600 ? [.hour, .minute] : secondsLeft >= 60 ? [.minute, .second] : [.second]
            timeFmt.maximumUnitCount = 2
            if let formatted = timeFmt.string(from: secondsLeft) {
                statsText += "  ·  \(formatted)"
                remainingText = ", \(formatted) restantes"
            }
        }
        transferStatsLabel.stringValue = statsText

        // Label VoiceOver sur le conteneur
        transferFooterView.setAccessibilityLabel(
            "\(direction) : \(transfer.fileName), \(pct) %, \(done) sur \(total), \(speed) par seconde\(remainingText)"
        )

        transferFooterView.isHidden = false
    }

    @objc private func cancelActiveTransfer() {
        guard let transfer = session.activeTransfers.first(where: { !cancelledTransferIDs.contains($0.transferID) }) else { return }
        cancelledTransferIDs.insert(transfer.transferID)
        connectionController.cancelFileTransfer(transferID: transfer.transferID)
        updateTransferFooter()
    }

    private func reloadFiles(previousFiles: [ChannelFile]?, previousUploads: [FileTransferProgress]?) {
        let selectedID = selectedFile?.id
        if let previousFiles, let previousUploads {
            let newFiles = sortedFiles
            let newUploads = activeUploadTransfers
            if previousFiles.map(\.id) == newFiles.map(\.id),
               previousUploads.map(\.transferID) == newUploads.map(\.transferID) {
                let changedRows = IndexSet(
                    (0 ..< (newFiles.count + newUploads.count)).compactMap { row in
                        if row < newFiles.count {
                            return previousFiles.indices.contains(row) && previousFiles[row] == newFiles[row] ? nil : row
                        }
                        let uploadRow = row - newFiles.count
                        return previousUploads.indices.contains(uploadRow) && newUploads.indices.contains(uploadRow)
                            && previousUploads[uploadRow] == newUploads[uploadRow] ? nil : row
                    }
                )
                if changedRows.isEmpty == false {
                    filesTableView.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integersIn: 0 ..< filesTableView.numberOfColumns))
                }
            } else {
                filesTableView.reloadData()
            }
        } else {
            filesTableView.reloadData()
        }
        if let id = selectedID,
           let row = sortedFiles.firstIndex(where: { $0.id == id }) {
            filesTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let hasContent = !session.channelFiles.isEmpty || !activeUploadTransfers.isEmpty
        emptyLabel.isHidden      = hasContent
        filesScrollView.isHidden = !hasContent
        updateButtonStates()
    }

    private func updateButtonStates() {
        let file = selectedFile
        uploadButton.isEnabled   = session.currentChannelID > 0
        downloadButton.isEnabled = file != nil
        if let file, let me = session.currentUser {
            deleteButton.isEnabled = me.isAdministrator || me.isChannelOperator || file.uploader == me.username
        } else {
            deleteButton.isEnabled = false
        }
    }

    private var selectedFile: ChannelFile? {
        let row = filesTableView.selectedRow
        let files = sortedFiles
        guard row >= 0, files.indices.contains(row) else { return nil }
        return files[row]
    }

    // MARK: - Actions

    @objc private func promptUpload() {
        guard let window = view.window else { return }

        let panel = NSOpenPanel()
        panel.title = L10n.text("files.upload.panelTitle")
        panel.prompt = L10n.text("files.upload.panelPrompt")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.announce(L10n.format("files.transfer.uploadStarted", url.lastPathComponent))
            self.connectionController.sendFile(toChannelID: self.session.currentChannelID, localPath: url.path) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func downloadSelectedFile() {
        guard let file = selectedFile, let window = view.window else { return }

        let panel = NSSavePanel()
        panel.title = L10n.text("files.download.panelTitle")
        panel.prompt = L10n.text("files.download.panelPrompt")
        panel.nameFieldStringValue = file.name

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.announce(L10n.format("files.transfer.downloadStarted", file.name))
            self.connectionController.receiveFile(fromChannelID: file.channelID, fileID: file.id, toLocalPath: url.path) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.presentActionError(error.localizedDescription)
                }
            }
        }
    }

    @objc private func deleteSelectedFile() {
        guard let file = selectedFile else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.format("files.delete.title", file.name)
        alert.informativeText = L10n.text("files.delete.message")
        alert.addButton(withTitle: L10n.text("files.delete.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        guard let window = view.window, alert.runModal() == .alertFirstButtonReturn else { return }
        _ = window

        connectionController.deleteChannelFile(channelID: file.channelID, fileID: file.id) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.presentActionError(error.localizedDescription)
            }
        }
    }

    private func presentActionError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text("connectedServer.action.error.title")
        alert.informativeText = message
        alert.runModal()
    }

    private func announce(_ message: String) {
        let element = NSApp.accessibilityWindow() ?? view.window ?? view
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

extension ChannelFilesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        sortedFiles.count + activeUploadTransfers.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortDescriptors = tableView.sortDescriptors
        let selectedID = selectedFile?.id
        tableView.reloadData()
        if let id = selectedID,
           let row = sortedFiles.firstIndex(where: { $0.id == id }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        updateButtonStates()
    }
}

extension ChannelFilesViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let files = sortedFiles
        let uploads = activeUploadTransfers
        let identifier = tableColumn?.identifier ?? Col.name

        let cell: NSTextField
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            cell = existing
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = identifier
            cell.lineBreakMode = .byTruncatingTail
        }

        if row < files.count {
            let file = files[row]
            switch identifier {
            case Col.name:     cell.stringValue = file.name
            case Col.size:     cell.stringValue = file.formattedSize
            case Col.uploader: cell.stringValue = file.uploader
            default: break
            }
        } else {
            let uploadIndex = row - files.count
            guard uploads.indices.contains(uploadIndex) else { return nil }
            let transfer = uploads[uploadIndex]
            switch identifier {
            case Col.name:     cell.stringValue = transfer.fileName
            case Col.size:     cell.stringValue = ""
            case Col.uploader: cell.stringValue = ""
            default: break
            }
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }
}
