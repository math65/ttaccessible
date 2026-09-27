//
//  MediaStreamSourceViewController.swift
//  ttaccessible
//
//  "Stream Audio from This Mac" sheet: a search field, then the list of sources — all audio
//  from this Mac on a line of its own, then Recently used, Devices and Applications as
//  groups that open and close (Recently used starts open) — a Select Application… button
//  beside it, the monitor and mute-source options, and Cancel / Stream.
//
//  The lines are CHECKBOXES and any combination streams together: the applications fuse
//  into one capture (DeviceStreamCaptureSpec.merging), and devices join them through
//  MixingCaptureBackend (DeviceStreamCaptureSpec.combining). The one exclusion is all audio
//  from this Mac, which already contains every application: checking it clears the
//  applications, and checking an application clears it. Every check is announced,
//  clearings included: a line unchecking itself elsewhere in the list is invisible.
//
//  A list rather than the pop-up and Applications submenu it replaces: a submenu popped
//  from inside a sheet is torn down the instant VoiceOver opens it (measured 2026-09-12:
//  opened and closed 19 ms apart, focus thrown back to the dialog), and running the dialog
//  app-modally instead drops every menu item's action (22703b8). A list has no menu, so the
//  dialog stays a sheet.
//

import AppKit
import UniformTypeIdentifiers

/// Space ticks the selected line — or opens and closes a group — the way a checkbox list is
/// expected to behave, and VoiceOver's press does the same on the list itself: until the
/// user interacts with the list, VO-Space lands on the list, not on a line.
final class StreamSourceOutlineView: NSOutlineView {
    var onToggleSelectedRow: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 49, modifiers.isDisjoint(with: [.command, .option, .control, .shift]) {
            onToggleSelectedRow?()
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onToggleSelectedRow, selectedRow >= 0 else { return super.accessibilityPerformPress() }
        onToggleSelectedRow()
        return true
    }
}

/// One line of the list: a group, or a source. A class, because the outline view keeps
/// track of what is expanded by identity.
private final class SourceNode {
    enum Kind {
        case group(StreamSourceCatalog.Group)
        case source(DeviceStreamCaptureSpec)
    }

    let kind: Kind
    var children: [SourceNode] = []

    init(_ kind: Kind) { self.kind = kind }
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
    private let recentTokens: [String]
    private let preselectedToken: String?

    /// Any input devices, plus any number of applications (VoiceOver counts as one) or all
    /// system audio — those two exclude each other, since it already contains them.
    private var selectedDevices: [InputAudioDeviceInfo] = []
    private var selectedApplications: [DeviceStreamCaptureSpec] = []
    private var systemAudioSelected = false

    private var catalog = StreamSourceCatalog(systemAudio: nil, recent: [], devices: [], applications: [])
    private var nodes: [SourceNode] = []
    /// One node per group for the dialog's lifetime, so rebuilding the list after a search
    /// keeps what the outline view knows about it.
    private var groupNodes: [StreamSourceCatalog.Group: SourceNode] = [:]
    /// The groups the user has open, restored when a search is cleared (a search opens every
    /// group with a match, so nothing it finds is hidden).
    private var openGroups: Set<StreamSourceCatalog.Group> = [.recent]
    private var query = ""
    private var isRebuilding = false
    private var matchAnnouncement: DispatchWorkItem?

    private var searchField: NSSearchField!
    private var outlineView: StreamSourceOutlineView!
    private var browseButton: NSButton?
    private var monitorCheckbox: NSButton!
    private var muteSourceCheckbox: NSButton?
    private var cancelButton: NSButton!
    private var streamButton: NSButton!

