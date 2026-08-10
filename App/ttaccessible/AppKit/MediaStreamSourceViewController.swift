//
//  MediaStreamSourceViewController.swift
//  ttaccessible
//
//  "Choose what to stream" sheet: a checkbox list of every source — all system
//  audio, the input devices, VoiceOver and the running applications — plus the
//  monitor and mute-source options.
//
//  A LIST, not a pop-up menu, because applications cumulate: both capture
//  backends mix several processes themselves (see DeviceStreamCaptureSpec.merging),
//  so streaming Music and VoiceOver together only ever needed an interface that
//  can express it. Devices don't cumulate — a device is captured by an entirely
//  different backend — so ticking one clears the applications, and vice versa.
//  That exclusion is announced: silently unticking a line is unintelligible when
//  you can't see the list.
//
//  This is a SHEET hosting a plain view controller, not an NSAlert. That is what
//  made the old menu work: in a modal session AppKit never delivers an
//  NSMenuItem's action, so no source could be selected at all. The list has no
//  such constraint, but the sheet stays — an NSAlert would also swallow the
//  Add Application… panel.
//

import AppKit
import UniformTypeIdentifiers

/// Space toggles the selected line, the way a checkbox list is expected to
/// behave. Without this, the ticks are reachable by mouse and by VoiceOver but
/// not by the keyboard alone.
final class SourceListTableView: NSTableView {
    var onToggleSelectedRow: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 49, modifiers.isDisjoint(with: [.command, .option, .control, .shift]) {
            onToggleSelectedRow?()
            return
        }
        super.keyDown(with: event)
    }
}

final class MediaStreamSourceViewController: NSViewController {

    /// Confirmed with the chosen source, whether to monitor it locally, and
    /// whether to mute it on this Mac while streaming.
    var onStream: ((DeviceStreamCaptureSpec, Bool, Bool) -> Void)?

    private let devices: [InputAudioDeviceInfo]
    private var applicationSources: [DeviceStreamCaptureSpec]
    private let voiceOverAvailable: Bool
    private let allowsApplicationBrowsing: Bool
    private let allowsSystemAudio: Bool
    private let preselectedToken: String?
    private let fallbackDeviceUID: String?

    /// At most one device, any number of applications, or all system audio —
    /// the three are mutually exclusive.
    private var selectedDevice: InputAudioDeviceInfo?
    private var selectedApplications: [DeviceStreamCaptureSpec] = []
    private var systemAudioSelected = false

    private enum Row {
        case group(String)
        case source(DeviceStreamCaptureSpec)
    }

    private var rows: [Row] = []

    private var tableView: SourceListTableView!
    private var browseButton: NSButton?
    private var summaryLabel: NSTextField!
    private var monitorCheckbox: NSButton!
    private var muteSourceCheckbox: NSButton?
    private var streamButton: NSButton!

