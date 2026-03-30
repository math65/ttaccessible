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

            CommandGroup(replacing: .newItem) {
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

                    Button(L10n.text("savedServers.menu.exportTT")) {
                        appDelegate.exportSelectedSavedServerTTFile()
                    }
                    .disabled(menuState.hasSelection == false)

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

                    Button(L10n.text("connectedServer.identity.status.menu")) {
                        appDelegate.changeStatus()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), modifiers: [])

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

                    Divider()

                    Button(L10n.text("accounts.menu.open")) {
                        appDelegate.openUserAccounts()
                    }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer || menuState.isAdministrator == false)

                    Button(L10n.text("bans.menu.open")) {
                        appDelegate.openBannedUsers()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(menuState.mode != .connectedServer || menuState.isAdministrator == false)

                    Button(L10n.text("serverProperties.menu.open")) {
                        appDelegate.openServerProperties()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
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

                    Button(L10n.text("connectedServer.menu.disconnect")) {
                        appDelegate.disconnectServer()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: [])
                }
            }

            if menuState.mode == .connectedServer {
                CommandMenu(L10n.text("user.menu.title")) {
                    Button(L10n.text("user.menu.info")) {
                        appDelegate.openSelectedUserInfo()
                    }
                    .disabled(menuState.hasSingleSelectedUser == false)

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
}
