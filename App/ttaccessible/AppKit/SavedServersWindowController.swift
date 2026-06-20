//
//  SavedServersWindowController.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit
import Combine

final class SavedServersWindowController: NSWindowController {
    private let menuState = SavedServersMenuState.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentToolbarMode: SavedServersMenuState.Mode = .savedServers

    init(contentViewController: NSViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ProfileContext.current.decorateWindowTitle(L10n.text("savedServers.window.title"))
        window.center()
        window.minSize = NSSize(width: 680, height: 420)
        window.setFrameAutosaveName("SavedServersWindow")
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentViewController = contentViewController

        super.init(window: window)
        shouldCascadeWindows = false

        installToolbar(on: window)
        observeMenuState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "SavedServersToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        currentToolbarMode = menuState.mode
    }

    private func observeMenuState() {
        // @Published emits via willSet, so re-reading menuState here returns the OLD
        // value. Defer with .receive(on:) so the property is up-to-date when we read.
        menuState.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMode in
                self?.rebuildToolbarItemsIfNeeded(for: newMode)
                self?.refreshToolbarItems()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            menuState.$hasSelection.map { _ in () }.eraseToAnyPublisher(),
            menuState.$isMasterMuted.map { _ in () }.eraseToAnyPublisher(),
            menuState.$isRecordingActive.map { _ in () }.eraseToAnyPublisher(),
            menuState.$isHearMyselfEnabled.map { _ in () }.eraseToAnyPublisher(),
            menuState.$isInChannel.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.refreshToolbarItems()
        }
        .store(in: &cancellables)
    }

    private func rebuildToolbarItemsIfNeeded(for newMode: SavedServersMenuState.Mode) {
        guard currentToolbarMode != newMode, let toolbar = window?.toolbar else {
            return
        }
        currentToolbarMode = newMode

        while toolbar.items.isEmpty == false {
            toolbar.removeItem(at: 0)
        }
        for (index, identifier) in defaultIdentifiers(for: newMode).enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    private func refreshToolbarItems() {
        guard let items = window?.toolbar?.items else { return }
        for item in items {
            switch item.itemIdentifier {
            case .ttConnect:
                item.isEnabled = menuState.hasSelection
            case .ttNewServer:
                item.isEnabled = menuState.mode == .savedServers
            case .ttEditServer:
                item.isEnabled = menuState.mode == .savedServers && menuState.hasSelection
            case .ttDisconnect:
                item.isEnabled = menuState.mode == .connectedServer
            case .ttMicrophone:
                item.isEnabled = menuState.mode == .connectedServer && menuState.isInChannel
            case .ttMasterMute:
                let muted = menuState.isMasterMuted
                item.label = L10n.text(muted ? "toolbar.unmute" : "toolbar.mute")
                item.paletteLabel = item.label
                item.toolTip = L10n.text(muted ? "toolbar.unmute.tooltip" : "toolbar.mute.tooltip")
                item.image = NSImage(
                    systemSymbolName: muted ? "speaker.slash.fill" : "speaker.wave.2",
                    accessibilityDescription: item.label
                )
                item.isEnabled = menuState.mode == .connectedServer
            case .ttRecording:
                let recording = menuState.isRecordingActive
                item.label = L10n.text(recording ? "toolbar.recording.stop" : "toolbar.recording.start")
                item.paletteLabel = item.label
                item.toolTip = L10n.text(recording ? "toolbar.recording.stop.tooltip" : "toolbar.recording.start.tooltip")
                item.image = NSImage(
                    systemSymbolName: recording ? "stop.circle.fill" : "record.circle",
                    accessibilityDescription: item.label
                )
                item.isEnabled = menuState.mode == .connectedServer && (recording || menuState.isInChannel)
            case .ttHearMyself:
                // Mirror the Mute/Recording pattern: VoiceOver reads the toolbar
                // item's label, so swap it to include "selected" when hearing-myself
                // is on (plain label when off). Stays an ordinary button.
                let on = menuState.isHearMyselfEnabled
                item.label = L10n.text(on ? "toolbar.hearMyself.selected" : "toolbar.hearMyself")
                item.paletteLabel = item.label
                item.image = NSImage(systemSymbolName: "ear", accessibilityDescription: item.label)
                item.isEnabled = menuState.mode == .connectedServer && menuState.isInChannel
            case .ttPreferences:
                item.isEnabled = true
            default:
                break
            }
        }
    }

    private func defaultIdentifiers(for mode: SavedServersMenuState.Mode) -> [NSToolbarItem.Identifier] {
        switch mode {
        case .savedServers:
            return [.ttConnect, .ttNewServer, .ttEditServer, .flexibleSpace, .ttPreferences]
        case .connectedServer:
            return [.ttMicrophone, .ttMasterMute, .ttRecording, .ttHearMyself, .flexibleSpace, .ttDisconnect, .ttPreferences]
        }
    }

    // SwiftUI's @NSApplicationDelegateAdaptor wraps the delegate, so
    // `NSApp.delegate as? AppDelegate` can fail; scan window delegates as a fallback.
    private var appDelegate: AppDelegate? {
        if let direct = NSApp.delegate as? AppDelegate {
            return direct
        }
        for window in NSApp.windows {
            if let candidate = window.delegate as? AppDelegate {
                return candidate
            }
        }
        return nil
    }

    @objc fileprivate func toolbarConnectAction(_ sender: Any?) {
        appDelegate?.connectSelectedSavedServer()
    }

    @objc fileprivate func toolbarDisconnectAction(_ sender: Any?) {
        appDelegate?.disconnectServer()
    }

    @objc fileprivate func toolbarNewServerAction(_ sender: Any?) {
        appDelegate?.addSavedServer()
    }

    @objc fileprivate func toolbarEditServerAction(_ sender: Any?) {
        appDelegate?.editSelectedSavedServer()
    }

    @objc fileprivate func toolbarPreferencesAction(_ sender: Any?) {
        appDelegate?.openPreferences()
    }

    @objc fileprivate func toolbarMicrophoneAction(_ sender: Any?) {
        appDelegate?.toggleMicrophone()
    }

    @objc fileprivate func toolbarMasterMuteAction(_ sender: Any?) {
        appDelegate?.toggleMasterMute()
    }

    @objc fileprivate func toolbarRecordingAction(_ sender: Any?) {
        appDelegate?.toggleRecording()
    }

    @objc fileprivate func toolbarHearMyselfAction(_ sender: Any?) {
        appDelegate?.toggleHearMyself()
    }
}

