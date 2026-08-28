//
//  ttaccessibleApp.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AppKit
import SwiftUI

@main
struct ttaccessibleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var menuState = SavedServersMenuState.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("preferences.menu.title")) {
                    appDelegate.openPreferences()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(after: .appInfo) {
                Button(L10n.text("update.menu.checkForUpdates")) {
                    appDelegate.checkForUpdates()
                }

                Divider()

                Button(L10n.text("profile.menu.newInstance")) {
                    appDelegate.openProfilesWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button(L10n.text("profile.menu.manage")) {
                    appDelegate.openProfilesWindow()
                }
            }

            // `replacing` rather than `after`: SwiftUI's own "<App> Help" item is
            // titled from the system language, which would read English in a
            // French UI when the language preference overrides the system.
            CommandGroup(replacing: .help) {
                Button(L10n.text("help.menu.userGuide")) {
                    HelpBook.open()
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                Button(L10n.text("help.menu.viewOnGitHub")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/math65/ttaccessible")!)
                }
                Button(L10n.text("help.menu.reportIssue")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/math65/ttaccessible/issues/new/choose")!)
                }
                if AppBackendClient.isConfigured {
                    Button(L10n.text("help.menu.contactDeveloper")) {
                        appDelegate.openFeedback()
                    }
                }
            }

            CommandGroup(replacing: .newItem) {
            }

            // Quit is normally AppKit's to add, and on current macOS it is there
            // without asking. On macOS 12 it is not: an app whose only Scene is
            // `Settings` gets an app menu without it, leaving the Dock or a force
            // quit as the only ways out. Declaring it here puts it in the menu
            // SwiftUI builds — on every system, at the placement AppKit would
            // have used — instead of repairing a built menu afterwards, which is
            // timing-dependent (SwiftUI rebuilds the menu whenever the state the
            // commands observe changes). AppDelegate still repairs the menu, as
            // the safety net for a system where even this doesn't land.
            CommandGroup(replacing: .appTermination) {
                Button(L10n.format("app.menu.quit", Self.appDisplayName)) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }

            // Same macOS 12 hole, same cure as Quit above. A field report showed
            // the AppKit-side repair being wiped: it inserts these items, then
            // SwiftUI rebuilds the app menu and takes them with it — the Edit
            // menu survives that report because it is a top-level menu SwiftUI
            // doesn't own. Declared here, they belong to the menu's own
            // construction and survive every rebuild.
            CommandGroup(replacing: .appVisibility) {
                Button(L10n.format("app.menu.hide", Self.appDisplayName)) {
                    NSApp.hide(nil)
                }
                .keyboardShortcut("h", modifiers: [.command])
                Button(L10n.text("app.menu.hideOthers")) {
                    NSApp.hideOtherApplications(nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
                Button(L10n.text("app.menu.showAll")) {
                    NSApp.unhideAllApplications(nil)
                }
            }

            // Services is a submenu, not a button — and it only fills once the
            // NSMenu behind it is handed to NSApp.servicesMenu, which SwiftUI
            // gives no way to do. AppDelegate's repair pass wires it after the
            // menu is built (and re-wires it after every rebuild).
            CommandGroup(replacing: .systemServices) {
                Menu(L10n.text("app.menu.services")) {}
            }

            CommandMenu(L10n.text("savedServers.menu.title")) {
                if menuState.mode == .savedServers {
                    Button(L10n.text("savedServers.menu.new")) {
                        appDelegate.addSavedServer()
                    }
                    .keyboardShortcut("n", modifiers: [.command])

                    Button(L10n.text("savedServers.menu.connect")) {
                        appDelegate.connectSelectedSavedServer()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: [])
                    .disabled(menuState.hasSelection == false)

                    Button(L10n.text("savedServers.menu.import")) {
                        appDelegate.importTeamTalkServers()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])

                    Button(L10n.text("serverExport.menu.title")) {
                        appDelegate.exportServer()
                    }
                    .disabled(menuState.hasSelection == false)

                    Button(L10n.text("savedServers.menu.exportList")) {
                        appDelegate.exportServerList()
                    }

                    Divider()

                    Button(L10n.text("savedServers.menu.edit")) {
                        appDelegate.editSelectedSavedServer()
                    }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(menuState.hasSelection == false)

                    Button(L10n.text("savedServers.menu.delete")) {
                        appDelegate.deleteSelectedSavedServer()
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(menuState.hasSelection == false)
                } else {
                    Button(L10n.text("connectedServer.identity.nickname.menu")) {
                        appDelegate.changeNickname()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)), modifiers: [])
                    .disabled(menuState.isNicknameLocked)

                    Button(L10n.text("connectedServer.identity.status.menu")) {
                        appDelegate.changeStatus()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [])
                    .disabled(menuState.isStatusLocked)

                    Divider()

                    Button(L10n.text("privateMessages.menu.open")) {
                        appDelegate.openMessages()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button(L10n.text("files.menu.open")) {
                        appDelegate.openChannelFiles()
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(menuState.isInChannel == false)

                    Button(L10n.text("files.menu.upload")) {
                        appDelegate.uploadFile()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)), modifiers: [.shift])
                    .disabled(menuState.isInChannel == false)

                    Divider()

                    Button(L10n.text("connectedServer.menu.createChannel")) {
                        appDelegate.createChannel()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), modifiers: [])
                    .disabled(menuState.hasSelectedChannel == false && menuState.isInChannel == false)

                    Button(L10n.text("connectedServer.menu.editChannel")) {
                        appDelegate.updateChannel()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), modifiers: [.shift])
                    .disabled(menuState.hasSelectedChannel == false)

                    Button(L10n.text("connectedServer.menu.deleteChannel")) {
                        appDelegate.deleteChannel()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey)!)), modifiers: [])
                    .disabled(menuState.hasSelectedChannel == false)

                    Divider()

                    Button(L10n.text("connectedUsers.menu.open")) {
                        appDelegate.openConnectedUsers()
                    }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer)

                    Button(L10n.text("accounts.menu.open")) {
                        appDelegate.openUserAccounts()
                    }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer || menuState.isAdministrator == false)

                    Button(L10n.text("bans.menu.open")) {
                        appDelegate.openBannedUsers()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    // Listing bans needs USERRIGHT_BAN_USERS, not an admin account.
                    .disabled(menuState.mode != .connectedServer || menuState.canBanUsers == false)

                    Button(L10n.text("serverProperties.menu.open")) {
                        appDelegate.openServerProperties()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer || menuState.isAdministrator == false)

                    Button(L10n.text("serverConfig.menu.save")) {
                        appDelegate.saveServerConfig()
                    }
                    .disabled(menuState.mode != .connectedServer || menuState.isAdministrator == false)

                    Button(L10n.text("stats.menu.open")) {
                        appDelegate.openStats()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer)

                    Divider()

                    Button(L10n.text("broadcast.menu.send")) {
                        appDelegate.broadcastMessage()
                    }
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(menuState.mode != .connectedServer || menuState.canSendBroadcast == false)

                    Divider()

                    Button(L10n.text("connectedServer.serverLink.copy")) {
                        appDelegate.copyServerLink()
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                    Button(L10n.text("serverExport.menu.title")) {
                        appDelegate.exportServer()
                    }

                    Divider()

                    Button(L10n.text("connectedServer.menu.disconnect")) {
                        appDelegate.disconnectServer()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: [])
                }
            }

            // The mode condition lives INSIDE the menu (ViewBuilder), not around
            // it: CommandsBuilder has no `if` before macOS 13, and SwiftUI omits
            // a CommandMenu whose content is empty, so this renders identically.
            CommandMenu(L10n.text("user.menu.title")) {
                if menuState.mode == .connectedServer {
                    Button(L10n.text("user.menu.info")) {
                        appDelegate.openSelectedUserInfo()
                    }
                    .keyboardShortcut("i", modifiers: [.command])
                    .disabled(menuState.hasSingleSelectedUser == false)

                    Button(menuState.isSelectedUserMuted
                           ? L10n.text("user.menu.unmute")
                           : L10n.text("user.menu.mute")) {
                        appDelegate.toggleMuteSelectedUser()
                    }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(menuState.hasSingleSelectedOtherUser == false)

                    Button(menuState.isSelectedUserMediaFileMuted
                           ? L10n.text("user.menu.unmuteMediaFile")
                           : L10n.text("user.menu.muteMediaFile")) {
                        appDelegate.toggleMuteSelectedUserMediaFile()
                    }
                    .keyboardShortcut("m", modifiers: [.command, .control, .shift])
                    .disabled(menuState.hasSingleSelectedOtherUser == false)

                    Button(L10n.text("user.menu.volume")) {
                        appDelegate.adjustSelectedUserVolume()
                    }
                    .keyboardShortcut("u", modifiers: [.command])
                    .disabled(menuState.hasSingleSelectedUser == false)

                    Button(menuState.isSelectedUserChannelOperator
                           ? L10n.text("user.menu.revokeOperator")
                           : L10n.text("user.menu.makeOperator")) {
                        appDelegate.toggleChannelOperator()
                    }
                    .keyboardShortcut("o", modifiers: [.control, .command])
                    .disabled(menuState.hasSingleSelectedOtherUser == false)

                    Divider()

                    Button(L10n.text("user.menu.kick")) {
                        appDelegate.kickSelectedUser()
                    }
                    .keyboardShortcut("k", modifiers: [.command])
                    .disabled(menuState.hasSingleSelectedOtherUser == false)

                    Button(L10n.text("user.menu.kickServer")) {
                        appDelegate.kickSelectedUserFromServer()
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(menuState.hasSingleSelectedOtherUser == false || menuState.canKickUsers == false)

                    Button(L10n.text("user.menu.kickBan")) {
                        appDelegate.kickBanSelectedUser()
                    }
                    .disabled(menuState.hasSingleSelectedOtherUser == false || menuState.canBanUsers == false)

                    Button(L10n.text("user.menu.move")) {
                        appDelegate.moveSelectedUser()
                    }
                    .keyboardShortcut("x", modifiers: [.command, .option])
                    .disabled(menuState.hasSingleSelectedOtherUser == false)

                    Divider()

                    Menu(L10n.text("user.menu.subscriptions")) {
                        ForEach(UserSubscriptionOption.regularCases, id: \.self) { option in
                            Toggle(
                                L10n.text(option.localizationKey),
                                isOn: Binding(
                                    get: { menuState.isSelectedUsersSubscriptionEnabled(option) },
                                    set: { appDelegate.setSelectedUsersSubscription(option, enabled: $0) }
                                )
                            )
                            .keyboardShortcut(option.shortcutKey, modifiers: option.shortcutModifiers)
                            .disabled(menuState.hasSelectedUsers == false)
                        }

                        Divider()

                        ForEach(UserSubscriptionOption.interceptCases, id: \.self) { option in
                            Toggle(
                                L10n.text(option.localizationKey),
                                isOn: Binding(
                                    get: { menuState.isSelectedUsersSubscriptionEnabled(option) },
                                    set: { appDelegate.setSelectedUsersSubscription(option, enabled: $0) }
                                )
                            )
                            .keyboardShortcut(option.shortcutKey, modifiers: option.shortcutModifiers)
                            .disabled(menuState.hasSelectedUsers == false)
                        }
                    }
                    .disabled(menuState.hasSelectedUsers == false)
                }
            }

            CommandMenu(L10n.text("shortcuts.menu.title")) {

                Button(L10n.text("shortcuts.focus.primary")) {
                    appDelegate.focusPrimaryArea()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button(L10n.text("shortcuts.focus.secondary")) {
                    appDelegate.focusSecondaryArea()
                }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer)

                Button(L10n.text("shortcuts.focus.message")) {
                    appDelegate.focusMessageArea()
                }
                .keyboardShortcut("3", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                Button(L10n.text("shortcuts.focus.history")) {
                    appDelegate.focusHistoryArea()
                }
                .keyboardShortcut("4", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer)

                Button(L10n.text("mixer.menu.open")) {
                    appDelegate.focusChannelMixerArea()
                }
                .keyboardShortcut("5", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                Divider()

                Button(L10n.text("connectedServer.menu.join")) {
                    appDelegate.joinSelectedChannel()
                }
                .keyboardShortcut("j", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer || menuState.hasSelectedChannel == false)

                Button(L10n.text("connectedServer.menu.leave")) {
                    appDelegate.leaveCurrentChannel()
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                Button(L10n.text("shortcuts.messages")) {
                    appDelegate.openMessages()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                Button(L10n.text("shortcuts.microphone")) {
                    appDelegate.toggleMicrophone()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                Button(menuState.isMasterMuted
                       ? L10n.text("shortcuts.masterUnmute")
                       : L10n.text("shortcuts.masterMute")) {
                    appDelegate.toggleMasterMute()
                }
                .keyboardShortcut("m", modifiers: [.command])
                .disabled(menuState.mode != .connectedServer)

                // While recording, show a single Stop item (⌘R). When idle, show the two
                // start options: ⌘R single file, ⌘⇧R the preference mode (separate/both).
                if menuState.isRecordingActive {
                    Button(L10n.text("shortcuts.recording.stop")) {
                        appDelegate.toggleRecording()
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(menuState.mode != .connectedServer)
                } else {
                    Button(L10n.text("shortcuts.recording.startSingle")) {
                        appDelegate.toggleRecording(mode: 1)
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                    Button(L10n.text("shortcuts.recording.startPreferred")) {
                        appDelegate.toggleRecording()
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)
                }

                Divider()

                Button(L10n.text("shortcuts.mediaStream.startFile")) {
                    appDelegate.startStreamingMediaFromFile()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(menuState.mode != .connectedServer || menuState.isMediaStreamingActive || menuState.isInChannel == false)

                Button(L10n.text("shortcuts.mediaStream.startURL")) {
                    appDelegate.startStreamingMediaFromURL()
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(menuState.mode != .connectedServer || menuState.isMediaStreamingActive || menuState.isInChannel == false)

                Button(L10n.text("shortcuts.mediaStream.startDevice")) {
                    appDelegate.startStreamingMediaFromDevice()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(menuState.mode != .connectedServer || menuState.isMediaStreamingActive || menuState.isInChannel == false)

                // A live capture can't be paused — the broadcast stays up and
                // goes silent — so it gets mute wording, not pause wording.
                Button(mediaStreamPauseTitle(menuState)) {
                    appDelegate.toggleMediaStreamingPause()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(menuState.mode != .connectedServer || !menuState.isMediaStreamingActive)

                Button(L10n.text("shortcuts.mediaStream.stop")) {
                    appDelegate.stopMediaStreaming()
                }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(menuState.mode != .connectedServer || !menuState.isMediaStreamingActive)

                Button(L10n.text("shortcuts.hearMyself")) {
                    appDelegate.toggleHearMyself()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)

                Button(L10n.text("shortcuts.announceAudio")) {
                    appDelegate.announceAudioState()
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF9FunctionKey)!)), modifiers: [])
                .disabled(menuState.mode != .connectedServer)

                Divider()

                Button(L10n.text("shortcuts.exportChat")) {
                    appDelegate.exportChat()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(menuState.mode != .connectedServer || menuState.isInChannel == false)
            }
        }
    }

    /// The name AppKit itself puts in the app menu's title.
    private static let appDisplayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "tt-Accessible"

    private func mediaStreamPauseTitle(_ menuState: SavedServersMenuState) -> String {
        if menuState.isMediaStreamingLive {
            return menuState.isMediaStreamingPaused
                ? L10n.text("shortcuts.mediaStream.unmute")
                : L10n.text("shortcuts.mediaStream.mute")
        }
        return menuState.isMediaStreamingPaused
            ? L10n.text("shortcuts.mediaStream.resume")
            : L10n.text("shortcuts.mediaStream.pause")
    }
}
