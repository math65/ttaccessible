//
//  AppDelegate.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit
import Combine
import KeyboardShortcuts
import UserNotifications
import UniformTypeIdentifiers
import Sparkle

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

    private enum ServerListExportMode {
        case singleFile
        case filePerServer
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
    private var feedbackWindowController: FeedbackWindowController?
    private let announcementService = AnnouncementService()
    private var userAccountsWindowController: NSWindowController?
    private var bannedUsersWindowController: NSWindowController?
    private var userInfoWindowController: UserInfoWindowController?
    private var connectedUsersWindowController: ConnectedUsersWindowController?
    var profilesWindowController: ProfilesWindowController?
    private weak var savedServersViewController: SavedServersViewController?
    private weak var connectedServerViewController: ConnectedServerViewController?
    private weak var privateMessagesViewController: PrivateMessagesViewController?
    private weak var channelFilesViewController: ChannelFilesViewController?
    private weak var userAccountsViewController: UserAccountsViewController?
    private weak var bannedUsersViewController: BannedUsersViewController?
    private weak var userInfoViewController: UserInfoViewController?
    private weak var connectedUsersViewController: ConnectedUsersViewController?
    weak var profilesViewController: ProfilesViewController?
    private var hasFinishedLaunching = false
    private var pendingTTFileURLs: [URL] = []
    private var userInfoUserID: Int32?
    private var lastObservedSessionHistory: [SessionHistoryEntry] = []
    private var recordingAccessedFolder: URL?
    private var activeRecordingMode: Int = 0
    private var recordingStopKeyMonitor: Any?
    private var lastObservedChannelID: Int32 = 0
    private var pendingUnsavedServerConfiguration: PendingUnsavedServerConfiguration?

    private var deviceChangeObserver: Any?

    private lazy var updaterController: SPUStandardUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var updaterAutoCheckCancellable: AnyCancellable?
    private var nicknameCancellable: AnyCancellable?
    private var userMenuVisibilityCancellable: AnyCancellable?
    private var pushToTalkModeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProfileInstanceLock.acquire(for: ProfileContext.current)
        AudioLogger.clear()
        let sdkVersion = String(cString: TT_GetVersion())
        AudioLogger.log("App launched — TeamTalk SDK %@ — profile %@", sdkVersion, ProfileContext.current.slug)
        #if DEBUG
        _ = AudioPCMResamplerSelfTest.runAll()
        #endif
        connectionController.delegate = self
        connectionController.audioDeviceChangeMonitor = audioDeviceChangeMonitor
        UNUserNotificationCenter.current().delegate = self
        audioDeviceChangeMonitor.startListening()

        deviceChangeObserver = NotificationCenter.default.addObserver(
            forName: AudioDeviceChangeMonitor.audioDevicesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let selector = notification.userInfo?[AudioDeviceChangeMonitor.selectorUserInfoKey] as? UInt32 ?? 0
            self?.connectionController.handleDebouncedAudioHardwareChange(selector: selector)
        }
        requestNotificationPermission()
        showSavedServersWindow()
        connectToLastServerOnLaunchIfEnabled()
        DispatchQueue.main.async { [weak self] in
            self?.preloadPreferencesWindow()
        }
        hasFinishedLaunching = true
        // Create the first TeamTalk instance in the background now. TT_InitTeamTalkPoll
        // enumerates all CoreAudio devices (~12 s on a large rig); prewarming it here
        // keeps that cost off the connect path so connecting is fast.
        connectionController.prewarmConnection()
        handleLaunchTTFilesIfNeeded()
        processPendingTTFileURLsIfPossible()
        syncSparkleAutoCheckPreference()
        syncNicknamePreference()
        scheduleLaunchUpdateCheck()
        configurePushToTalkObservers()
        installRecordingStopKeyMonitor()
        configureUserMenuVisibility()
        // Slight delay so the announcement alert never races the main window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.announcementService.checkAtLaunch()
        }
    }

    /// Flush any pending debounced writes of the live preference / saved-server
    /// stores to the current profile's UserDefaults suite. Called before
    /// duplicating the current profile so the copy captures the latest edits.
    func flushPersistableStores() {
        store.flushPendingChanges()
        preferencesStore.flushPendingChanges()
    }

    /// The User command menu is declared unconditionally — macOS 12's
    /// CommandsBuilder cannot express a conditional menu, and the Optional
    /// Commands conformance an availability split would need doesn't exist at
    /// runtime before macOS 13. Its menu-bar visibility is managed here at the
    /// AppKit layer instead: hidden unless connected, the same behavior the
    /// SwiftUI-level `if` used to provide. Re-applied (idempotently) after any
    /// menuState change, since SwiftUI may rebuild the main menu then.
    private func configureUserMenuVisibility() {
        userMenuVisibilityCancellable = menuState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.applyUserMenuVisibility()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.applyUserMenuVisibility()
                }
            }
        // SwiftUI installs the main menu after launch finishes — apply once
        // now and again after it has settled.
        applyUserMenuVisibility()
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.applyUserMenuVisibility()
            }
        }
    }

    private func applyUserMenuVisibility() {
        let title = L10n.text("user.menu.title")
        guard let item = NSApp.mainMenu?.items.first(where: {
            $0.submenu?.title == title || $0.title == title
        }) else { return }
        item.isHidden = menuState.mode != .connectedServer
    }

    private func syncNicknamePreference() {
        nicknameCancellable = preferencesStore.$preferences
            .map(\.defaultNickname)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] nickname in
                self?.connectionController.changeNickname(to: nickname) { _ in }
            }
    }

    private func configurePushToTalkObservers() {
        // Lets the audio insert path treat PTT as inactive when no global
        // shortcut is configured — otherwise pushToTalkPressed never flips
        // and the mic stays muted forever.
        connectionController.pushToTalkShortcutResolver = {
            KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
        }

        // Static handlers registered once for the lifetime of the app — the
        // library only fires them while a shortcut is configured for the
        // .pushToTalk name. Mode gating (always-on vs PTT) happens in the
        // audio insert path; we still want the press/release effects for the
        // beep + announcement either way (cheap and harmless if mode is
        // .alwaysOn — the user wouldn't have set a shortcut in that case).
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.handlePushToTalkPress()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.handlePushToTalkRelease()
        }

        // Reset transmit state when the mode toggles, so toggling Push-to-talk
        // off doesn't leave the gate stuck open from a previous press.
        pushToTalkModeCancellable = preferencesStore.$preferences
            .map(\.microphoneMode)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.connectionController.setPushToTalkPressed(false)
            }
    }

    private func handlePushToTalkPress() {
        connectionController.setPushToTalkPressed(true)
        playPushToTalkBeep()
    }

    private func handlePushToTalkRelease() {
        connectionController.setPushToTalkPressed(false)
        playPushToTalkBeep()
    }

    private func playPushToTalkBeep() {
        guard preferencesStore.preferences.pushToTalkBeepEnabled else { return }
        SoundPlayer.shared.play(.hotkey)
    }

    private func syncSparkleAutoCheckPreference() {
        updaterController.updater.automaticallyChecksForUpdates = preferencesStore.preferences.autoCheckForUpdates
        updaterAutoCheckCancellable = preferencesStore.$preferences
            .map(\.autoCheckForUpdates)
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updaterController.updater.automaticallyChecksForUpdates = enabled
            }
    }

    private func scheduleLaunchUpdateCheck() {
        guard preferencesStore.preferences.autoCheckForUpdates else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.updaterController.updater.checkForUpdatesInBackground()
        }
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
        ProfileInstanceLock.release(for: ProfileContext.current)
        connectionController.disconnectSynchronously()
        // The TeamTalk SDK's internal reactor thread sometimes outlives
        // TT_CloseTeamTalk and crashes when exit()'s static destructors race
        // with it. A short sleep lets the SDK threads finish unwinding before
        // we return and the C++ statics tear down. See the 2026-05-19 crash
        // report in libTeamTalk5.dylib::ACE_Reactor::run_reactor_event_loop.
        Thread.sleep(forTimeInterval: 0.3)
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
            window.title = ProfileContext.current.decorateWindowTitle(L10n.text("savedServers.window.title"))
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
            // Assign the placeholder's view directly: a bare NSViewController
            // has no nib, and before macOS 14 its default loadView throws.
            let placeholder = NSViewController()
            placeholder.view = NSView()
            let windowController = SavedServersWindowController(contentViewController: placeholder)
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
        savedServersWindowController?.window?.title = ProfileContext.current.decorateWindowTitle(
            L10n.format("connectedServer.window.title", session.displayName)
        )
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
            let window = EscapeClosableWindow(
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

    func exportServerList() {
        guard menuState.mode == .savedServers else {
            return
        }
        showSavedServersWindow()
        switch promptServerListExportMode() {
        case .singleFile:
            savedServersViewController?.exportAllServersToSingleFile(nil)
        case .filePerServer:
            savedServersViewController?.exportEachServerToFolder(nil)
        case nil:
            return
        }
    }

    private func promptServerListExportMode() -> ServerListExportMode? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("serverExport.mode.title")
        alert.informativeText = L10n.text("serverExport.mode.message")
        alert.addButton(withTitle: L10n.text("serverExport.mode.singleFile"))
        alert.addButton(withTitle: L10n.text("serverExport.mode.filePerServer"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .singleFile
        case .alertSecondButtonReturn:
            return .filePerServer
        default:
            return nil
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

    /// On launch, automatically connect to the last used server when the
    /// `connectToLastServerOnLaunch` preference is enabled and a previously
    /// selected server still exists. The saved-servers window stays visible
    /// underneath, so a failed or cancelled connection falls back to the list.
    private func connectToLastServerOnLaunchIfEnabled() {
        // A profile clone launched with -noconnect starts disconnected so it can
        // be pointed at a different server (mirrors the Qt client). Passed via
        // argument or environment (NSWorkspace may drop arguments).
        let noConnect = ProfileContext.startsDisconnectedOnLaunch
            || CommandLine.arguments.contains("-noconnect")
            || ProcessInfo.processInfo.environment["TTACCESSIBLE_NOCONNECT"] == "1"
        guard noConnect == false else {
            return
        }
        guard preferencesStore.preferences.connectToLastServerOnLaunch else {
            return
        }
        guard let selectedID = store.selectedServerID(),
              store.load().contains(where: { $0.id == selectedID }) else {
            return
        }
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

    func focusChannelMixerArea() {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.focusChannelMixer()
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

    // `fromControl` is true when triggered by pressing the mic toolbar button itself:
    // VoiceOver then re-reads the button's state-bearing label, so the spoken status
    // announcement is suppressed to avoid saying "Microphone" twice. The keyboard
    // shortcut / menu path (focus elsewhere) keeps the announcement.
    func toggleMicrophone(fromControl: Bool = false) {
        guard menuState.mode == .connectedServer else {
            return
        }
        restoreMainWindow()
        connectedServerViewController?.performToggleMicrophoneShortcut(announceStatus: fromControl == false)
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

    /// True when the Connected Users window is the key window — per-user keyboard
    /// shortcuts then act on its selection instead of the main outline view.
    private var connectedUsersWindowIsKey: Bool {
        connectedUsersViewController?.view.window?.isKeyWindow == true
    }

    /// Dispatches a per-user action to the Connected Users window when it is key,
    /// otherwise to the main outline view (bringing the main window forward).
    private func routeUserAction(
        connectedUsers: (ConnectedUsersViewController) -> Void,
        mainWindow: () -> Void
    ) {
        guard menuState.mode == .connectedServer else { return }
        if connectedUsersWindowIsKey, let vc = connectedUsersViewController {
            connectedUsers(vc)
            return
        }
        restoreMainWindow()
        mainWindow()
    }

    func toggleChannelOperator() {
        routeUserAction(
            connectedUsers: { $0.keyToggleOperatorSelectedUser() },
            mainWindow: { connectedServerViewController?.toggleChannelOperatorAction() }
        )
    }

    func kickSelectedUser() {
        routeUserAction(
            connectedUsers: { $0.keyKickSelectedUser() },
            mainWindow: { connectedServerViewController?.kickUserAction() }
        )
    }

    func kickSelectedUserFromServer() {
        routeUserAction(
            connectedUsers: { $0.keyKickFromServerSelectedUser() },
            mainWindow: { connectedServerViewController?.kickUserFromServerAction() }
        )
    }

    func kickBanSelectedUser() {
        routeUserAction(
            connectedUsers: { $0.keyKickBanSelectedUser() },
            mainWindow: { connectedServerViewController?.kickBanUserAction() }
        )
    }

    func moveSelectedUser() {
        routeUserAction(
            connectedUsers: { $0.keyMoveSelectedUser() },
            mainWindow: { connectedServerViewController?.moveUserAction() }
        )
    }

    func toggleMuteSelectedUser() {
        routeUserAction(
            connectedUsers: { $0.keyMuteSelectedUser() },
            mainWindow: { connectedServerViewController?.toggleMuteUserAction() }
        )
    }

    func toggleMuteSelectedUserMediaFile() {
        routeUserAction(
            connectedUsers: { $0.keyMuteMediaFileSelectedUser() },
            mainWindow: { connectedServerViewController?.toggleMuteUserMediaFileAction() }
        )
    }

    func adjustSelectedUserVolume() {
        routeUserAction(
            connectedUsers: { $0.keyAdjustVolumeSelectedUser() },
            mainWindow: { connectedServerViewController?.adjustUserVolume() }
        )
    }

    /// While recording, ⌘⇧R has no menu item (only a single Stop item on ⌘R is shown), so
    /// catch ⌘⇧R here to stop as well. When idle, the "start (preferred)" menu item claims
    /// ⌘⇧R before it reaches this monitor, so this only ever fires while recording is active.
    private func installRecordingStopKeyMonitor() {
        recordingStopKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.menuState.isRecordingActive,
                  event.charactersIgnoringModifiers?.lowercased() == "r",
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] else {
                return event
            }
            self.toggleRecording()
            return nil
        }
    }

    /// Toggle recording. When starting, `mode` selects the recording layout as a bitmask
    /// (1 = single muxed file, 2 = separate files, 3 = both). Pass `nil` to use the mode
    /// configured in preferences (⌘⇧R and the toolbar button); ⌘R passes `1` to force a
    /// single file regardless of the preference.
    func toggleRecording(mode: Int? = nil) {
        guard menuState.mode == .connectedServer else { return }
        if menuState.isRecordingActive {
            stopAllRecording()
            return
        }
        // Honour the channel's recording policy: a CHANNEL_NO_RECORDING channel forbids
        // recording unless our account holds USERRIGHT_RECORD_VOICE. (We patch the SDK to
        // keep *playing* audio in such channels, but must not record there.)
        guard connectionController.isRecordingAllowedInCurrentChannel() else {
            announceWithVoiceOver(L10n.text("recording.announced.notAllowedHere"))
            return
        }
        let resolvedMode = mode ?? preferencesStore.preferences.recordingMode
        guard let folderURL = preferencesStore.resolveRecordingFolderURL() else {
            promptRecordingFolder(mode: resolvedMode)
            return
        }
        startRecordingToFolder(folderURL, mode: resolvedMode)
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

    private func promptRecordingFolder(mode: Int) {
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
            self.startRecordingToFolder(url, mode: mode)
        }
    }

    private func startRecordingToFolder(_ folder: URL, mode: Int) {
        guard folder.startAccessingSecurityScopedResource() else {
            preferencesStore.updateRecordingFolderBookmark(nil)
            promptRecordingFolder(mode: mode)
            return
        }
        recordingAccessedFolder = folder
        let format = AudioFileFormat(rawValue: UInt32(preferencesStore.preferences.recordingAudioFileFormat))
        activeRecordingMode = mode
        preferencesStore.updateLastRecordingWasActive(true)
        // Persist the *actual* mode so auto-restart restores what was really in use
        // (e.g. a single-file ⌘R recording) rather than the clamped preference mode.
        preferencesStore.updateLastActiveRecordingMode(mode)

        let recordsStems = mode & 2 != 0
        if mode & 1 != 0 {
            connectionController.startMuxedRecording(folder: folder, format: format) { [weak self] result in
                switch result {
                case .success(let fileName):
                    // "Both" (single + stems) gets its own announcement so ⌘⇧R is
                    // distinct from ⌘R's plain single-file recording.
                    let key = recordsStems ? "recording.announced.startedBoth" : "recording.announced.started"
                    self?.announceWithVoiceOver(L10n.format(key, fileName))
                case .failure:
                    self?.announceWithVoiceOver(L10n.text("recording.announced.error"))
                    self?.releaseRecordingFolderAccess()
                }
            }
        }
        if recordsStems {
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
            self?.menuState.setHearMyselfEnabled(enabled)
            let key = enabled ? "shortcuts.hearMyself.announced.on" : "shortcuts.hearMyself.announced.off"
            self?.announceWithVoiceOver(L10n.text(key))
        }
    }

    func startStreamingMediaFromFile() {
        guard menuState.mode == .connectedServer, !menuState.isMediaStreamingActive else { return }
        promptMediaStreamFile()
    }

    func startStreamingMediaFromURL() {
        guard menuState.mode == .connectedServer, !menuState.isMediaStreamingActive else { return }
        promptMediaStreamURL()
    }

    func startStreamingMediaFromDevice() {
        guard menuState.mode == .connectedServer, !menuState.isMediaStreamingActive else { return }
        promptMediaStreamDevice()
    }

    func stopMediaStreaming() {
        guard menuState.mode == .connectedServer, menuState.isMediaStreamingActive else { return }
        connectionController.stopStreamingMediaFile()
        announceWithVoiceOver(L10n.text("mediaStream.announced.finished"))
    }

    private func promptMediaStreamFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = L10n.text("mediaStream.panel.title")
        panel.message = L10n.text("mediaStream.panel.message")
        panel.prompt = L10n.text("mediaStream.panel.choose")
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie, .mpeg4Movie, .video, .avi, .quickTimeMovie]
        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.connectionController.startStreamingMediaFile(at: url) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        self?.announceWithVoiceOver(L10n.text("mediaStream.announced.error"))
                        let alert = NSAlert(error: error)
                        alert.runModal()
                    }
                }
            }
        }
    }

    private func promptMediaStreamURL() {
        let alert = NSAlert()
        alert.messageText = L10n.text("mediaStream.url.prompt.title")
        alert.informativeText = L10n.text("mediaStream.url.prompt.message")
        alert.addButton(withTitle: L10n.text("mediaStream.url.prompt.start"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.placeholderString = L10n.text("mediaStream.url.prompt.placeholder")
        textField.setAccessibilityLabel(L10n.text("mediaStream.url.prompt.accessibilityLabel"))
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let raw = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "rtmp", "rtmps", "rtsp", "mms"].contains(scheme),
                  url.host?.isEmpty == false else {
                self.announceWithVoiceOver(L10n.text("mediaStream.url.error.invalid"))
                let errorAlert = NSAlert()
                errorAlert.messageText = L10n.text("mediaStream.url.error.invalid.title")
                errorAlert.informativeText = L10n.text("mediaStream.url.error.invalid")
                errorAlert.runModal()
                return
            }
            self.connectionController.startStreamingMediaURL(url) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        self?.announceWithVoiceOver(L10n.text("mediaStream.announced.error"))
                        let alert = NSAlert(error: error)
                        alert.runModal()
                    }
                }
            }
        }
    }

    private func promptMediaStreamDevice() {
        // Source discovery off the main thread: SCK's shareable-content fetch
        // (macOS 13.0–14.1) blocks up to a few seconds on first permission.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let devices = InputAudioDeviceResolver.availableInputDevices()
            var applicationSources: [DeviceStreamCaptureSpec] = []
            var voiceOverAvailable = false
            if #available(macOS 14.2, *) {
                applicationSources = ProcessTapCaptureBackend.runningAudioApplications()
                    .map { DeviceStreamCaptureSpec.application(bundleID: $0.bundleID, displayName: $0.name) }
                voiceOverAvailable = true
            } else if #available(macOS 13.0, *) {
                let apps = SCKAudioCaptureBackend.capturableApplications()
                applicationSources = apps
                    .map { DeviceStreamCaptureSpec.application(bundleID: $0.bundleID, displayName: $0.name) }
                voiceOverAvailable = apps.contains { app in
                    DeviceStreamCaptureSpec.voiceOverBundlePrefixes.contains { app.bundleID.hasPrefix($0) }
                }
            }
            // macOS 12: no public per-app audio capture API — devices only.
            DispatchQueue.main.async {
                self?.presentMediaStreamSourceDialog(
                    devices: devices,
                    applicationSources: applicationSources,
                    voiceOverAvailable: voiceOverAvailable
                )
            }
        }
    }

    private func presentMediaStreamSourceDialog(
        devices: [InputAudioDeviceInfo],
        applicationSources: [DeviceStreamCaptureSpec],
        voiceOverAvailable: Bool
    ) {
        guard devices.isEmpty == false || applicationSources.isEmpty == false || voiceOverAvailable else {
            announceWithVoiceOver(L10n.text("mediaStream.device.error.noDevices"))
            let errorAlert = NSAlert()
            errorAlert.messageText = L10n.text("mediaStream.device.prompt.title")
            errorAlert.informativeText = L10n.text("mediaStream.device.error.noDevices")
            errorAlert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.text("mediaStream.device.prompt.title")
        alert.informativeText = L10n.text("mediaStream.device.prompt.message")
        alert.addButton(withTitle: L10n.text("mediaStream.device.prompt.start"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        // A plain button popping a standalone NSMenu (Mixer's source-menu
        // pattern) — NSPopUpButton chokes VoiceOver once submenus are involved.
        let sourceButton = DeviceStreamSourceButton(title: "", target: nil, action: nil)
        sourceButton.bezelStyle = .rounded
        sourceButton.frame = NSRect(x: 0, y: 32, width: 320, height: 26)
        sourceButton.accessibleName = L10n.text("mediaStream.device.prompt.sourceLabel")
        // The browse-for-any-app entry needs the tap backend's wait-and-attach
        // behavior (14.2+); the SCK tier can only capture running apps.
        let allowsApplicationBrowsing: Bool
        if #available(macOS 14.2, *) { allowsApplicationBrowsing = true } else { allowsApplicationBrowsing = false }
        let picker = DeviceStreamSourcePicker(
            button: sourceButton,
            devices: devices,
            applicationSources: applicationSources,
            voiceOverAvailable: voiceOverAvailable,
            allowsApplicationBrowsing: allowsApplicationBrowsing
        )
        let lastSourceToken = preferencesStore.preferences.deviceStreamLastSource
            ?? preferencesStore.preferences.deviceStreamLastDeviceUID.map { "device:\($0)" }
        picker.preselect(
            token: lastSourceToken,
            fallbackDeviceUID: InputAudioDeviceResolver.defaultInputDeviceUID()
        )

        // Off by default on purpose: the source is usually audible locally
        // already, and hearing it back a second time reads as an echo.
        let monitorCheckbox = NSButton(
            checkboxWithTitle: L10n.text("mediaStream.device.prompt.monitor"),
            target: nil,
            action: nil
        )
        monitorCheckbox.state = .off

        // Mute-while-streaming (process taps only, macOS 14.2+): silence the
        // captured app/VoiceOver on this Mac so only the channel hears it.
        // Deliberately never persisted and off by default — accidentally-muted
        // VoiceOver would be catastrophic for a VO user.
        var muteSourceCheckbox: NSButton?
        var accessoryHeight: CGFloat = 62
        if #available(macOS 14.2, *) {
            let checkbox = NSButton(
                checkboxWithTitle: L10n.text("mediaStream.device.prompt.muteSource"),
                target: nil,
                action: nil
            )
            checkbox.state = .off
            muteSourceCheckbox = checkbox
            accessoryHeight = 86
            sourceButton.frame = NSRect(x: 0, y: 56, width: 320, height: 26)
            monitorCheckbox.frame = NSRect(x: 0, y: 28, width: 320, height: 24)
            checkbox.frame = NSRect(x: 0, y: 2, width: 320, height: 24)
            picker.onSelectionChanged = { spec in
                let isProcessSource: Bool
                if case .processes = spec { isProcessSource = true } else { isProcessSource = false }
                checkbox.isEnabled = isProcessSource
                if isProcessSource == false { checkbox.state = .off }
            }
            picker.onSelectionChanged?(picker.selectedSpec)
        } else {
            monitorCheckbox.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: accessoryHeight))
        accessory.addSubview(sourceButton)
        accessory.addSubview(monitorCheckbox)
        if let muteSourceCheckbox { accessory.addSubview(muteSourceCheckbox) }
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = sourceButton

        guard let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else { return }
        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            // `picker` is captured here so it (the submenu items' target)
            // outlives the sheet.
            guard response == .alertFirstButtonReturn, let self else { _ = picker; return }
            guard let spec = picker.selectedSpec else { return }
            self.preferencesStore.mutateDeviceStreamLastSource(spec)
            self.connectionController.startStreamingCaptureSource(
                spec: spec,
                monitorEnabled: monitorCheckbox.state == .on,
                muteSourceOutput: muteSourceCheckbox?.state == .on
            ) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        self?.announceWithVoiceOver(L10n.text("mediaStream.announced.error"))
                        let alert = NSAlert(error: error)
                        alert.runModal()
                    }
                }
            }
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
        guard menuState.mode == .connectedServer else { return }
        if connectedUsersWindowIsKey {
            connectedUsersViewController?.keyShowInfoSelectedUser()
            return
        }
        guard let user = connectedServerViewController?.selectedUserForInfo() else { return }
        openUserInfo(for: user)
    }

    func openUserInfo(for user: ConnectedServerUser) {
        guard menuState.mode == .connectedServer else { return }

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

    func openFeedback() {
        if feedbackWindowController == nil {
            feedbackWindowController = FeedbackWindowController(preferencesStore: preferencesStore)
        }
        feedbackWindowController?.show()
    }


    // MARK: - Updates

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
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
        routeUserAction(
            connectedUsers: { $0.keySetSubscription(option, enabled: enabled) },
            mainWindow: { connectedServerViewController?.setSelectedUsersSubscription(option, enabled: enabled) }
        )
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

    func openConnectedUsers() {
        guard menuState.mode == .connectedServer else { return }
        let vc: ConnectedUsersViewController
        if let existing = connectedUsersViewController {
            vc = existing
        } else {
            vc = ConnectedUsersViewController(serverViewController: connectedServerViewController, appDelegate: self)
            connectedUsersViewController = vc
        }
        if connectedUsersWindowController == nil {
            connectedUsersWindowController = ConnectedUsersWindowController(contentViewController: vc)
        }
        if let session = connectedServerViewController?.session {
            vc.update(users: allConnectedUsers(in: session))
        }
        connectedUsersWindowController?.showWindow(nil)
        connectedUsersWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeConnectedUsersWindow() {
        connectedUsersWindowController?.close()
        connectedUsersWindowController = nil
        connectedUsersViewController = nil
        // The window no longer owns the per-user menu state; let the main outline reclaim it.
        connectedServerViewController?.updateMenuState()
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
            useWebLogin: BearWareWebLogin.isWebLogin(link.username),
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
            useWebLogin: BearWareWebLogin.isWebLogin(link.username),
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
            useWebLogin: BearWareWebLogin.isWebLogin(payload.auth.username),
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
           // Don't auto-restart into a channel that forbids recording.
           connectionController.isRecordingAllowedInCurrentChannel(),
           let folderURL = preferencesStore.resolveRecordingFolderURL() {
            // Restore the mode that was actually in use (single-file, separate, or both);
            // fall back to the preference only if we somehow have no recorded mode.
            let savedMode = preferencesStore.preferences.lastActiveRecordingMode
            let restartMode = savedMode != 0 ? savedMode : preferencesStore.preferences.recordingMode
            startRecordingToFolder(folderURL, mode: restartMode)
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
        if connectedUsersWindowController?.window?.isVisible == true {
            connectedUsersViewController?.update(users: allConnectedUsers(in: session))
        }
        if let userInfoUserID, userInfoWindowController != nil {
            let user = allConnectedUsers(in: session).first(where: { $0.id == userInfoUserID })
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
        closeConnectedUsersWindow()
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

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateMediaStreamingProgress progress: MediaStreamingProgress) {
        menuState.setMediaStreamingActive(progress.isActive)
        connectedServerViewController?.applyMediaStreamingProgress(progress)
    }

    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateVideoDisplay state: VideoDisplayState) {
        connectedServerViewController?.applyVideoDisplay(state)
    }
}

extension AppDelegate: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let includeBeta = MainActor.assumeIsolated {
            preferencesStore.preferences.includeBetaUpdates
        }
        return includeBeta ? ["beta"] : []
    }

    /// Sparkle relaunches the app without preserving `-profile <slug>`. Stash a
    /// one-shot token so the relaunched process can rebind to this profile
    /// instead of falling back to Default. No-op for the default profile.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        ProfileContext.recordPendingHandoff(slug: ProfileContext.current.slug, suppressAutoConnect: false)
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

    /// Every user connected to the server, including those not in any channel
    /// (which have no node in the channel tree). Feeds the Connected Users window.
    func allConnectedUsers(in session: ConnectedServerSession) -> [ConnectedServerUser] {
        flattenedUsers(in: session.rootChannels) + session.usersWithoutChannel
    }
}
/// Selection model for the media-stream source picker. A plain button that
/// pops a standalone NSMenu (devices, VoiceOver, an Application submenu) —
/// the pattern VoiceOver navigates natively, mirroring Mixer's source menus.
/// (An NSPopUpButton with submenus is NOT VoiceOver-navigable: VO announces a
/// "pop up button group" and the submenu items can't be chosen.) Retained by
/// the sheet-completion closure (menu-item targets are weak).
/// Source-picker button, mirroring the Mixer project's `VirtualStripAccessibility`
/// `.picker` role. VoiceOver has to see a POP UP BUTTON carrying the current
/// selection as its value — a plain `NSButton` with `setAccessibilityLabel`/
/// `setAccessibilityValue` reads as "button", exposes no selection, and its menu
/// (the applications submenu especially) doesn't navigate correctly, because the
/// attribute setters can't change the element's ROLE. Overriding the
/// accessibility methods is what does.
private final class DeviceStreamSourceButton: NSButton {
    /// What VoiceOver reads as the control's name (its purpose).
    var accessibleName: String = ""
    /// What VoiceOver reads as its value (the selected source).
    var accessibleValue: String = ""
    /// Step to the next/previous source without opening the menu at all —
    /// Mixer's picker does this, and it keeps the common case off the submenu.
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?

    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }

    override func accessibilityRoleDescription() -> String? {
        // The system's own localized "pop up button" — not a hardcoded string.
        NSAccessibility.Role.popUpButton.description(with: nil)
    }

    override func accessibilityLabel() -> String? { accessibleName }

    override func accessibilityValue() -> Any? { accessibleValue }

    override func accessibilityPerformPress() -> Bool {
        performClick(nil)
        return true
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard let onIncrement else { return false }
        onIncrement()
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard let onDecrement else { return false }
        onDecrement()
        return true
    }
}

