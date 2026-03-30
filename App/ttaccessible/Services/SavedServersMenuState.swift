//
//  SavedServersMenuState.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import Combine
import Foundation

@MainActor
final class SavedServersMenuState: ObservableObject {
    enum Mode {
        case savedServers
        case connectedServer
    }

    static let shared = SavedServersMenuState()

    @Published private(set) var hasSelection = false
    @Published private(set) var mode: Mode = .savedServers
    @Published private(set) var hasSelectedChannel = false
    @Published private(set) var isInChannel = false
    @Published private(set) var isAdministrator = false
    @Published private(set) var canSendBroadcast = false
    @Published private(set) var hasSelectedUsers = false
    @Published private(set) var hasSingleSelectedUser = false
    @Published private(set) var selectedUserSubscriptionStates: [UserSubscriptionOption: Bool] = [:]

    private init() {
    }

    func setHasSelection(_ hasSelection: Bool) {
        if self.hasSelection != hasSelection {
            self.hasSelection = hasSelection
        }
    }

    func setMode(_ mode: Mode) {
        if self.mode != mode {
            self.mode = mode
        }
    }

    func setConnectedState(hasSelectedChannel: Bool, isInChannel: Bool) {
        if self.hasSelectedChannel != hasSelectedChannel {
            self.hasSelectedChannel = hasSelectedChannel
        }

        if self.isInChannel != isInChannel {
            self.isInChannel = isInChannel
        }
    }

    func resetConnectedTransientState() {
        setCanSendBroadcast(false)
        setSelectedUsersState(hasSelectedUsers: false, hasSingleSelectedUser: false, states: [:])
    }

    func setAdministrator(_ value: Bool) {
        if isAdministrator != value { isAdministrator = value }
    }

    func setCanSendBroadcast(_ value: Bool) {
        if canSendBroadcast != value { canSendBroadcast = value }
    }

    func setSelectedUsersState(hasSelectedUsers: Bool, hasSingleSelectedUser: Bool, states: [UserSubscriptionOption: Bool]) {
        if self.hasSelectedUsers != hasSelectedUsers {
            self.hasSelectedUsers = hasSelectedUsers
        }
        if self.hasSingleSelectedUser != hasSingleSelectedUser {
            self.hasSingleSelectedUser = hasSingleSelectedUser
        }
        if self.selectedUserSubscriptionStates != states {
            self.selectedUserSubscriptionStates = states
        }
    }

    func isSelectedUsersSubscriptionEnabled(_ option: UserSubscriptionOption) -> Bool {
        selectedUserSubscriptionStates[option] ?? false
    }
}
