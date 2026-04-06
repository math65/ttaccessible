//
//  AppDelegate.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        connectionController.delegate = self
        UNUserNotificationCenter.current().delegate = self
        audioDeviceChangeMonitor.startListening()
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
        savedServersViewController?.importTeamTalkServers(nil)
    }

    func connectSelectedSavedServer() {
        guard menuState.mode == .savedServers else {
            return
        }

        showSavedServersWindow()
        savedServersViewController?.connectSelectedServer()
    }

    func exportSelectedSavedServerTTFile() {
        guard menuState.mode == .savedServers, menuState.hasSelection else {
            return
        }

        showSavedServersWindow()
        savedServersViewController?.exportSelectedTTFile(nil)
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

    func toggleMuteSelectedUser() {
        guard menuState.mode == .connectedServer else { return }
        restoreMainWindow()
        connectedServerViewController?.toggleMuteUserAction()
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
        guard let host = url.host, host.isEmpty == false else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems ?? []

        func param(_ name: String) -> String {
            params.first(where: { $0.name == name })?.value ?? ""
        }

        let tcpPort = Int(param("tcpport")) ?? 10333
        let udpPort = Int(param("udpport")) ?? tcpPort
        let encrypted = param("encrypted") == "true" || param("encrypted") == "1"
        let username = param("username")
        let password = param("password")
        let channel = param("channel")
        let chanPassword = param("chanpasswd")

        let draft = SavedServerDraft(
            name: host,
            host: host,
            tcpPort: String(tcpPort),
            udpPort: String(udpPort),
            encrypted: encrypted,
            nickname: preferencesStore.preferences.defaultNickname,
            username: username,
            password: password,
            initialChannelPath: channel,
            initialChannelPassword: chanPassword
        )

        let editor = SavedServerEditorWindowController(mode: .add, draft: draft, parentWindow: nil)
        guard let result = editor.runModal(), let record = result.makeRecord(id: UUID()) else { return }

        if connectionController.sessionSnapshot != nil {
            let alert = NSAlert()
            alert.messageText = L10n.text("ttFile.alert.connected.title")
            alert.informativeText = L10n.format("ttFile.alert.connected.message", record.host)
            alert.addButton(withTitle: L10n.text("ttFile.alert.connected.confirm"))
            alert.addButton(withTitle: L10n.text("ttFile.alert.connected.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            connectionController.disconnect()
        }

        let options = TeamTalkConnectOptions(
            nicknameOverride: nil,
            statusMessage: nil,
            genderOverride: nil,
            initialChannelPath: result.sanitizedInitialChannelPath.isEmpty ? nil : result.sanitizedInitialChannelPath,
            initialChannelPassword: result.initialChannelPassword,
            preferJoinLastChannelFromServer: false
        )
        connectionController.connect(to: record, password: result.password, options: options) { [weak self] result in
            if case .failure(let error) = result {
                self?.presentErrorAlert(
                    title: L10n.text("ttFile.alert.connectionError.title"),
                    message: error.localizedDescription
                )
            }
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
            initialChannelPath: "",
            initialChannelPassword: ""
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
                break
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
    // Permet l'affichage des notifications même quand l'app est au premier plan
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