    /// - Parameters:
    ///   - allowsApplicationBrowsing: browsing for a not-yet-running app needs
    ///     the process-tap backend's wait-and-attach (macOS 14.2+); the
    ///     ScreenCaptureKit tier can only capture apps that are already running.
    ///   - allowsSystemAudio: capturing everything the Mac plays needs one of
    ///     the two process backends, so macOS 13 or later.
    init(devices: [InputAudioDeviceInfo],
         applicationSources: [DeviceStreamCaptureSpec],
         voiceOverAvailable: Bool,
         allowsApplicationBrowsing: Bool,
         allowsSystemAudio: Bool,
         preselectedToken: String?,
         fallbackDeviceUID: String?) {
        self.devices = devices
        self.applicationSources = applicationSources
        self.voiceOverAvailable = voiceOverAvailable
        self.allowsApplicationBrowsing = allowsApplicationBrowsing
        self.allowsSystemAudio = allowsSystemAudio
        self.preselectedToken = preselectedToken
        self.fallbackDeviceUID = fallbackDeviceUID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 460))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        rebuildRows()
        selectPreferredSource()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.initialFirstResponder = tableView
        view.window?.makeFirstResponder(tableView)
        // Return confirms even while the list holds focus; a key equivalent
        // alone doesn't carry in a sheet.
        view.window?.defaultButtonCell = streamButton.cell as? NSButtonCell
    }

    // MARK: - Rows

    /// Every selectable source, flat, in list order — used for preselection and
    /// for restoring a remembered choice.
    private var orderedSources: [DeviceStreamCaptureSpec] {
        var specs: [DeviceStreamCaptureSpec] = []
        if allowsSystemAudio { specs.append(.systemAudio()) }
        specs.append(contentsOf: devices.map { DeviceStreamCaptureSpec.inputDevice($0) })
        if voiceOverAvailable { specs.append(.voiceOver()) }
        specs.append(contentsOf: applicationSources)
        return specs
    }

    private func rebuildRows() {
        var rows: [Row] = []
        // All-system audio leads, ungrouped: it is the broadest answer to
        // "stream several apps", and it belongs to neither group.
        if allowsSystemAudio {
            rows.append(.source(.systemAudio()))
        }
        if devices.isEmpty == false {
            rows.append(.group(L10n.text("mediaStream.device.group.devices")))
            rows.append(contentsOf: devices.map { .source(.inputDevice($0)) })
        }
        if voiceOverAvailable || applicationSources.isEmpty == false {
            rows.append(.group(L10n.text("mediaStream.device.group.applications")))
            if voiceOverAvailable { rows.append(.source(.voiceOver())) }
            rows.append(contentsOf: applicationSources.map { .source($0) })
        }
        self.rows = rows
        tableView?.reloadData()
    }

    private func isSelected(_ spec: DeviceStreamCaptureSpec) -> Bool {
        switch spec {
        case .inputDevice(let device):
            return selectedDevice == device
        case .processes(let selection):
            if selection.capturesEntireSystem { return systemAudioSelected }
            return selectedApplications.contains(spec)
        }
    }

    // MARK: - Setup

    private func setupLayout() {
        let header = NSTextField(wrappingLabelWithString: L10n.text("mediaStream.device.prompt.title"))
        header.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        header.translatesAutoresizingMaskIntoConstraints = false
        // AXHeading by raw value: the typed constant is macOS 26+, this app
        // targets 12. Same approach as MoveUsersViewController.
        header.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading"))

        let message = NSTextField(wrappingLabelWithString: L10n.text("mediaStream.device.prompt.message"))
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        message.translatesAutoresizingMaskIntoConstraints = false

        let table = SourceListTableView()
        table.headerView = nil
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = false
        table.rowSizeStyle = .default
        table.style = .inset
        table.setAccessibilityLabel(L10n.text("mediaStream.device.prompt.sourceLabel"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.onToggleSelectedRow = { [weak self] in self?.toggleSelectedRow() }
        tableView = table

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        // Off by default on purpose: the source is usually audible locally
        // already, and hearing it back a second time reads as an echo.
        monitorCheckbox = NSButton(checkboxWithTitle: L10n.text("mediaStream.device.prompt.monitor"),
                                   target: nil, action: nil)
        monitorCheckbox.state = .off
        monitorCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let optionsStack = NSStackView(views: [monitorCheckbox])
        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 6
        optionsStack.translatesAutoresizingMaskIntoConstraints = false

        // Mute-while-streaming (process taps only, macOS 14.2+): silence the
        // captured app/VoiceOver on this Mac so only the channel hears it.
        // Deliberately never persisted and off by default — an accidentally
        // muted VoiceOver would be catastrophic for a VoiceOver user.
        if #available(macOS 14.2, *) {
            let checkbox = NSButton(checkboxWithTitle: L10n.text("mediaStream.device.prompt.muteSource"),
                                    target: nil, action: nil)
            checkbox.state = .off
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            muteSourceCheckbox = checkbox
            optionsStack.addArrangedSubview(checkbox)
        }

        var browse: NSButton?
        if allowsApplicationBrowsing {
            // Browse for ANY installed app, running or not: the tap backend
            // waits for it and attaches when it plays audio.
            let button = NSButton(title: L10n.text("mediaStream.device.source.chooseApplication"),
                                  target: self, action: #selector(browseForApplication))
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            browse = button
            browseButton = button
        }

        let cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        streamButton = NSButton(title: L10n.text("mediaStream.device.prompt.start"),
                                target: self, action: #selector(confirm))
        streamButton.bezelStyle = .rounded
        streamButton.keyEquivalent = "\r"
        streamButton.translatesAutoresizingMaskIntoConstraints = false

        var subviews: [NSView] = [header, message, scrollView, summaryLabel,
                                  optionsStack, cancelButton, streamButton]
        if let browse { subviews.append(browse) }
        subviews.forEach { view.addSubview($0) }

        var constraints: [NSLayoutConstraint] = [
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            message.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 190),

            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            optionsStack.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
            optionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            optionsStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            streamButton.topAnchor.constraint(greaterThanOrEqualTo: optionsStack.bottomAnchor, constant: 14),
            streamButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            streamButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            cancelButton.trailingAnchor.constraint(equalTo: streamButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ]

        if let browse {
            constraints += [
                browse.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
                browse.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
                summaryLabel.topAnchor.constraint(equalTo: browse.bottomAnchor, constant: 10)
            ]
        } else {
            constraints.append(summaryLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10))
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Selection

    @objc private func checkboxToggled(_ sender: NSButton) {
        guard case .source(let spec)? = rows[safe: sender.tag] else { return }
        apply(spec, selected: sender.state == .on)
    }

    private func toggleSelectedRow() {
        let row = tableView.selectedRow
        guard case .source(let spec)? = rows[safe: row] else {
            NSSound.beep()
            return
        }
        apply(spec, selected: !isSelected(spec))
    }

    /// Applies a tick, enforcing the exclusions and saying out loud what the
    /// tick took away — a line unticking itself elsewhere in the list is
    /// invisible to anyone not looking at it.
    private func apply(_ spec: DeviceStreamCaptureSpec, selected: Bool) {
        var clearedMessages: [String] = []

        switch spec {
        case .inputDevice(let device):
            if selected {
                if selectedApplications.isEmpty == false {
                    clearedMessages.append(L10n.text("mediaStream.device.cleared.applications"))
                    selectedApplications.removeAll()
                }
                if systemAudioSelected {
                    clearedMessages.append(L10n.text("mediaStream.device.cleared.systemAudio"))
                    systemAudioSelected = false
                }
                if let previous = selectedDevice, previous != device {
                    clearedMessages.append(L10n.format("mediaStream.device.cleared.device", previous.name))
                }
                selectedDevice = device
            } else if selectedDevice == device {
                selectedDevice = nil
            }

        case .processes(let selection) where selection.capturesEntireSystem:
            if selected {
                if let previous = selectedDevice {
                    clearedMessages.append(L10n.format("mediaStream.device.cleared.device", previous.name))
                    selectedDevice = nil
                }
                if selectedApplications.isEmpty == false {
                    clearedMessages.append(L10n.text("mediaStream.device.cleared.applications"))
                    selectedApplications.removeAll()
                }
            }
            systemAudioSelected = selected

        case .processes:
            if selected {
                if let previous = selectedDevice {
                    clearedMessages.append(L10n.format("mediaStream.device.cleared.device", previous.name))
                    selectedDevice = nil
                }
                if systemAudioSelected {
                    clearedMessages.append(L10n.text("mediaStream.device.cleared.systemAudio"))
                    systemAudioSelected = false
                }
                if selectedApplications.contains(spec) == false {
                    selectedApplications.append(spec)
                }
            } else {
                selectedApplications.removeAll { $0 == spec }
            }
        }

        refreshSelectionUI()
        if clearedMessages.isEmpty == false {
            announce(clearedMessages.joined(separator: " "))
        }
    }

    private func refreshSelectionUI() {
        // Only the ticks change, never the rows: reloading data would move the
        // keyboard selection out from under the user mid-toggle.
        for (index, row) in rows.enumerated() {
            guard case .source(let spec) = row,
                  let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? NSButton
            else { continue }
            cell.state = isSelected(spec) ? .on : .off
        }
        updateSummary()
        updateMuteAvailability()
        streamButton.isEnabled = resolvedSpec != nil
    }

    private func updateSummary() {
        if systemAudioSelected {
            summaryLabel.stringValue = L10n.text("mediaStream.device.source.systemAudio")
        } else if let selectedDevice {
            summaryLabel.stringValue = selectedDevice.name
        } else if selectedApplications.count == 1 {
            summaryLabel.stringValue = selectedApplications[0].displayName
        } else if selectedApplications.isEmpty == false {
            summaryLabel.stringValue = L10n.format("mediaStream.device.summary.applications",
                                                   selectedApplications.count)
        } else {
            summaryLabel.stringValue = L10n.text("mediaStream.device.summary.none")
        }
    }

    /// Restores the last streamed selection, falling back to the default input
    /// device and then to whatever comes first.
    private func selectPreferredSource() {
        if let preselectedToken {
            let tokens = DeviceStreamCaptureSpec.componentTokens(of: preselectedToken)
            let sources = orderedSources
            let restored = tokens.compactMap { token in
                sources.first(where: { $0.persistenceToken == token })
            }
            if restored.isEmpty == false {
                restored.forEach { apply($0, selected: true) }
                selectFirstSelectedRow()
                return
            }
        }
        if let fallbackDeviceUID,
           let device = devices.first(where: { $0.uid == fallbackDeviceUID }) {
            apply(.inputDevice(device), selected: true)
            selectFirstSelectedRow()
            return
        }
        if let first = orderedSources.first {
            apply(first, selected: true)
        }
        selectFirstSelectedRow()
    }

    /// Put the keyboard on what is already ticked, so the list opens where the
    /// user left off rather than on its first line.
    private func selectFirstSelectedRow() {
        let target = rows.firstIndex { row in
            guard case .source(let spec) = row else { return false }
            return isSelected(spec)
        } ?? rows.firstIndex { if case .source = $0 { return true } else { return false } }

        guard let target else { return }
        tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        tableView.scrollRowToVisible(target)
    }

    private func updateMuteAvailability() {
        guard let muteSourceCheckbox else { return }
        // Never offered for all-system audio: muting the tap there would
        // silence the whole Mac, VoiceOver included.
        let isMutableSource = systemAudioSelected == false && selectedApplications.isEmpty == false
        muteSourceCheckbox.isEnabled = isMutableSource
        if isMutableSource == false { muteSourceCheckbox.state = .off }
    }

    /// The single spec the capture backends consume, or nil when nothing is ticked.
    private var resolvedSpec: DeviceStreamCaptureSpec? {
        if systemAudioSelected { return .systemAudio() }
        if let selectedDevice { return .inputDevice(selectedDevice) }
        return DeviceStreamCaptureSpec.merging(selectedApplications)
    }

    private func announce(_ text: String) {
        // .priority must be the NSNumber rawValue, not the enum, or VoiceOver drops it.
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    // MARK: - Actions

    @objc private func browseForApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, bundleID.isEmpty == false else {
            NSSound.beep()
            return
        }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let spec = DeviceStreamCaptureSpec.application(bundleID: bundleID, displayName: name)
        if applicationSources.contains(spec) == false {
            applicationSources.append(spec)
            rebuildRows()
        }
        apply(spec, selected: true)
        selectFirstSelectedRow()
        announce(L10n.format("mediaStream.device.added.application", name))
    }

    @objc private func confirm() {
        guard let spec = resolvedSpec else {
            NSSound.beep()
            return
        }
        dismiss(nil)
        onStream?(spec, monitorCheckbox.state == .on, muteSourceCheckbox?.state == .on)
    }

    @objc private func cancel() {
        dismiss(nil)
    }
}

// MARK: - Table data source & delegate

extension MediaStreamSourceViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group? = rows[safe: row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .group? = rows[safe: row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[safe: row] {
        case .group(let title):
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            return label

        case .source(let spec):
            let checkbox = NSButton(checkboxWithTitle: spec.displayName,
                                    target: self, action: #selector(checkboxToggled(_:)))
            checkbox.tag = row
            checkbox.state = isSelected(spec) ? .on : .off
            return checkbox

        case nil:
            return nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