private final class DeviceStreamSourcePicker: NSObject {
    private let button: DeviceStreamSourceButton
    private let devices: [InputAudioDeviceInfo]
    private let applicationSources: [DeviceStreamCaptureSpec]
    private let voiceOverAvailable: Bool
    private let allowsApplicationBrowsing: Bool
    /// An application picked via browse that isn't in the running list — kept
    /// so it stays visible (and checkable) in the menu.
    private var browsedApplication: DeviceStreamCaptureSpec?

    private(set) var selectedSpec: DeviceStreamCaptureSpec?
    /// Fired whenever the selected source changes (dialog uses it to enable
    /// the process-source-only mute checkbox).
    var onSelectionChanged: ((DeviceStreamCaptureSpec?) -> Void)?

    init(
        button: DeviceStreamSourceButton,
        devices: [InputAudioDeviceInfo],
        applicationSources: [DeviceStreamCaptureSpec],
        voiceOverAvailable: Bool,
        allowsApplicationBrowsing: Bool
    ) {
        self.button = button
        self.devices = devices
        self.applicationSources = applicationSources
        self.voiceOverAvailable = voiceOverAvailable
        self.allowsApplicationBrowsing = allowsApplicationBrowsing
        super.init()
        button.target = self
        button.action = #selector(showSourceMenu(_:))
        button.onIncrement = { [weak self] in self?.step(by: 1) }
        button.onDecrement = { [weak self] in self?.step(by: -1) }
    }

