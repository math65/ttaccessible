//
//  AppDelegate.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit
import UserNotifications
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct PendingUnsavedServerConfiguration {
        var record: SavedServerRecord
        var password: String
        var initialChannelPassword: String
    }

    private struct ParsedTTLink {
        var host: String
        var tcpPort: Int
        var udpPort: Int
        var encrypted: Bool
        var username: String
        var password: String
        var channel: String
        var channelPassword: String
    }

    private enum TeamTalkImportSource {
        case configurationFile
        case ttFile
        case ttLink
    }

    private enum ServerExportDestination {
        case ttFile
        case ttLink
    }

    private struct ServerExportChannelContext {
        var name: String
        var path: String
        var password: String
    }

    private struct ServerExportContext {
        var record: SavedServerRecord
        var password: String
        var channelPassword: String
        var currentChannel: ServerExportChannelContext?
    }

    private let store = SavedServerStore()
    private let passwordStore = ServerPasswordStore()
    private let preferencesStore = AppPreferencesStore()
    private let ttFileService = TTFileService()
    private let voiceOverAppleScriptAnnouncementService = VoiceOverAppleScriptAnnouncementService()
    private let macOSTextToSpeechAnnouncementService = MacOSTextToSpeechAnnouncementService()
    private let menuState = SavedServersMenuState.shared
    private let audioDeviceChangeMonitor = AudioDeviceChangeMonitor()
    private lazy var connectionController = TeamTalkConnectionController(preferencesStore: preferencesStore)
    private lazy var advancedMicrophoneSettingsStore = AdvancedMicrophoneSettingsStore(
        preferencesStore: preferencesStore,
        connectionController: connectionController
    )
    private var savedServersWindowController: SavedServersWindowController?
    private var privateMessagesWindowController: PrivateMessagesWindowController?
    private var channelFilesWindowController: ChannelFilesWindowController?
    private var statsWindowController: NSWindowController?
    private weak var statsViewController: StatsViewController?
    private var preferencesWindowController: PreferencesWindowController?
    private var userAccountsWindowController: NSWindowController?
    private var bannedUsersWindowController: NSWindowController?
    private var userInfoWindowController: UserInfoWindowController?
    private weak var savedServersViewController: SavedServersViewController?
    private weak var connectedServerViewController: ConnectedServerViewController?
    private weak var privateMessagesViewController: PrivateMessagesViewController?
    private weak var channelFilesViewController: ChannelFilesViewController?
    private weak var userAccountsViewController: UserAccountsViewController?
    private weak var bannedUsersViewController: BannedUsersViewController?
    private weak var userInfoViewController: UserInfoViewController?
    private var hasFinishedLaunching = false
    private var pendingTTFileURLs: [URL] = []
    private var userInfoUserID: Int32?
    private var lastObservedSessionHistory: [SessionHistoryEntry] = []
    private var recordingAccessedFolder: URL?
    private var activeRecordingMode: Int = 0
    private var lastObservedChannelID: Int32 = 0
    private var pendingUnsavedServerConfiguration: PendingUnsavedServerConfiguration?

    private var deviceChangeObserver: Any?
    private var globalDeviceChangeWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioLogger.clear()
        let sdkVersion = String(cString: TT_GetVersion())
        AudioLogger.log("App launched — TeamTalk SDK %@", sdkVersion)
        connectionController.delegate = self
        connectionController.audioDeviceChangeMonitor = audioDeviceChangeMonitor
        UNUserNotificationCenter.current().delegate = self
        audioDeviceChangeMonitor.startListening()

        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: AudioDeviceChangeMonitor.audioDevicesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.globalDeviceChangeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.connectionController.restartSoundSystem { _ in }
            }
            self?.globalDeviceChangeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: workItem)
        }
        requestNotificationPermission()
        showSavedServersWindow()
        DispatchQueue.main.async { [weak self] in
            self?.preloadPreferencesWindow()
        }
        hasFinishedLaunching = true
        handleLaunchTTFilesIfNeeded()
        processPendingTTFileURLsIfPossible()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func announceWithVoiceOver(_ message: String) {
        let element: Any = NSApp.accessibilityWindow() ?? savedServersWindowController?.window as Any
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func handleBackgroundIncomingTextMessage(_ event: IncomingTextMessageEvent) {
        guard NSApp.isActive == false else {
            return
        }

        let type: BackgroundMessageAnnouncementType
        switch event.kind {
        case .privateMessage:
            type = .privateMessages
        case .channelMessage:
            type = .channelMessages
        case .broadcastMessage:
            type = .broadcastMessages
        }

        let message = L10n.format(type.nativeAnnouncementLocalizationKey, event.senderName, event.content)
        let mode = preferencesStore.preferences.backgroundAnnouncementMode(for: type)
        switch mode {
        case .nativeVoiceOver, .systemNotification:
            // Native VoiceOver announcements remain foreground-only.
            sendNotification(
                title: L10n.format(type.systemNotificationTitleLocalizationKey, event.senderName),
                body: event.content,
                identifier: "bgmsg-\(type.id)-\(Date().timeIntervalSince1970)"
            )
        case .macOSTextToSpeech:
            macOSTextToSpeechAnnouncementService.announce(
                message,
                voiceIdentifier: preferencesStore.preferences.macOSTTSVoiceIdentifier,
                speechRate: preferencesStore.preferences.macOSTTSSpeechRate,
                volume: preferencesStore.preferences.macOSTTSVolume
            )
        case .voiceOverAppleScript:
            voiceOverAppleScriptAnnouncementService.announce(message)
        }
    }

    private func handleBackgroundSessionHistory(previousEntries: [SessionHistoryEntry], session: ConnectedServerSession) {
        guard NSApp.isActive == false else {
            return
        }

        let disabledKinds = preferencesStore.preferences.voiceOverAnnouncements.disabledSessionHistoryKinds

        guard let latestEntry = SessionHistoryAnnouncementHelper.latestAppendedEntry(
            previous: previousEntries,
            current: session.sessionHistory,
            filter: { entry in
                SessionHistoryAnnouncementHelper.shouldAnnounceBackgroundHistoryEntry(entry, disabledKinds: disabledKinds)
            }
        ) else {
            return
        }

        let type: BackgroundMessageAnnouncementType = .sessionHistory
        let mode = preferencesStore.preferences.backgroundAnnouncementMode(for: type)
        switch mode {
        case .nativeVoiceOver, .systemNotification:
            sendNotification(
                title: L10n.text(type.systemNotificationTitleLocalizationKey),
                body: latestEntry.message,
                identifier: "bg-history-\(Date().timeIntervalSince1970)"
            )
        case .macOSTextToSpeech:
            macOSTextToSpeechAnnouncementService.announce(
                latestEntry.message,
                voiceIdentifier: preferencesStore.preferences.macOSTTSVoiceIdentifier,
                speechRate: preferencesStore.preferences.macOSTTSSpeechRate,
                volume: preferencesStore.preferences.macOSTTSVolume
            )
        case .voiceOverAppleScript:
            voiceOverAppleScriptAnnouncementService.announce(latestEntry.message)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        connectionController.disconnectSynchronously()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard confirmSavePendingUnsavedServerIfNeeded() else {
            return .terminateCancel
        }

        connectionController.disconnectSynchronously()
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let ttLinks = urls.filter { $0.scheme?.lowercased() == "tt" }
        let ttFiles = urls.filter { $0.scheme?.lowercased() != "tt" }

        if let link = ttLinks.first {
            handleTTLink(link)
        }
        if ttFiles.isEmpty == false {
            enqueueTTFileURLs(ttFiles, source: "openURLs")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag == false {
            restoreMainWindow()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if NSApp.windows.contains(where: { $0.isVisible }) == false {
            restoreMainWindow()
        }
    }

    private func showSavedServersWindow() {
        let shouldActivateWindow = savedServersWindowController == nil
            || savedServersWindowController?.window?.contentViewController is SavedServersViewController == false
            || savedServersWindowController?.window?.isVisible == false

        if savedServersWindowController == nil {
            let windowController = SavedServersWindowController(contentViewController: makeSavedServersViewController())
            windowController.window?.delegate = self
            savedServersWindowController = windowController
        }

        if let window = savedServersWindowController?.window,
           window.contentViewController is SavedServersViewController == false {
            let viewController = makeSavedServersViewController()
            window.contentViewController = viewController
            window.title = L10n.text("savedServers.window.title")
        }

        menuState.setMode(.savedServers)
        menuState.setConnectedState(hasSelectedChannel: false, isInChannel: false)
        menuState.resetConnectedTransientState()
        closePrivateMessagesWindow()
        closeChannelFilesWindow()
        if shouldActivateWindow {
            savedServersWindowController?.showWindow(nil)
            savedServersWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeSavedServersViewController() -> SavedServersViewController {
        let viewController = SavedServersViewController(
            store: store,
            passwordStore: passwordStore,
            preferencesStore: preferencesStore,
            menuState: menuState,
            connectionController: connectionController
        )
        savedServersViewController = viewController
        connectedServerViewController = nil
        return viewController
    }

    private func showConnectedServerWindow(session: ConnectedServerSession) {
        let shouldActivateWindow = savedServersWindowController == nil
            || savedServersWindowController?.window?.contentViewController is ConnectedServerViewController == false
            || savedServersWindowController?.window?.isVisible == false

        if savedServersWindowController == nil {
            let windowController = SavedServersWindowController(contentViewController: NSViewController())
            savedServersWindowController = windowController
        }

        let viewController: ConnectedServerViewController
        if let existing = connectedServerViewController {
            existing.update(session: session)
            viewController = existing
        } else {
            viewController = ConnectedServerViewController(
                session: session,
                preferencesStore: preferencesStore,
                connectionController: connectionController,
                menuState: menuState,
                appDelegate: self
            )
            connectedServerViewController = viewController
            savedServersViewController = nil
        }

        savedServersWindowController?.window?.contentViewController = viewController
        savedServersWindowController?.window?.title = L10n.format("connectedServer.window.title", session.displayName)
        menuState.setMode(.connectedServer)
        menuState.setHasSelection(false)
        if shouldActivateWindow {
            savedServersWindowController?.showWindow(nil)
            savedServersWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func restoreMainWindow() {
        if let session = connectionController.sessionSnapshot {
            showConnectedServerWindow(session: session)
        } else {
            showSavedServersWindow()
        }

        savedServersWindowController?.showWindow(nil)
        savedServersWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func showPrivateMessagesWindow(session: ConnectedServerSession, select userID: Int32?, activate: Bool) {
        let shouldShowWindow = privateMessagesWindowController == nil
            || privateMessagesWindowController?.window?.isVisible == false
        let shouldSelectConversation = privateMessagesViewController == nil || userID != nil

        let viewController: PrivateMessagesViewController
        if let existing = privateMessagesViewController {
            existing.preferencesStore = preferencesStore
            existing.update(session: session, markRead: activate)
            viewController = existing
        } else {
            viewController = PrivateMessagesViewController(
                session: session,
                connectionController: connectionController,
                preferencesStore: preferencesStore
            )
            viewController.preferencesStore = preferencesStore
            privateMessagesViewController = viewController
        }

        if privateMessagesWindowController == nil {
            let wc = PrivateMessagesWindowController(contentViewController: viewController)
            wc.onUserClose = { [weak self] in
                self?.connectionController.updatePrivateMessagesConsultation(isWindowVisible: false, selectedUserID: nil)
                self?.privateMessagesWindowController = nil
                self?.privateMessagesViewController = nil
            }
            privateMessagesWindowController = wc
        } else {
            privateMessagesWindowController?.window?.contentViewController = viewController
        }

        privateMessagesWindowController?.window?.title = L10n.text("privateMessages.window.title")
        if shouldSelectConversation {
            viewController.selectConversation(
                userID: userID,
                markRead: activate,
                focusInput: activate && userID != nil
            )
        }

        guard let window = privateMessagesWindowController?.window else {
            return
        }

        if shouldShowWindow {
            _ = window.contentViewController?.view
            window.orderFront(nil)
        }

        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closePrivateMessagesWindow() {
        connectionController.updatePrivateMessagesConsultation(isWindowVisible: false, selectedUserID: nil)
        privateMessagesWindowController?.close()
        privateMessagesWindowController = nil
        privateMessagesViewController = nil
    }

    func openChannelFiles() {
        guard menuState.mode == .connectedServer,
              let session = connectionController.sessionSnapshot,
              session.currentChannelID > 0 else { return }
        showChannelFilesWindow(session: session, activate: true)
    }

    func uploadFile() {
        guard menuState.mode == .connectedServer,
              let session = connectionController.sessionSnapshot,
              session.currentChannelID > 0 else { return }
        showChannelFilesWindow(session: session, activate: true)
        channelFilesViewController?.performUpload()
    }

    private func showChannelFilesWindow(session: ConnectedServerSession, activate: Bool) {
        let viewController: ChannelFilesViewController
        if let existing = channelFilesViewController {
            existing.update(session: session)
            viewController = existing
        } else {
            viewController = ChannelFilesViewController(session: session, connectionController: connectionController)
            channelFilesViewController = viewController
        }

        if channelFilesWindowController == nil {
            let wc = ChannelFilesWindowController(contentViewController: viewController)
            wc.onUserClose = { [weak self] in
                self?.channelFilesWindowController = nil
                self?.channelFilesViewController = nil
            }
            channelFilesWindowController = wc
        } else {
            channelFilesWindowController?.window?.contentViewController = viewController
        }

        let base = L10n.text("files.window.title")
        channelFilesWindowController?.window?.title = session.currentChannelName.map { "\(base) — \($0)" } ?? base

        guard let window = channelFilesWindowController?.window else { return }
        _ = window.contentViewController?.view
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFront(nil)
        }
    }

    private func closeChannelFilesWindow() {
        channelFilesWindowController?.close()
        channelFilesWindowController = nil
        channelFilesViewController = nil
    }

    func openStats() {
        guard menuState.mode == .connectedServer else { return }
        if statsWindowController == nil {
            let vc = StatsViewController()
            vc.onRefreshNeeded = { [weak self] in
                self?.connectionController.queryServerStats()
            }
            vc.clientStatisticsProvider = { [weak self] in
                self?.connectionController.getClientStatistics()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.text("stats.window.title")
            window.isReleasedWhenClosed = false
            window.contentViewController = vc
            window.center()
            statsWindowController = NSWindowController(window: window)
            statsViewController = vc
        }
        statsWindowController?.showWindow(nil)
        statsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func announceAudioState() {
        guard menuState.mode == .connectedServer else { return }
        connectedServerViewController?.announceAudioStateAction(nil)
    }

    func exportChat() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.exportChatHistory(nil)
    }

    func addSavedServer() {
        guard menuState.mode == .savedServers else {
            return
        }
        showSavedServersWindow()
        savedServersViewController?.addServer(nil)
    }

    func editSelectedSavedServer() {
        guard menuState.mode == .savedServers, menuState.hasSelection else {
            return
        }

        showSavedServersWindow()
        savedServersViewController?.editSelectedServer(nil)
    }

    func deleteSelectedSavedServer() {
        guard menuState.mode == .savedServers, menuState.hasSelection else {
            return
        }

        showSavedServersWindow()
        savedServersViewController?.deleteSelectedServer(nil)
    }

    func importTeamTalkServers() {
        guard menuState.mode == .savedServers else {
            return
        }

        showSavedServersWindow()

        switch promptTeamTalkImportSource() {
        case .configurationFile:
            savedServersViewController?.importTeamTalkConfiguration(nil)
        case .ttFile:
            savedServersViewController?.importTTFile(nil)
        case .ttLink:
            importPastedTTLink()
        case nil:
            return
        }
    }

    private func promptTeamTalkImportSource() -> TeamTalkImportSource? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("teamTalkImport.source.title")
        alert.informativeText = L10n.text("teamTalkImport.source.message")
        alert.addButton(withTitle: L10n.text("teamTalkImport.source.configurationFile"))
        alert.addButton(withTitle: L10n.text("teamTalkImport.source.ttFile"))
        alert.addButton(withTitle: L10n.text("teamTalkImport.source.link"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .configurationFile
        case .alertSecondButtonReturn:
            return .ttFile
        case .alertThirdButtonReturn:
            return .ttLink
        default:
            return nil
        }
    }

    private func importPastedTTLink() {
        guard let rawLink = promptForTTLinkText() else {
            return
        }

        guard let parsedLink = parseTTLink(rawLink) else {
            presentErrorAlert(
                title: L10n.text("savedServers.alert.error.title"),
                message: L10n.text("teamTalkImport.link.invalid")
            )
            return
        }

        let draft = savedServerDraft(from: parsedLink)
        let editor = SavedServerEditorWindowController(
            mode: .add,
            draft: draft,
            parentWindow: savedServersWindowController?.window
        )

        guard let result = editor.runModal(),
              let record = result.makeRecord(id: UUID()) else {
            return
        }

        let existingRecord = store.load().first { $0.matchesEndpoint(of: record) }
        if let existingRecord,
           confirmImportReplacingExistingServer(
                existingRecord: existingRecord,
                importedRecord: record,
                sourceName: L10n.text("teamTalkImport.link.sourceName")
           ) == false {
            return
        }

        let savedRecord = existingRecord.map { record.withID($0.id) } ?? record

        do {
            try passwordStore.setPassword(result.password, for: savedRecord.id)
            try passwordStore.setChannelPassword(result.initialChannelPassword, for: savedRecord.id)
            if existingRecord == nil {
                store.add(savedRecord)
            } else {
                store.update(savedRecord)
            }
            store.setSelectedServer(id: savedRecord.id)
            store.flushPendingChanges()
            savedServersViewController?.refreshSavedServers(selecting: savedRecord.id)
        } catch {
            presentErrorAlert(
                title: L10n.text("savedServers.alert.error.title"),
                message: error.localizedDescription
            )
        }
    }

    private func confirmImportReplacingExistingServer(
        existingRecord: SavedServerRecord,
        importedRecord: SavedServerRecord,
        sourceName: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("teamTalkImport.duplicate.title")
        alert.informativeText = L10n.format(
            "teamTalkImport.duplicate.message",
            existingRecord.name,
            existingRecord.host,
            existingRecord.tcpPort,
            importedRecord.name,
            sourceName
        )
        alert.addButton(withTitle: L10n.text("teamTalkImport.duplicate.replace"))
        alert.addButton(withTitle: L10n.text("teamTalkImport.duplicate.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptForTTLinkText() -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("teamTalkImport.link.title")
        alert.informativeText = L10n.text("teamTalkImport.link.message")
        alert.addButton(withTitle: L10n.text("teamTalkImport.link.import"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let pasteboardValue = NSPasteboard.general.string(forType: .string) ?? ""
        let suggestedValue = parseTTLink(pasteboardValue) == nil ? "" : pasteboardValue
        let textField = NSTextField(string: suggestedValue)
        textField.placeholderString = L10n.text("teamTalkImport.link.placeholder")
        textField.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func connectSelectedSavedServer() {
        guard menuState.mode == .savedServers else {
            return
        }

        showSavedServersWindow()
        savedServersViewController?.connectSelectedServer()
    }

    func exportSelectedSavedServerTTFile() {
        exportServer()
    }

    func exportServer() {
        switch menuState.mode {
        case .savedServers:
            guard menuState.hasSelection else {
                return
            }
            showSavedServersWindow()
            guard let context = selectedSavedServerExportContext() else {
                return
            }
            promptAndExportServer(context)
        case .connectedServer:
            guard let context = connectedServerExportContext() else {
                return
            }
            restoreMainWindow()
            promptAndExportServer(context)
        }
    }

    private func selectedSavedServerExportContext() -> ServerExportContext? {
        guard menuState.mode == .savedServers, menuState.hasSelection else {
            return nil
        }

        guard let selectedID = store.selectedServerID(),
              let record = store.load().first(where: { $0.id == selectedID }) else {
            return nil
        }

        do {
            return ServerExportContext(
                record: record,
                password: try passwordStore.password(for: record.id) ?? "",
                channelPassword: try passwordStore.channelPassword(for: record.id) ?? record.initialChannelPassword,
                currentChannel: nil
            )
        } catch {
            presentErrorAlert(title: L10n.text("savedServers.alert.error.title"), message: error.localizedDescription)
            return nil
        }
    }

    private func connectedServerExportContext() -> ServerExportContext? {
        guard menuState.mode == .connectedServer,
              let session = connectionController.sessionSnapshot else {
            return nil
        }

        let record = session.savedServer
        let channelContext: ServerExportChannelContext?
        if session.currentChannelID > 0,
           let channel = session.findChannelByID(session.currentChannelID) {
            channelContext = ServerExportChannelContext(
                name: channel.name,
                path: "/" + channel.pathComponents.joined(separator: "/"),
                password: connectionController.passwordForChannel(session.currentChannelID)
            )
        } else {
            channelContext = nil
        }

        return ServerExportContext(
            record: record,
            password: connectionController.reconnectPassword ?? "",
            channelPassword: record.initialChannelPassword,
            currentChannel: channelContext
        )
    }

    private func promptAndExportServer(_ context: ServerExportContext) {
        guard let (destination, includeCurrentChannel) = promptServerExportDestination(context) else {
            return
        }

        let channelPath: String?
        let channelPassword: String
        if includeCurrentChannel, let currentChannel = context.currentChannel {
            channelPath = currentChannel.path
            channelPassword = currentChannel.password
        } else {
            let savedPath = context.record.initialChannelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            channelPath = savedPath.isEmpty ? nil : savedPath
            channelPassword = context.channelPassword
        }

        switch destination {
        case .ttFile:
            exportTTFile(
                record: context.record,
                password: context.password,
                channelPath: channelPath,
                channelPassword: channelPassword
            )
        case .ttLink:
            copyTTLink(
                record: context.record,
                password: context.password,
                channelPath: channelPath,
                channelPassword: channelPassword
            )
        }
    }

    private func promptServerExportDestination(_ context: ServerExportContext) -> (ServerExportDestination, Bool)? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("serverExport.title")
        alert.informativeText = L10n.format("serverExport.message", context.record.name)
        alert.addButton(withTitle: L10n.text("serverExport.ttFile"))
        alert.addButton(withTitle: L10n.text("serverExport.link"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let includeCurrentChannelButton: NSButton?
        if let currentChannel = context.currentChannel {
            let checkbox = NSButton(
                checkboxWithTitle: L10n.format("serverExport.includeCurrentChannel", currentChannel.name),
                target: nil,
                action: nil
            )
            checkbox.state = .on
            checkbox.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
            alert.accessoryView = checkbox
            includeCurrentChannelButton = checkbox
        } else {
            includeCurrentChannelButton = nil
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return (.ttFile, includeCurrentChannelButton?.state == .on)
        case .alertSecondButtonReturn:
            return (.ttLink, includeCurrentChannelButton?.state == .on)
        default:
            return nil
        }
    }

    private func exportTTFile(
        record: SavedServerRecord,
        password: String,
        channelPath: String?,
        channelPassword: String
    ) {
        guard let data = ttFileService.generateFileContents(
            record: record,
            password: password,
            defaultJoinChannelPath: channelPath,
            defaultJoinPassword: channelPassword,
            defaultStatusMessage: preferencesStore.preferences.defaultStatusMessage,
            defaultGender: preferencesStore.preferences.defaultGender
        ) else {
            presentErrorAlert(
                title: L10n.text("savedServers.alert.error.title"),
                message: L10n.text("ttFile.export.error.unreadable")
            )
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
            presentErrorAlert(title: L10n.text("savedServers.alert.error.title"), message: error.localizedDescription)
        }
    }

    private func copyTTLink(
        record: SavedServerRecord,
        password: String,
        channelPath: String?,
        channelPassword: String
    ) {
        let link = record.generateLink(
            password: password,
            channelPath: channelPath,
            channelPassword: channelPassword.isEmpty ? nil : channelPassword
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)

        let message = L10n.text("connectedServer.serverLink.copied")
        if menuState.mode == .connectedServer {
            connectedServerViewController?.announce(message)
        } else {
            announceWithVoiceOver(message)
        }
    }

    private func sanitizedTTFileName(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "server" : trimmed
        return baseName.replacingOccurrences(of: "/", with: "-") + ".tt"
    }

    func focusPrimaryArea() {
        if privateMessagesWindowController?.window?.isKeyWindow == true {
            focusPrivateMessagesPrimaryArea()
            return
        }

        switch menuState.mode {
        case .savedServers:
            showSavedServersWindow()
            savedServersViewController?.focusTable()
        case .connectedServer:
            restoreMainWindow()
            connectedServerViewController?.focusChannels()
        }
    }

    func focusSecondaryArea() {
        if privateMessagesWindowController?.window?.isKeyWindow == true {
            focusPrivateMessagesSecondaryArea()
            return
        }

        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.focusChatHistory()
    }

    func focusMessageArea() {
        if privateMessagesWindowController?.window?.isKeyWindow == true {
            focusPrivateMessagesMessageArea()
            return
        }

        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.focusMessageInput()
    }

    func focusHistoryArea() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.focusHistory()
    }

    func joinSelectedChannel() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.performJoinShortcut()
    }

    func leaveCurrentChannel() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.performLeaveShortcut()
    }

    func openMessages() {
        guard menuState.mode == .connectedServer else {
            return
        }
        if let session = connectionController.sessionSnapshot {
            showPrivateMessagesWindow(session: session, select: session.selectedPrivateConversationUserID, activate: true)
        }
    }

    func toggleMicrophone() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.performToggleMicrophoneShortcut()
    }

    func changeNickname() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.promptChangeNickname()
    }

    func changeStatus() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.promptChangeStatus()
    }

    func toggleChannelOperator() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.toggleChannelOperatorAction()
    }

    func kickSelectedUser() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.kickUserAction()
    }

    func kickSelectedUserFromServer() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.kickUserFromServerAction()
    }

    func kickBanSelectedUser() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.kickBanUserAction()
    }

    func moveSelectedUser() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.moveUserAction()
    }

    func toggleMuteSelectedUser() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.toggleMuteUserAction()
    }

    func toggleMuteSelectedUserMediaFile() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.toggleMuteUserMediaFileAction()
    }

    func adjustSelectedUserVolume() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.adjustUserVolume()
    }

    func toggleRecording() {
        guard menuState.mode == .connectedServer else { return }
        if menuState.isRecordingActive {
            stopAllRecording()
            return
        }
        guard let folderURL = preferencesStore.resolveRecordingFolderURL() else {
            promptRecordingFolder()
            return
        }
        startRecordingToFolder(folderURL)
    }

    private func stopAllRecording() {
        preferencesStore.updateLastRecordingWasActive(false)
        let mode = activeRecordingMode
        var pending = 0
        let announce = { [weak self] in
            pending -= 1
            if pending <= 0 {
                self?.releaseRecordingFolderAccess()
                self?.announceWithVoiceOver(L10n.text("recording.announced.stopped"))
            }
        }
        if mode & 1 != 0 {
            pending += 1
            connectionController.stopMuxedRecording { announce() }
        }
        if mode & 2 != 0 {
            pending += 1
            connectionController.stopSeparateRecording { announce() }
        }
        if pending == 0 {
            connectionController.stopMuxedRecording { [weak self] in
                self?.connectionController.stopSeparateRecording { [weak self] in
                    self?.releaseRecordingFolderAccess()
                    self?.announceWithVoiceOver(L10n.text("recording.announced.stopped"))
                }
            }
        }
    }

    private func promptRecordingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("recording.panel.choose")
        panel.message = L10n.text("recording.panel.message")
        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                self.preferencesStore.updateRecordingFolderBookmark(bookmark)
            }
            self.startRecordingToFolder(url)
        }
    }

    private func startRecordingToFolder(_ folder: URL) {
        guard folder.startAccessingSecurityScopedResource() else {
            preferencesStore.updateRecordingFolderBookmark(nil)
            promptRecordingFolder()
            return
        }
        recordingAccessedFolder = folder
        let format = AudioFileFormat(rawValue: UInt32(preferencesStore.preferences.recordingAudioFileFormat))
        let mode = preferencesStore.preferences.recordingMode
        activeRecordingMode = mode
        preferencesStore.updateLastRecordingWasActive(true)

        if mode & 1 != 0 {
            connectionController.startMuxedRecording(folder: folder, format: format) { [weak self] result in
                switch result {
                case .success(let fileName):
                    self?.announceWithVoiceOver(L10n.format("recording.announced.started", fileName))
                case .failure:
                    self?.announceWithVoiceOver(L10n.text("recording.announced.error"))
                    self?.releaseRecordingFolderAccess()
                }
            }
        }
        if mode & 2 != 0 {
            connectionController.startSeparateRecording(folder: folder, format: format) { [weak self] result in
                if case .failure = result {
                    self?.announceWithVoiceOver(L10n.text("recording.announced.error"))
                    self?.releaseRecordingFolderAccess()
                } else if mode & 1 == 0 {
                    self?.announceWithVoiceOver(L10n.text("recording.announced.startedSeparate"))
                }
            }
        }
    }

    private func releaseRecordingFolderAccess() {
        guard let folder = recordingAccessedFolder else { return }
        recordingAccessedFolder = nil
        folder.stopAccessingSecurityScopedResource()
    }

    func toggleHearMyself() {
        guard menuState.mode == .connectedServer else { return }
        connectionController.toggleHearMyself { [weak self] enabled in
            let key = enabled ? "shortcuts.hearMyself.announced.on" : "shortcuts.hearMyself.announced.off"
            self?.announceWithVoiceOver(L10n.text(key))
        }
    }

    func toggleMasterMute() {
        guard menuState.mode == .connectedServer else { return }
        connectionController.toggleMasterMute { [weak self] muted in
            self?.menuState.setMasterMuted(muted)
            let key = muted
                ? "shortcuts.masterMute.announced.muted"
                : "shortcuts.masterMute.announced.unmuted"
            self?.announceWithVoiceOver(L10n.text(key))
        }
    }

    func openSelectedUserInfo() {
        guard menuState.mode == .connectedServer,
              let user = connectedServerViewController?.selectedUserForInfo() else {
            return
        }

        let viewController: UserInfoViewController
        if let existing = userInfoViewController {
            viewController = existing
        } else {
            viewController = UserInfoViewController()
            viewController.userStatisticsProvider = { [weak self] userID in
                self?.connectionController.getUserStatistics(userID: userID)
            }
            userInfoViewController = viewController
        }

        if userInfoWindowController == nil {
            userInfoWindowController = UserInfoWindowController(contentViewController: viewController)
        } else {
            userInfoWindowController?.window?.contentViewController = viewController
        }

        userInfoUserID = user.id
        viewController.update(user: user)
        userInfoWindowController?.window?.title = L10n.format("userInfo.window.title.withName", user.displayName)
        userInfoWindowController?.showWindow(nil)
        userInfoWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferencesStore: preferencesStore,
                connectionController: connectionController,
                advancedMicrophoneSettingsStore: advancedMicrophoneSettingsStore
            )
        }
        preferencesWindowController?.showPreferences()
    }

    private func preloadPreferencesWindow() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferencesStore: preferencesStore,
                connectionController: connectionController,
                advancedMicrophoneSettingsStore: advancedMicrophoneSettingsStore
            )
        }
        preferencesWindowController?.preloadPreferencesIfNeeded()
    }

    func createChannel() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.promptCreateChannel()
    }

    func broadcastMessage() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.promptBroadcastMessage()
    }

    func copyServerLink() {
        guard menuState.mode == .connectedServer,
              let session = connectionController.sessionSnapshot else { return }
        let record = session.savedServer
        var channelPath = ""
        if session.currentChannelID > 0,
           let channel = session.findChannelByID(session.currentChannelID) {
            channelPath = "/" + channel.pathComponents.joined(separator: "/")
        }

        let draft = SavedServerDraft(
            record: record,
            password: connectionController.reconnectPassword ?? "",
            initialChannelPassword: nil
        )
        var editableDraft = draft
        editableDraft.initialChannelPath = channelPath

        let editor = SavedServerEditorWindowController(
            mode: .copyLink,
            draft: editableDraft,
            parentWindow: connectedServerViewController?.view.window
        )
        guard let result = editor.runModal() else { return }
        guard let resultRecord = result.makeRecord(id: UUID()) else { return }

        let link = resultRecord.generateLink(
            password: result.password,
            channelPath: result.sanitizedInitialChannelPath.isEmpty ? nil : result.sanitizedInitialChannelPath,
            channelPassword: result.initialChannelPassword.isEmpty ? nil : result.initialChannelPassword
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        connectedServerViewController?.announce(L10n.text("connectedServer.serverLink.copied"))
    }

    func setSelectedUsersSubscription(_ option: UserSubscriptionOption, enabled: Bool) {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.setSelectedUsersSubscription(option, enabled: enabled)
    }

    func updateChannel() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.promptUpdateChannel()
    }

    func deleteChannel() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.promptDeleteChannel()
    }

    func disconnectServer() {
        guard menuState.mode == .connectedServer else {
            return
        }

        guard confirmSavePendingUnsavedServerIfNeeded() else {
            return
        }

        connectionController.disconnect()
    }

    func openPrivateConversation(userID: Int32, displayName: String) {
        connectionController.openPrivateConversation(withUserID: userID, displayName: displayName, activate: true)
    }

    func focusPrivateMessagesPrimaryArea() {
        privateMessagesViewController?.focusConversations()
    }

    func focusPrivateMessagesSecondaryArea() {
        privateMessagesViewController?.focusHistory()
    }

    func focusPrivateMessagesMessageArea() {
        privateMessagesViewController?.focusMessageInput()
    }

    func openServerProperties() {
        guard menuState.mode == .connectedServer, menuState.isAdministrator else { return }
        restoreMainWindow()
        connectedServerViewController?.promptServerProperties()
    }

    func saveServerConfig() {
        guard menuState.mode == .connectedServer, menuState.isAdministrator else { return }
        connectionController.saveServerConfig { result in
            switch result {
            case .success:
                SoundPlayer.shared.play(.fileTxComplete)
            case .failure:
                break
            }
        }
    }

    func openUserAccounts() {
        guard menuState.mode == .connectedServer, menuState.isAdministrator else { return }
        if userAccountsWindowController == nil {
            let vc = UserAccountsViewController(connectionController: connectionController)
            userAccountsViewController = vc
            userAccountsWindowController = UserAccountsWindowController(contentViewController: vc)
        }
        userAccountsWindowController?.showWindow(nil)
        userAccountsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connectionController.listUserAccounts()
    }

    private func closeUserAccountsWindow() {
        userAccountsWindowController?.close()
        userAccountsWindowController = nil
        userAccountsViewController = nil
    }

    func openBannedUsers() {
        guard menuState.mode == .connectedServer, menuState.isAdministrator else { return }
        if bannedUsersWindowController == nil {
            let vc = BannedUsersViewController(connectionController: connectionController)
            bannedUsersViewController = vc
            bannedUsersWindowController = BannedUsersWindowController(contentViewController: vc)
        }
        bannedUsersWindowController?.showWindow(nil)
        bannedUsersWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connectionController.listBans()
    }

    private func closeBannedUsersWindow() {
        bannedUsersWindowController?.close()
        bannedUsersWindowController = nil
        bannedUsersViewController = nil
    }

    private func closeUserInfoWindow() {
        userInfoWindowController?.close()
        userInfoWindowController = nil
        userInfoViewController = nil
        userInfoUserID = nil
    }

    private func presentDisconnectedAlert(message: String) {
        guard let window = savedServersWindowController?.window else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("connectedServer.disconnect.alert.title")
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    private func handleLaunchTTFilesIfNeeded() {
        let urls = CommandLine.arguments.dropFirst().compactMap { argument -> URL? in
            guard argument.lowercased().hasSuffix(".tt") else {
                return nil
            }
            return URL(fileURLWithPath: NSString(string: argument).expandingTildeInPath)
        }
        enqueueTTFileURLs(Array(urls), source: "launchArgs")
    }

    private func handleTTLink(_ url: URL) {
        guard let parsedLink = parseTTLink(url) else {
            return
        }

        let record = savedServerRecord(from: parsedLink, id: UUID())

        if connectionController.sessionSnapshot != nil {
            let alert = NSAlert()
            alert.messageText = L10n.text("ttFile.alert.connected.title")
            alert.informativeText = L10n.format("ttFile.alert.connected.message", record.host)
            alert.addButton(withTitle: L10n.text("ttFile.alert.connected.confirm"))
            alert.addButton(withTitle: L10n.text("ttFile.alert.connected.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard confirmSavePendingUnsavedServerIfNeeded() else { return }
            connectionController.disconnectSynchronously()
        }

        let options = TeamTalkConnectOptions(
            nicknameOverride: nil,
            statusMessage: nil,
            genderOverride: nil,
            initialChannelPath: parsedLink.channel.isEmpty ? nil : parsedLink.channel,
            initialChannelPassword: parsedLink.channelPassword,
            preferJoinLastChannelFromServer: false
        )
        connectionController.connect(to: record, password: parsedLink.password, options: options) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.pendingUnsavedServerConfiguration = PendingUnsavedServerConfiguration(
                    record: record,
                    password: parsedLink.password,
                    initialChannelPassword: parsedLink.channelPassword
                )
            case .failure(let error):
                self.presentErrorAlert(
                    title: L10n.text("ttFile.alert.connectionError.title"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func parseTTLink(_ rawValue: String) -> ParsedTTLink? {
        let normalizedValue = normalizedTTLinkString(rawValue)
        guard let url = URL(string: normalizedValue) else {
            return nil
        }
        return parseTTLink(url)
    }

    private func normalizedTTLinkString(_ rawValue: String) -> String {
        let wrapperCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "<>\"'"))
        var value = rawValue.trimmingCharacters(in: wrapperCharacters)
        if let schemeRange = value.range(of: "tt://", options: [.caseInsensitive]) {
            value = String(value[schemeRange.lowerBound...])
        }
        if let endIndex = value.firstIndex(where: { $0.isWhitespace }) {
            value = String(value[..<endIndex])
        }
        return value.trimmingCharacters(in: wrapperCharacters)
    }

    private func parseTTLink(_ url: URL) -> ParsedTTLink? {
        guard url.scheme?.lowercased() == "tt",
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              host.isEmpty == false else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems ?? []

        func param(_ name: String) -> String {
            params.first(where: { item in
                item.name.caseInsensitiveCompare(name) == .orderedSame
            })?.value ?? ""
        }

        let tcpPort = parsedPort(param("tcpport")) ?? 10333
        let udpPort = parsedPort(param("udpport")) ?? tcpPort
        let channelPassword = param("chanpasswd").isEmpty ? param("chanpassword") : param("chanpasswd")

        return ParsedTTLink(
            host: host,
            tcpPort: tcpPort,
            udpPort: udpPort,
            encrypted: truthyQueryValue(param("encrypted")),
            username: param("username"),
            password: param("password"),
            channel: param("channel"),
            channelPassword: channelPassword
        )
    }

    private func savedServerDraft(from link: ParsedTTLink) -> SavedServerDraft {
        SavedServerDraft(
            name: link.host,
            host: link.host,
            tcpPort: String(link.tcpPort),
            udpPort: String(link.udpPort),
            encrypted: link.encrypted,
            nickname: preferencesStore.preferences.defaultNickname,
            username: link.username,
            password: link.password,
            initialChannelPath: link.channel,
            initialChannelPassword: link.channelPassword
        )
    }

    private func savedServerRecord(from link: ParsedTTLink, id: UUID) -> SavedServerRecord {
        SavedServerRecord(
            id: id,
            name: link.host,
            host: link.host,
            tcpPort: link.tcpPort,
            udpPort: link.udpPort,
            encrypted: link.encrypted,
            nickname: preferencesStore.preferences.defaultNickname,
            username: link.username,
            initialChannelPath: link.channel,
            initialChannelPassword: link.channelPassword
        )
    }

    private func parsedPort(_ value: String) -> Int? {
        guard let port = Int(value), (1...65535).contains(port) else {
            return nil
        }
        return port
    }

    private func truthyQueryValue(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private func enqueueTTFileURLs(_ urls: [URL], source: String) {
        let normalizedURLs = urls
            .filter { $0.pathExtension.caseInsensitiveCompare("tt") == .orderedSame }
            .map { $0.standardizedFileURL }

        guard normalizedURLs.isEmpty == false else {
            return
        }

        for url in normalizedURLs where pendingTTFileURLs.contains(url) == false {
            pendingTTFileURLs.append(url)
        }

        processPendingTTFileURLsIfPossible()
    }

    private func processPendingTTFileURLsIfPossible() {
        guard pendingTTFileURLs.isEmpty == false else {
            return
        }

        guard hasFinishedLaunching else {
            return
        }

        let urls = pendingTTFileURLs
        pendingTTFileURLs.removeAll()
        handleIncomingTTFiles(urls)
    }

    private func handleIncomingTTFiles(_ urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "tt" }) else {
            return
        }

        do {
            let payload = try ttFileService.load(from: url)
            let proceed = {
                self.openTTFilePayload(payload)
            }

            if connectionController.sessionSnapshot != nil {
                guard confirmOpenTTFileWhileConnected(payload: payload) else {
                    return
                }
                guard confirmSavePendingUnsavedServerIfNeeded() else {
                    return
                }
                connectionController.disconnectSynchronously()
                proceed()
                return
            }

            proceed()
        } catch {
            presentErrorAlert(
                title: L10n.text("ttFile.alert.openError.title"),
                message: L10n.format("ttFile.alert.openError.message", url.lastPathComponent, error.localizedDescription)
            )
        }
    }

    private func openTTFilePayload(_ payload: TTFilePayload) {
        var nickname = payload.auth.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if nickname.isEmpty {
            nickname = preferencesStore.preferences.defaultNickname
        }

        let record = SavedServerRecord(
            id: UUID(),
            name: payload.name,
            host: payload.host,
            tcpPort: payload.tcpPort,
            udpPort: payload.udpPort,
            encrypted: payload.encrypted,
            nickname: nickname,
            username: payload.auth.username,
            initialChannelPath: payload.join?.channelPath ?? "",
            initialChannelPassword: payload.join?.password ?? ""
        )

        if let clientSetup = payload.clientSetup, clientSetup.hasAnySettings {
            applyClientSetupIfConfirmed(clientSetup, fileName: payload.fileURL.lastPathComponent)
        }

        let options = TeamTalkConnectOptions(
            nicknameOverride: nickname,
            statusMessage: payload.auth.statusMessage,
            genderOverride: payload.clientSetup?.gender,
            initialChannelPath: payload.join?.channelPath,
            initialChannelPassword: payload.join?.password ?? "",
            preferJoinLastChannelFromServer: payload.join?.joinLastChannel ?? false
        )

        connectionController.connect(to: record, password: payload.auth.password, options: options) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success:
                self.pendingUnsavedServerConfiguration = PendingUnsavedServerConfiguration(
                    record: record,
                    password: payload.auth.password,
                    initialChannelPassword: payload.join?.password ?? ""
                )
            case .failure(let error):
                self.presentErrorAlert(
                    title: L10n.text("ttFile.alert.connectionError.title"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func applyClientSetupIfConfirmed(_ setup: TTFilePayload.ClientSetup, fileName: String) {
        guard confirmApplyClientSetup(setup, fileName: fileName) else {
            return
        }

        let nickname = setup.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if nickname.isEmpty == false {
            preferencesStore.updateDefaultNickname(nickname)
        }
        if let gender = setup.gender {
            preferencesStore.updateDefaultGender(gender)
        }
    }

    private func confirmOpenTTFileWhileConnected(payload: TTFilePayload) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("ttFile.alert.connected.title")
        alert.informativeText = L10n.format("ttFile.alert.connected.message", payload.name)
        alert.addButton(withTitle: L10n.text("ttFile.alert.connected.confirm"))
        alert.addButton(withTitle: L10n.text("ttFile.alert.connected.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmApplyClientSetup(_ setup: TTFilePayload.ClientSetup, fileName: String) -> Bool {
        let supportedParts = [
            setup.nickname.isEmpty == false ? L10n.text("ttFile.clientSetup.nickname") : nil,
            setup.gender != nil ? L10n.text("ttFile.clientSetup.gender") : nil,
            setup.voiceActivated != nil ? L10n.text("ttFile.clientSetup.voiceActivatedIgnored") : nil
        ].compactMap { $0 }
        let unsupportedPart = setup.unsupportedFields.isEmpty
            ? nil
            : L10n.format("ttFile.clientSetup.unsupportedFields", setup.unsupportedFields.joined(separator: ", "))
        let details = (supportedParts + [unsupportedPart].compactMap { $0 }).joined(separator: "\n")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("ttFile.alert.clientSetup.title")
        alert.informativeText = L10n.format("ttFile.alert.clientSetup.message", fileName, details)
        alert.addButton(withTitle: L10n.text("ttFile.alert.clientSetup.confirm"))
        alert.addButton(withTitle: L10n.text("ttFile.alert.clientSetup.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmSavePendingUnsavedServerIfNeeded() -> Bool {
        guard let configuration = pendingUnsavedServerConfiguration else {
            return true
        }

        guard let session = connectionController.sessionSnapshot,
              session.savedServer.id == configuration.record.id else {
            pendingUnsavedServerConfiguration = nil
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("ttFile.savePrompt.title")
        alert.informativeText = L10n.format("ttFile.savePrompt.message", configuration.record.name)
        alert.addButton(withTitle: L10n.text("ttFile.savePrompt.save"))
        alert.addButton(withTitle: L10n.text("ttFile.savePrompt.dontSave"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return promptForServerNameAndSave(configuration)
        case .alertSecondButtonReturn:
            pendingUnsavedServerConfiguration = nil
            return true
        default:
            return false
        }
    }

    private func promptForServerNameAndSave(_ configuration: PendingUnsavedServerConfiguration) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("ttFile.saveName.title")
        alert.informativeText = L10n.text("ttFile.saveName.message")
        alert.addButton(withTitle: L10n.text("ttFile.saveName.save"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let textField = NSTextField(string: configuration.record.name)
        textField.placeholderString = L10n.text("ttFile.saveName.placeholder")
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            presentErrorAlert(
                title: L10n.text("savedServers.alert.error.title"),
                message: L10n.text("ttFile.saveName.emptyName")
            )
            return false
        }

        do {
            var record = configuration.record
            record.name = name
            try passwordStore.setPassword(configuration.password, for: record.id)
            try passwordStore.setChannelPassword(configuration.initialChannelPassword, for: record.id)
            store.add(record)
            store.setSelectedServer(id: record.id)
            store.flushPendingChanges()
            pendingUnsavedServerConfiguration = nil
            return true
        } catch {
            presentErrorAlert(
                title: L10n.text("savedServers.alert.error.title"),
                message: error.localizedDescription
            )
            return false
        }
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

extension AppDelegate: TeamTalkConnectionControllerDelegate {
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateSession session: ConnectedServerSession) {
        let previousHistory = session.sessionHistory.count < lastObservedSessionHistory.count
            ? []
            : lastObservedSessionHistory
        handleBackgroundSessionHistory(previousEntries: previousHistory, session: session)
        lastObservedSessionHistory = session.sessionHistory
        menuState.setAdministrator(session.isAdministrator)
        menuState.setCanSendBroadcast(session.canSendBroadcast)
        menuState.setNicknameLocked(session.isNicknameLocked)
        menuState.setStatusLocked(session.isStatusLocked)
        showConnectedServerWindow(session: session)

        // Auto-restart recording when joining a new channel
        let previousChannelID = lastObservedChannelID
        lastObservedChannelID = session.currentChannelID
        if session.currentChannelID > 0,
           session.currentChannelID != previousChannelID,
           !session.recordingActive,
           preferencesStore.preferences.autoRestartRecording,
           preferencesStore.preferences.lastRecordingWasActive,
           let folderURL = preferencesStore.resolveRecordingFolderURL() {
            startRecordingToFolder(folderURL)
        }

        if privateMessagesWindowController != nil {
            showPrivateMessagesWindow(session: session, select: nil, activate: false)
        }
        if channelFilesWindowController != nil {
            if session.currentChannelID > 0 {
                showChannelFilesWindow(session: session, activate: false)
            } else {
                closeChannelFilesWindow()
            }
        }
        if let userInfoUserID, userInfoWindowController != nil {
            let user = flattenedUsers(in: session.rootChannels).first(where: { $0.id == userInfoUserID })
            userInfoViewController?.update(user: user)
            userInfoWindowController?.window?.title = user.map {
                L10n.format("userInfo.window.title.withName", $0.displayName)
            } ?? L10n.text("userInfo.window.title")
        }
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateAudioRuntime update: ConnectedServerAudioRuntimeUpdate) {
        connectedServerViewController?.applyAudioRuntimeUpdate(update)
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateActiveTransfers transfers: [FileTransferProgress], currentChannelID: Int32) {
        channelFilesViewController?.updateActiveTransfers(transfers, currentChannelID: currentChannelID)
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didDisconnectWithMessage message: String?) {
        releaseRecordingFolderAccess()
        activeRecordingMode = 0
        lastObservedChannelID = 0
        lastObservedSessionHistory = []
        let shouldShowAlert = message
        closeUserAccountsWindow()
        closeBannedUsersWindow()
        closeUserInfoWindow()
        showSavedServersWindow()

        if let shouldShowAlert {
            presentDisconnectedAlert(message: shouldShowAlert)
        }
    }

    func teamTalkConnectionControllerDidStartReconnecting(_ controller: TeamTalkConnectionController) {
        connectedServerViewController?.showReconnecting()
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didFinishFileTransfer fileName: String, isDownload: Bool, success: Bool) {
        if let vc = channelFilesViewController, channelFilesWindowController?.window?.isVisible == true {
            vc.announceTransferResult(fileName: fileName, isDownload: isDownload, success: success)
        } else {
            // Announce in main window
            let key: String
            if success {
                key = isDownload ? "files.transfer.downloaded" : "files.transfer.uploaded"
            } else {
                key = isDownload ? "files.transfer.downloadFailed" : "files.transfer.uploadFailed"
            }
            let message = L10n.format(key, fileName)
            let element: Any = NSApp.accessibilityWindow() ?? savedServersWindowController?.window as Any
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

    func teamTalkConnectionController(
        _ controller: TeamTalkConnectionController,
        didRequestPrivateMessagesWindowFor userID: Int32?,
        reason: PrivateMessagesPresentationReason
    ) {
        guard let session = controller.sessionSnapshot else {
            return
        }
        let isWindowVisible = privateMessagesWindowController?.window?.isVisible == true

        switch reason {
        case .userInitiated:
            showPrivateMessagesWindow(session: session, select: userID, activate: true)
        case .incomingMessage:
            if isWindowVisible {
                showPrivateMessagesWindow(session: session, select: nil, activate: false)
            } else {
                showPrivateMessagesWindow(session: session, select: userID, activate: false)
            }
        }
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveIncomingTextMessage event: IncomingTextMessageEvent) {
        handleBackgroundIncomingTextMessage(event)
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveServerStatistics stats: ServerStatistics) {
        statsViewController?.update(stats: stats)
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveUserAccounts accounts: [UserAccountProperties]) {
        userAccountsViewController?.update(accounts: accounts)
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveBannedUsers bans: [BannedUserProperties]) {
        bannedUsersViewController?.update(bans: bans)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Allow notifications to display even when the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard menuState.mode == .connectedServer else { return true }
        disconnectServer()
        return false
    }
}

private extension AppDelegate {
    func flattenedUsers(in channels: [ConnectedServerChannel]) -> [ConnectedServerUser] {
        channels.flatMap { $0.users + flattenedUsers(in: $0.children) }
    }
}