    /// - Parameters:
    ///   - allowsApplicationBrowsing: browsing for a not-yet-running app needs
    ///     the process-tap backend's wait-and-attach (macOS 14.2+); the
    ///     ScreenCaptureKit tier can only capture apps that are already running.
    ///   - allowsSystemAudio: capturing everything the Mac plays needs one of
    ///     the two process backends, so macOS 13 or later.
    ///   - recentTokens: the sources streamed lately, newest first (persistence tokens).
    init(devices: [InputAudioDeviceInfo],
         applicationSources: [DeviceStreamCaptureSpec],
         voiceOverAvailable: Bool,
         allowsApplicationBrowsing: Bool,
         allowsSystemAudio: Bool,
         recentTokens: [String],
         preselectedToken: String?) {
        self.devices = devices
        self.applicationSources = applicationSources
        self.voiceOverAvailable = voiceOverAvailable
        self.allowsApplicationBrowsing = allowsApplicationBrowsing
        self.allowsSystemAudio = allowsSystemAudio
        self.recentTokens = recentTokens
        self.preselectedToken = preselectedToken
        super.init(nibName: nil, bundle: nil)
        catalog = makeCatalog()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        selectPreferredSource()
        openGroups = catalog.groupsRevealing(orderedSources.filter(isSelected), open: openGroups)
        rebuildList()
        // Stream starts disabled when nothing was restored.
        refreshSelectionUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.autorecalculatesKeyViewLoop = false
        linkKeyViewLoop()
        view.window?.initialFirstResponder = outlineView
        focusList()
        // Return streams from anywhere in the sheet, the list included.
        view.window?.defaultButtonCell = streamButton.cell as? NSButtonCell
    }

    // MARK: - Sources

    private func makeCatalog() -> StreamSourceCatalog {
        let systemAudio: DeviceStreamCaptureSpec? = allowsSystemAudio ? .systemAudio() : nil
        let deviceSpecs = devices.map { DeviceStreamCaptureSpec.inputDevice($0) }
        let applicationSpecs = (voiceOverAvailable ? [DeviceStreamCaptureSpec.voiceOver()] : []) + applicationSources
        let browsing = allowsApplicationBrowsing
        let recent = StreamSourceCatalog.resolveRecent(
            tokens: recentTokens,
            available: [systemAudio].compactMap { $0 } + deviceSpecs + applicationSpecs,
            resolveMissing: { token in
                // An application streamed before but not running now can still be offered
                // where the tap backend waits for it to play (the same reach as
                // Select Application…). Token format: see ProcessSelection.persistenceToken.
                let prefix = "app:"
                guard browsing, token.hasPrefix(prefix) else { return nil }
                let bundleID = String(token.dropFirst(prefix.count))
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
                return .application(bundleID: bundleID, displayName: Self.applicationName(at: url))
            })
        return StreamSourceCatalog(systemAudio: systemAudio, recent: recent,
                                   devices: deviceSpecs, applications: applicationSpecs)
    }

    /// Every selectable source, flat — used for preselection and for restoring a remembered
    /// choice.
    private var orderedSources: [DeviceStreamCaptureSpec] {
        var specs = [catalog.systemAudio].compactMap { $0 } + catalog.devices + catalog.applications
        specs.append(contentsOf: catalog.recent.filter { specs.contains($0) == false })
        return specs
    }

    private func isSelected(_ spec: DeviceStreamCaptureSpec) -> Bool {
        switch spec {
        case .inputDevice(let device):
            return selectedDevices.contains(device)
        case .processes(let selection):
            if selection.capturesEntireSystem { return systemAudioSelected }
            return selectedApplications.contains(spec)
        case .combined:
            return false
        }
    }