    /// Every selectable source in menu order, for VoiceOver's increment and
    /// decrement (the "Select Application…" browse entry isn't a source, so it
    /// isn't in here — it stays a menu-only action).
    private var orderedSpecs: [DeviceStreamCaptureSpec] {
        var specs = devices.map { DeviceStreamCaptureSpec.inputDevice($0) }
        if voiceOverAvailable {
            specs.append(.voiceOver())
        }
        specs.append(contentsOf: applicationSources)
        if let browsedApplication, specs.contains(browsedApplication) == false {
            specs.append(browsedApplication)
        }
        return specs
    }

    private func step(by offset: Int) {
        let specs = orderedSpecs
        guard specs.isEmpty == false else { return }
        let current = selectedSpec.flatMap { specs.firstIndex(of: $0) } ?? 0
        let next = min(max(current + offset, 0), specs.count - 1)
        guard next != current else { return }
        applySelection(specs[next])
        NSAccessibility.post(
            element: button,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: specs[next].displayName,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    func preselect(token: String?, fallbackDeviceUID: String?) {
        if let token {
            if token == DeviceStreamCaptureSpec.voiceOverPersistenceToken, voiceOverAvailable {
                applySelection(.voiceOver())
                return
            }
            if token.hasPrefix("app:"),
               let source = applicationSources.first(where: { $0.persistenceToken == token }) {
                applySelection(source)
                return
            }
            if token.hasPrefix("device:") {
                let uid = String(token.dropFirst("device:".count))
                if let device = devices.first(where: { $0.uid == uid }) {
                    applySelection(.inputDevice(device))
                    return
                }
            }
        }
        if let fallbackDeviceUID, let device = devices.first(where: { $0.uid == fallbackDeviceUID }) {
            applySelection(.inputDevice(device))
        } else if let firstDevice = devices.first {
            applySelection(.inputDevice(firstDevice))
        } else if voiceOverAvailable {
            applySelection(.voiceOver())
        } else if let firstApplication = applicationSources.first {
            // No input devices and no capturable VoiceOver (13.0–14.1): without
            // this the picker stays empty and Stream silently does nothing.
            applySelection(firstApplication)
        }
    }

    private func applySelection(_ spec: DeviceStreamCaptureSpec) {
        selectedSpec = spec
        button.title = spec.displayName
        button.accessibleValue = spec.displayName
        onSelectionChanged?(spec)
    }

    @objc private func showSourceMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for device in devices {
            let spec = DeviceStreamCaptureSpec.inputDevice(device)
            menu.addItem(makeSourceItem(for: spec))
        }

        let showApplicationMenu = applicationSources.isEmpty == false || allowsApplicationBrowsing
        if voiceOverAvailable || showApplicationMenu {
            if devices.isEmpty == false {
                menu.addItem(.separator())
            }
            if voiceOverAvailable {
                menu.addItem(makeSourceItem(for: .voiceOver()))
            }
            if showApplicationMenu {
                let submenu = NSMenu(title: L10n.text("mediaStream.device.source.applicationMenu"))
                var submenuSources = applicationSources
                if let browsedApplication, submenuSources.contains(browsedApplication) == false {
                    submenuSources.append(browsedApplication)
                }
                for source in submenuSources {
                    submenu.addItem(makeSourceItem(for: source))
                }
                if allowsApplicationBrowsing {
                    // Browse for ANY installed app (running or not): the tap
                    // backend waits for it and attaches when it plays audio.
                    if submenuSources.isEmpty == false {
                        submenu.addItem(.separator())
                    }
                    let browseItem = NSMenuItem(
                        title: L10n.text("mediaStream.device.source.chooseApplication"),
                        action: #selector(browseForApplication(_:)),
                        keyEquivalent: ""
                    )
                    browseItem.target = self
                    submenu.addItem(browseItem)
                }
                let parent = NSMenuItem(
                    title: L10n.text("mediaStream.device.source.applicationMenu"),
                    action: nil,
                    keyEquivalent: ""
                )
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    private func makeSourceItem(for spec: DeviceStreamCaptureSpec) -> NSMenuItem {
        let item = NSMenuItem(title: spec.displayName, action: #selector(selectSource(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = spec
        item.state = spec == selectedSpec ? .on : .off
        return item
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? DeviceStreamCaptureSpec else { return }
        applySelection(spec)
    }

    /// "Select Application…": browse for any installed .app (running or not —
    /// the tap backend waits for it) and use its bundle identifier.
    @objc private func browseForApplication(_ sender: NSMenuItem) {
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
        let spec = DeviceStreamCaptureSpec.application(bundleID: bundleID, displayName: name)
        browsedApplication = spec
        applySelection(spec)
    }
}
