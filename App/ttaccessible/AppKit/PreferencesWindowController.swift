//
//  PreferencesWindowController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    enum Pane: CaseIterable {
        case connection
        case audio
        case notifications
        case `import`
        case accessibility

        var title: String {
            switch self {
            case .connection:
                return L10n.text("preferences.connection.title")
            case .audio:
                return L10n.text("preferences.audio.title")
            case .notifications:
                return L10n.text("preferences.notifications.title")
            case .import:
                return L10n.text("preferences.import.title")
            case .accessibility:
                return L10n.text("preferences.accessibility.title")
            }
        }

        var iconName: String {
            switch self {
            case .connection:
                return "network"
            case .audio:
                return "speaker.wave.2"
            case .notifications:
                return "bell"
            case .import:
                return "square.and.arrow.down"
            case .accessibility:
                return "accessibility"
            }
        }
    }

    private let preferencesStore: AppPreferencesStore
    private let connectionController: TeamTalkConnectionController
    private let advancedMicrophoneSettingsStore: AdvancedMicrophoneSettingsStore
    private var hasWarmedUpDependencies = false

    init(
        preferencesStore: AppPreferencesStore,
        connectionController: TeamTalkConnectionController,
        advancedMicrophoneSettingsStore: AdvancedMicrophoneSettingsStore
    ) {
        self.preferencesStore = preferencesStore
        self.connectionController = connectionController
        self.advancedMicrophoneSettingsStore = advancedMicrophoneSettingsStore

        let contentViewController = PreferencesContainerViewController(
            preferencesStore: preferencesStore,
            connectionController: connectionController,
            advancedMicrophoneSettingsStore: advancedMicrophoneSettingsStore
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("preferences.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = contentViewController

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showPreferences() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if hasWarmedUpDependencies == false,
           let container = window?.contentViewController as? PreferencesContainerViewController {
            hasWarmedUpDependencies = true
            container.warmupExpensiveDependencies()
        }
    }

    func preloadPreferencesIfNeeded() {
        _ = window?.contentViewController?.view
        if hasWarmedUpDependencies == false,
           let container = window?.contentViewController as? PreferencesContainerViewController {
            hasWarmedUpDependencies = true
            container.warmupExpensiveDependencies()
        }
    }
}

@MainActor
private final class PreferencesContainerViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let connectionController: TeamTalkConnectionController
    private let advancedMicrophoneSettingsStore: AdvancedMicrophoneSettingsStore
    private let connectionPreferencesStore: ConnectionPreferencesStore
    private let audioPreferencesStore: AudioPreferencesStore
    private let notificationsPreferencesStore: NotificationsPreferencesStore
    private let accessibilityPreferencesStore: AccessibilityPreferencesStore
    private let sidebarViewController = PreferencesSidebarViewController()
    private let contentHostViewController = PreferencesContentHostViewController()
    private let sidebarWidth: CGFloat = 200
    private var selectedPane: PreferencesWindowController.Pane = .connection
    private var paneViewControllers = [PreferencesWindowController.Pane: NSViewController]()

    init(
        preferencesStore: AppPreferencesStore,
        connectionController: TeamTalkConnectionController,
        advancedMicrophoneSettingsStore: AdvancedMicrophoneSettingsStore
    ) {
        self.preferencesStore = preferencesStore
        self.connectionController = connectionController
        self.advancedMicrophoneSettingsStore = advancedMicrophoneSettingsStore
        self.connectionPreferencesStore = preferencesStore.makeConnectionStore(
            onSubscriptionPreferencesChanged: { [weak connectionController] in
                connectionController?.applyDefaultSubscriptionPreferences()
            }
        )
        self.audioPreferencesStore = preferencesStore.makeAudioStore(
            connectionController: connectionController,
            advancedSettingsStore: advancedMicrophoneSettingsStore
        )
        self.notificationsPreferencesStore = preferencesStore.makeNotificationsStore()
        self.accessibilityPreferencesStore = preferencesStore.makeAccessibilityStore()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()

        sidebarViewController.onSelectionChanged = { [weak self] pane in
            self?.selectPane(pane, updateSidebarSelection: false)
        }
        selectPane(.connection)
    }

    func warmupExpensiveDependencies() {
        audioPreferencesStore.warmup()
        notificationsPreferencesStore.prepareIfNeeded()
    }

    private func selectPane(_ pane: PreferencesWindowController.Pane, updateSidebarSelection: Bool = true) {
        if selectedPane == .audio, pane != .audio {
            audioPreferencesStore.suspendWhenHidden()
        }
        selectedPane = pane
        view.window?.title = L10n.text("preferences.window.title")
        if updateSidebarSelection {
            sidebarViewController.selectPane(pane)
        }

        // Create the pane view controller on first access.
        if paneViewControllers[pane] == nil {
            paneViewControllers[pane] = makePaneViewController(for: pane)
            contentHostViewController.addPaneViewController(paneViewControllers[pane]!, for: pane)
        }
        contentHostViewController.showPane(pane)
        switch pane {
        case .audio:
            audioPreferencesStore.prepareIfNeeded()
        case .notifications:
            notificationsPreferencesStore.prepareIfNeeded()
        default:
            break
        }
    }

    private func makePaneViewController(for pane: PreferencesWindowController.Pane) -> NSViewController {
        switch pane {
        case .connection:
            return NSHostingController(
                rootView: PreferencesConnectionView(store: connectionPreferencesStore)
            )
        case .audio:
            return NSHostingController(
                rootView: PreferencesAudioView(store: audioPreferencesStore)
            )
        case .notifications:
            return NSHostingController(rootView: PreferencesNotificationsView(store: notificationsPreferencesStore))
        case .import:
            return NSHostingController(rootView: PreferencesImportView(store: preferencesStore))
        case .accessibility:
            return NSHostingController(rootView: PreferencesAccessibilityView(store: accessibilityPreferencesStore))
        }
    }

    private func configureLayout() {
        view = NSView()

        let sidebarView = sidebarViewController.view
        let contentView = contentHostViewController.view
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addChild(sidebarViewController)
        addChild(contentHostViewController)

        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(sidebarView)
        view.addSubview(separator)
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: sidebarWidth),

            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

@MainActor
private final class PreferencesContentHostViewController: NSViewController {
    private var contentViewControllers: [PreferencesWindowController.Pane: NSViewController] = [:]

    override func loadView() {
        view = NSView()
    }

    func addPaneViewController(_ viewController: NSViewController, for pane: PreferencesWindowController.Pane) {
        guard contentViewControllers[pane] == nil else { return }
        contentViewControllers[pane] = viewController
        addChild(viewController)
        let contentView = viewController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.isHidden = true
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func showPane(_ pane: PreferencesWindowController.Pane) {
        for (key, viewController) in contentViewControllers {
            viewController.view.isHidden = key != pane
        }
    }
}

@MainActor
private final class PreferencesSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectionChanged: ((PreferencesWindowController.Pane) -> Void)?

    private let panes = PreferencesWindowController.Pane.allCases
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private var isProgrammaticSelectionChange = false

    override func loadView() {
        view = NSVisualEffectView()
        configureUI()
    }

    func selectPane(_ pane: PreferencesWindowController.Pane) {
        guard let row = panes.firstIndex(of: pane) else {
            return
        }
        isProgrammaticSelectionChange = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isProgrammaticSelectionChange = false
    }

    private func configureUI() {
        guard let effectView = view as? NSVisualEffectView else {
            return
        }
        effectView.material = .sidebar
        effectView.state = .active

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        if #available(macOS 11.0, *) {
            tableView.style = .sourceList
        }
        tableView.rowSizeStyle = .default
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.setAccessibilityLabel(L10n.text("preferences.sidebar.accessibilityLabel"))

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        panes.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard isProgrammaticSelectionChange == false else {
            return
        }
        let row = tableView.selectedRow
        guard panes.indices.contains(row) else {
            return
        }
        onSelectionChanged?(panes[row])
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard panes.indices.contains(row) else {
            return nil
        }

        let pane = panes[row]
        let identifier = PreferencesSidebarCellView.reuseIdentifier
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? PreferencesSidebarCellView)
            ?? PreferencesSidebarCellView()
        cell.configure(with: pane)
        cell.setAccessibilityLabel(pane.title)
        return cell
    }
}

private final class PreferencesSidebarCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("PreferencePaneCell")

    private let paneImageView = NSImageView(frame: .zero)
    private let paneTextField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier

        paneImageView.translatesAutoresizingMaskIntoConstraints = false
        paneImageView.imageScaling = .scaleProportionallyDown

        paneTextField.translatesAutoresizingMaskIntoConstraints = false
        paneTextField.font = .systemFont(ofSize: NSFont.systemFontSize)

        addSubview(paneImageView)
        addSubview(paneTextField)
        imageView = paneImageView
        textField = paneTextField

        NSLayoutConstraint.activate([
            paneImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            paneImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            paneImageView.widthAnchor.constraint(equalToConstant: 18),
            paneImageView.heightAnchor.constraint(equalToConstant: 18),
            paneTextField.leadingAnchor.constraint(equalTo: paneImageView.trailingAnchor, constant: 10),
            paneTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            paneTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(with pane: PreferencesWindowController.Pane) {
        paneImageView.image = NSImage(systemSymbolName: pane.iconName, accessibilityDescription: nil)
        paneTextField.stringValue = pane.title
    }
}
