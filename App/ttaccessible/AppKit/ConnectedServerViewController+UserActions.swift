//
//  ConnectedServerViewController+UserActions.swift
//  ttaccessible
//

import AppKit

extension ConnectedServerViewController {
    @objc func adjustUserVolume(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              let window = view.window else { return }

        let volDefault = Double(SOUND_VOLUME_DEFAULT.rawValue)
        let storedVolume = connectionController.userVolumeStore.volume(forUsername: user.username)
        let effectiveVolume = storedVolume ?? user.volumeVoice
        let currentPercent = Int(Double(effectiveVolume) / volDefault * 100)

        let alert = NSAlert()
        alert.messageText = L10n.format("connectedServer.volume.title", user.displayName)
        alert.informativeText = L10n.text("connectedServer.volume.info")
        alert.addButton(withTitle: L10n.text("connectedServer.volume.ok"))
        alert.addButton(withTitle: L10n.text("connectedServer.volume.cancel"))

        let slider = NSSlider(value: Double(currentPercent), minValue: 0, maxValue: 200, target: nil, action: nil)
        slider.numberOfTickMarks = 0
        slider.isContinuous = true
        slider.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        slider.setAccessibilityLabel(L10n.text("connectedServer.volume.sliderLabel"))
        alert.accessoryView = slider
        alert.window.initialFirstResponder = slider

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let percent = Int(slider.doubleValue)
            let raw = Int32(Double(percent) / 100.0 * Double(SOUND_VOLUME_DEFAULT.rawValue))
            let clamped = max(Int32(SOUND_VOLUME_MIN.rawValue), min(Int32(SOUND_VOLUME_MAX.rawValue), raw))
            self.connectionController.setUserVoiceVolume(userID: user.id, username: user.username, volume: clamped)
        }
    }

    @objc func toggleMuteUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode, !user.isCurrentUser else { return }
        connectionController.muteUser(userID: user.id, mute: !user.isMuted)
    }

    @objc func kickUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              !user.isCurrentUser,
              let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.format("connectedServer.kick.title", user.displayName)
        alert.informativeText = L10n.text("connectedServer.kick.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("connectedServer.kick.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.connectionController.kickUser(userID: user.id, channelID: user.channelID) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
        }
    }

    @objc func kickBanUserAction(_ sender: Any? = nil) {
        guard case .user(let user)? = selectedNode,
              !user.isCurrentUser,
              let window = view.window else { return }

        let alert = NSAlert()
        alert.messageText = L10n.format("bans.kickban.title", user.displayName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("bans.kickban.byIP"))
        alert.addButton(withTitle: L10n.text("bans.kickban.byUsername"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            let banTypes: UInt32
            switch response {
            case .alertFirstButtonReturn:
                banTypes = UInt32(BANTYPE_IPADDR.rawValue)
            case .alertSecondButtonReturn:
                banTypes = UInt32(BANTYPE_USERNAME.rawValue)
            default:
                return
            }
            self.connectionController.kickAndBanUser(userID: user.id, banTypes: banTypes) { [weak self] result in
                if case .failure(let error) = result {
                    self?.presentError(error)
                }
            }
        }
    }

    @objc func moveUserAction(_ sender: Any? = nil) {
        let users = selectedUserNodes()
        guard !users.isEmpty, let window = view.window else { return }

        // Canaux disponibles : tous sauf le canal commun si tous les utilisateurs sont dans le même
        let commonChannelID = users.count == 1 ? users[0].channelID : nil
        let allChannels = flatChannels(from: session.rootChannels)
        let channels = allChannels.filter { $0.id != commonChannelID }
        guard !channels.isEmpty else { return }

        let title = users.count == 1
            ? L10n.format("connectedServer.move.title", users[0].displayName)
            : L10n.format("connectedServer.move.title.multiple", users.count)

        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: L10n.text("connectedServer.move.confirm"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        channels.forEach { popup.addItem(withTitle: $0.name) }
        alert.accessoryView = popup
        alert.window.initialFirstResponder = popup

        alert.beginSheetModal(for: window) { [weak self] response in
            let selectedIndex = popup.indexOfSelectedItem
            guard response == .alertFirstButtonReturn, let self,
                  selectedIndex >= 0, selectedIndex < channels.count else { return }
            let target = channels[selectedIndex]
            for user in users {
                self.connectionController.moveUser(userID: user.id, toChannelID: target.id) { [weak self] result in
                    if case .failure(let error) = result {
                        self?.presentError(error)
                    }
                }
            }
        }
    }

    func selectedUserNodes() -> [ConnectedServerUser] {
        outlineView.selectedRowIndexes.compactMap { row in
            guard case .user(let user) = outlineView.item(atRow: row) as? ServerTreeNode else { return nil }
            return user
        }
    }

    func flatChannels(from channels: [ConnectedServerChannel]) -> [ConnectedServerChannel] {
        channels.flatMap { [$0] + flatChannels(from: $0.children) }
    }

    func setSelectedUsersSubscription(_ option: UserSubscriptionOption, enabled: Bool) {
        let users = selectedUserNodes().filter { $0.isCurrentUser == false }
        let userIDs = users.map(\.id)
        guard userIDs.isEmpty == false else {
            return
        }

        connectionController.setSubscription(option, forUserIDs: userIDs, enabled: enabled) { [weak self] result in
            if case .failure(let error) = result {
                self?.presentActionError(error.localizedDescription)
            }
        }
    }
}