    private static func applicationName(at url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Setup

    private func setupLayout() {
        let header = NSTextField(wrappingLabelWithString: L10n.text("mediaStream.device.prompt.title"))
        header.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        header.translatesAutoresizingMaskIntoConstraints = false
        // AXHeading by raw value: the typed constant is macOS 26+, this app
        // targets 12. Same approach as MoveUsersViewController. With that role the
        // field's text is only its AXValue, and VoiceOver announced an empty
        // heading, so the title is the label too.
        header.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading"))
        header.setAccessibilityLabel(header.stringValue)

        let message = NSTextField(wrappingLabelWithString: L10n.text("mediaStream.device.prompt.message"))
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        message.translatesAutoresizingMaskIntoConstraints = false

        searchField = NSSearchField()
        searchField.placeholderString = L10n.text("mediaStream.device.search.placeholder")
        searchField.setAccessibilityLabel(L10n.text("mediaStream.device.search.placeholder"))
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        outlineView = StreamSourceOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityLabel(L10n.text("mediaStream.device.prompt.sourceLabel"))
        outlineView.onToggleSelectedRow = { [weak self] in self?.toggleSelectedRow() }

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        if allowsApplicationBrowsing {
            // Browse for ANY installed app, running or not: the tap backend waits for it
            // and attaches when it plays audio.
            let button = NSButton(title: L10n.text("mediaStream.device.source.chooseApplication"),
                                  target: self, action: #selector(browseForApplication))
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            browseButton = button
        }

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

        cancelButton = NSButton(title: L10n.text("common.cancel"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        streamButton = NSButton(title: L10n.text("mediaStream.device.prompt.start"),
                                target: self, action: #selector(confirm))
        streamButton.bezelStyle = .rounded
        streamButton.keyEquivalent = "\r"
        streamButton.translatesAutoresizingMaskIntoConstraints = false

        // Left to right, as VoiceOver reads it: the search, the list, then the button that
        // adds to the list.
        ([header, message, searchField, scrollView, optionsStack, cancelButton, streamButton] + [browseButton].compactMap { $0 })
            .forEach { view.addSubview($0) }

        var constraints: [NSLayoutConstraint] = [
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            message.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            searchField.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchField.widthAnchor.constraint(equalToConstant: 170),

            scrollView.topAnchor.constraint(equalTo: searchField.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 10),
            scrollView.heightAnchor.constraint(equalToConstant: 220),

            optionsStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            optionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            optionsStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            streamButton.topAnchor.constraint(greaterThanOrEqualTo: optionsStack.bottomAnchor, constant: 14),
            streamButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            streamButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            cancelButton.trailingAnchor.constraint(equalTo: streamButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ]
        if let browseButton {
            constraints += [
                browseButton.topAnchor.constraint(equalTo: scrollView.topAnchor),
                browseButton.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 10),
                browseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            ]
        } else {
            constraints.append(scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14))
        }
        NSLayoutConstraint.activate(constraints)
    }

    /// Tab walks the sheet in reading order: search, list, Select Application…, the options,
    /// Cancel, Stream.
    private func linkKeyViewLoop() {
        var chain: [NSView] = [searchField, outlineView]
        if let browseButton { chain.append(browseButton) }
        chain.append(monitorCheckbox)
        if let muteSourceCheckbox { chain.append(muteSourceCheckbox) }
        chain.append(contentsOf: [cancelButton, streamButton])
        for (index, view) in chain.enumerated() {
            view.nextKeyView = chain[(index + 1) % chain.count]
        }
    }

    // MARK: - List

    private func groupNode(_ group: StreamSourceCatalog.Group) -> SourceNode {
        if let node = groupNodes[group] { return node }
        let node = SourceNode(.group(group))
        groupNodes[group] = node
        return node
    }

    private func title(for group: StreamSourceCatalog.Group) -> String {
        switch group {
        case .recent: return L10n.text("mediaStream.device.group.recent")
        case .devices: return L10n.text("mediaStream.device.group.devices")
        case .applications: return L10n.text("mediaStream.device.group.applications")
        }
    }

    /// Rebuilds the lines from the catalog and the search. A search opens every group with a
    /// match; an empty search puts back the groups the user had open.
    private func rebuildList() {
        let filtered = catalog.filtered(by: query)
        var top: [SourceNode] = []
        if let systemAudio = filtered.systemAudio {
            top.append(SourceNode(.source(systemAudio)))
        }
        for section in filtered.sections {
            let node = groupNode(section.group)
            node.children = section.sources.map { SourceNode(.source($0)) }
            top.append(node)
        }
        nodes = top

        isRebuilding = true
        outlineView.reloadData()
        let searching = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        for node in top {
            guard case .group(let group) = node.kind else { continue }
            if searching || openGroups.contains(group) {
                outlineView.expandItem(node)
            } else {
                outlineView.collapseItem(node)
            }
        }
        isRebuilding = false
    }

    /// Redraws every visible tick from the selection, in place: reloading the list would make
    /// VoiceOver read the line again on top of the announcement.
    private func refreshTicks() {
        for row in 0 ..< outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SourceNode,
                  case .source(let spec) = node.kind,
                  let box = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSButton
            else { continue }
            box.state = isSelected(spec) ? .on : .off
        }
    }

    /// Puts the focus in the list, on the first ticked line — the current choice — or the
    /// first source when nothing is ticked. From the search, `preferChecked` is false: Down
    /// Arrow goes to the first match, checked or not.
    private func focusList(preferChecked: Bool = true) {
        view.window?.makeFirstResponder(outlineView)
        guard outlineView.selectedRow < 0 else { return }
        var firstSource: Int?
        for row in 0 ..< outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SourceNode, case .source(let spec) = node.kind
            else { continue }
            if firstSource == nil {
                firstSource = row
                if preferChecked == false { break }
            }
            if isSelected(spec) { firstSource = row; break }
        }
        guard let row = firstSource ?? (outlineView.numberOfRows > 0 ? 0 : nil) else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    private func toggleSelectedRow() {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SourceNode else { return }
        switch node.kind {
        case .group:
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        case .source(let spec):
            toggle(spec)
        }
    }

    @objc private func checkboxClicked(_ sender: NSButton) {
        let row = outlineView.row(for: sender)
        guard row >= 0, let node = outlineView.item(atRow: row) as? SourceNode,
              case .source(let spec) = node.kind else { return }
        // The click has already flipped this box; the selection decides, and refreshTicks
        // redraws every box from it.
        toggle(spec)
    }

    private func toggle(_ spec: DeviceStreamCaptureSpec) {
        let selected = !isSelected(spec)
        let cleared = apply(spec, selected: selected)
        let stateText = L10n.format(selected ? "mediaStream.device.source.checked"
                                             : "mediaStream.device.source.unchecked",
                                    spec.displayName)
        announce(([stateText] + cleared).joined(separator: " "))
    }

    // MARK: - Search

    @objc private func searchChanged(_ sender: NSSearchField) {
        query = sender.stringValue
        rebuildList()
        refreshTicks()
        scheduleMatchAnnouncement()
    }

    /// Says how many sources the search leaves, once typing pauses — the list changing
    /// under the search field is otherwise silent.
    private func scheduleMatchAnnouncement() {
        matchAnnouncement?.cancel()
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let filtered = self.catalog.filtered(by: self.query)
            var distinct: [DeviceStreamCaptureSpec] = []
            for spec in [filtered.systemAudio].compactMap({ $0 }) + filtered.sections.flatMap(\.sources)
            where distinct.contains(spec) == false {
                distinct.append(spec)
            }
            switch distinct.count {
            case 0: self.announce(L10n.text("mediaStream.device.search.none"))
            case 1: self.announce(L10n.text("mediaStream.device.search.one"))
            default: self.announce(L10n.format("mediaStream.device.search.results", distinct.count))
            }
        }
        matchAnnouncement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Selection

    /// Applies a tick, enforcing the exclusions, and returns what the tick took
    /// away for the caller to say out loud — a line unticking itself elsewhere in
    /// the list is invisible to anyone not looking at it.
    @discardableResult
    private func apply(_ spec: DeviceStreamCaptureSpec, selected: Bool) -> [String] {
        var clearedMessages: [String] = []

        switch spec {
        case .inputDevice(let device):
            // Devices combine with everything, each other included.
            if selected {
                if selectedDevices.contains(device) == false { selectedDevices.append(device) }
            } else {
                selectedDevices.removeAll { $0 == device }
            }

        case .processes(let selection) where selection.capturesEntireSystem:
            // All audio from this Mac already contains every application.
            if selected, selectedApplications.isEmpty == false {
                clearedMessages.append(L10n.text("mediaStream.device.cleared.applications"))
                selectedApplications.removeAll()
            }
            systemAudioSelected = selected

        case .processes:
            if selected {
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

        case .combined:
            // Never a line in the list: a saved combination is restored from its parts.
            break
        }

        refreshSelectionUI()
        return clearedMessages
    }

    private func refreshSelectionUI() {
        guard isViewLoaded, outlineView != nil else { return }
        refreshTicks()
        updateMuteAvailability()
        streamButton.isEnabled = resolvedSpec != nil
    }

    /// Restores the last streamed selection — and nothing else. With no history (or none of
    /// it plugged in or running) nothing is checked: the sheet used to check the default
    /// microphone, which then streamed unless the user thought to uncheck it.
    private func selectPreferredSource() {
        guard let preselectedToken else { return }
        let sources = orderedSources
        DeviceStreamCaptureSpec.componentTokens(of: preselectedToken)
            .compactMap { token in sources.first(where: { $0.persistenceToken == token }) }
            .forEach { apply($0, selected: true) }
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
        DeviceStreamCaptureSpec.combining(
            selectedDevices.map { DeviceStreamCaptureSpec.inputDevice($0) }
                + (systemAudioSelected ? [.systemAudio()] : selectedApplications)
        )
    }

    /// Every tick is announced explicitly, and so is what a search leaves: neither is
    /// otherwise spoken while the focus stays where it is.
    private func announce(_ text: String) {
        // .priority must be the NSNumber rawValue, not the enum, or VoiceOver drops it.
        NSAccessibility.post(
            element: outlineView as Any,
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
        let name = Self.applicationName(at: url)
        let spec = DeviceStreamCaptureSpec.application(bundleID: bundleID, displayName: name)
        // Kept in the list so it stays visible and tickable, in an open Applications group.
        if applicationSources.contains(spec) == false {
            applicationSources.append(spec)
        }
        catalog = makeCatalog()
        openGroups.insert(.applications)
        rebuildList()
        let cleared = apply(spec, selected: true)
        // One announcement: the addition, then anything the exclusions unticked.
        announce(([L10n.format("mediaStream.device.added.application", name)] + cleared)
            .joined(separator: " "))
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

// MARK: - Outline

extension MediaStreamSourceViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SourceNode)?.children.count ?? nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SourceNode)?.children[index] ?? nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SourceNode, case .group = node.kind else { return false }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SourceNode else { return nil }
        switch node.kind {
        case .group(let group):
            let label = NSTextField(labelWithString: title(for: group))
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return label
        case .source(let spec):
            let box = NSButton(checkboxWithTitle: spec.displayName,
                               target: self, action: #selector(checkboxClicked(_:)))
            box.state = isSelected(spec) ? .on : .off
            return box
        }
    }

    // What the user opens and closes is remembered — but not what a search opens for them,
    // nor what rebuilding the list does on its own.
    func outlineViewItemDidExpand(_ notification: Notification) {
        rememberGroup(notification, open: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        rememberGroup(notification, open: false)
    }

    private func rememberGroup(_ notification: Notification, open: Bool) {
        guard isRebuilding == false,
              query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let node = notification.userInfo?["NSObject"] as? SourceNode,
              case .group(let group) = node.kind else { return }
        if open { openGroups.insert(group) } else { openGroups.remove(group) }
    }
}

// MARK: - Search field

extension MediaStreamSourceViewController: NSSearchFieldDelegate {
    /// Down arrow from the search goes to the list, onto the first match.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField, commandSelector == #selector(NSResponder.moveDown(_:)) else { return false }
        outlineView.deselectAll(nil)
        focusList(preferChecked: false)
        return true
    }
}