extension SavedServersWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        defaultIdentifiers(for: menuState.mode)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .ttConnect, .ttDisconnect, .ttNewServer, .ttEditServer,
            .ttMicrophone, .ttMasterMute, .ttRecording, .ttHearMyself,
            .ttPreferences,
            .flexibleSpace, .space,
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .ttConnect:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.connect",
                tooltipKey: "toolbar.connect.tooltip",
                symbolName: "bolt.horizontal",
                action: #selector(toolbarConnectAction(_:))
            )
        case .ttDisconnect:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.disconnect",
                tooltipKey: "toolbar.disconnect.tooltip",
                symbolName: "bolt.horizontal.fill",
                action: #selector(toolbarDisconnectAction(_:))
            )
        case .ttNewServer:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.newServer",
                tooltipKey: "toolbar.newServer.tooltip",
                symbolName: "plus",
                action: #selector(toolbarNewServerAction(_:))
            )
        case .ttEditServer:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.editServer",
                tooltipKey: "toolbar.editServer.tooltip",
                symbolName: "pencil",
                action: #selector(toolbarEditServerAction(_:))
            )
        case .ttMicrophone:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.microphone",
                tooltipKey: "toolbar.microphone.tooltip",
                symbolName: "mic",
                action: #selector(toolbarMicrophoneAction(_:))
            )
        case .ttMasterMute:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.mute",
                tooltipKey: "toolbar.mute.tooltip",
                symbolName: "speaker.wave.2",
                action: #selector(toolbarMasterMuteAction(_:))
            )
        case .ttRecording:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.recording.start",
                tooltipKey: "toolbar.recording.start.tooltip",
                symbolName: "record.circle",
                action: #selector(toolbarRecordingAction(_:))
            )
        case .ttHearMyself:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.hearMyself",
                tooltipKey: "toolbar.hearMyself.tooltip",
                symbolName: "ear",
                action: #selector(toolbarHearMyselfAction(_:))
            )
        case .ttPreferences:
            return makeToolbarItem(
                identifier: itemIdentifier,
                labelKey: "toolbar.preferences",
                tooltipKey: "toolbar.preferences.tooltip",
                symbolName: "gearshape",
                action: #selector(toolbarPreferencesAction(_:))
            )
        default:
            return nil
        }
    }

    private func makeToolbarItem(
        identifier: NSToolbarItem.Identifier,
        labelKey: String,
        tooltipKey: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let label = L10n.text(labelKey)
        item.label = label
        item.paletteLabel = label
        item.toolTip = L10n.text(tooltipKey)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let ttConnect = NSToolbarItem.Identifier("ttaccessible.toolbar.connect")
    static let ttDisconnect = NSToolbarItem.Identifier("ttaccessible.toolbar.disconnect")
    static let ttNewServer = NSToolbarItem.Identifier("ttaccessible.toolbar.newServer")
    static let ttEditServer = NSToolbarItem.Identifier("ttaccessible.toolbar.editServer")
    static let ttMicrophone = NSToolbarItem.Identifier("ttaccessible.toolbar.microphone")
    static let ttMasterMute = NSToolbarItem.Identifier("ttaccessible.toolbar.masterMute")
    static let ttRecording = NSToolbarItem.Identifier("ttaccessible.toolbar.recording")
    static let ttHearMyself = NSToolbarItem.Identifier("ttaccessible.toolbar.hearMyself")
    static let ttPreferences = NSToolbarItem.Identifier("ttaccessible.toolbar.preferences")
}
