//
//  TeamTalkConnectionController+Identity.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 30/03/2026.
//

import Foundation
import IOKit

extension TeamTalkConnectionController {

    func changeNickname(to nickname: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.identity.error.emptyNickname"))))
                }
                return
            }

            let commandID = trimmed.withCString { TT_DoChangeNickname(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func changeStatus(
        mode: TeamTalkStatusMode,
        message: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let currentUser = self.currentUserLocked(instance: instance)
            self.clearAutoAwayStateLocked()
            let mergedMode = mode.merged(with: currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue)
            let commandID = message.withCString { messagePointer in
                TT_DoChangeStatus(instance, mergedMode, messagePointer)
            }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                if mode == .question {
                    SoundPlayer.shared.play(.questionMode)
                }
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func changeGender(
        _ gender: TeamTalkGender,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let currentUser = self.currentUserLocked(instance: instance)
            let currentBitmask = currentUser?.nStatusMode ?? TeamTalkStatusMode.available.rawValue
            let currentMode = TeamTalkStatusMode(bitmask: currentBitmask)
            let mergedMode = currentMode.merged(with: gender.merged(with: currentBitmask))
            let currentStatusMessage = currentUser.map { self.ttString(from: $0.szStatusMsg) } ?? ""

            let commandID = currentStatusMessage.withCString { messagePointer in
                TT_DoChangeStatus(instance, mergedMode, messagePointer)
            }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Auto-away

    func clearAutoAwayStateLocked() {
        isAutoAwayActive = false
        autoAwayActivationTime = nil
        autoAwayRestoreStatusMessage = ""
    }

    func currentIdleSecondsLocked() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else {
            return 0
        }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as NSDictionary?,
              let idleTime = dictionary["HIDIdleTime"] as? NSNumber else {
            return 0
        }

        return Double(idleTime.uint64Value) / 1_000_000_000
    }

    func updateAutoAwayIfNeededLocked(instance: UnsafeMutableRawPointer) -> Bool {
        guard (TT_GetFlags(instance) & UInt32(CLIENT_AUTHORIZED.rawValue)) != 0 else {
            if isAutoAwayActive {
                clearAutoAwayStateLocked()
            }
            return false
        }

        let timeoutMinutes = preferencesStore.preferences.autoAwayTimeoutMinutes
        guard timeoutMinutes > 0 else {
            if isAutoAwayActive {
                return deactivateAutoAwayLocked(instance: instance)
            }
            return false
        }

        guard let currentUser = currentUserLocked(instance: instance) else {
            if isAutoAwayActive {
                clearAutoAwayStateLocked()
            }
            return false
        }

        let currentMode = TeamTalkStatusMode(bitmask: currentUser.nStatusMode)
        if isAutoAwayActive, currentMode != .away {
            clearAutoAwayStateLocked()
            return false
        }

        let idleSeconds = currentIdleSecondsLocked()
        let threshold = Double(timeoutMinutes * 60)

        if isAutoAwayActive {
            guard idleSeconds < 10 else {
                return false
            }
            return deactivateAutoAwayLocked(instance: instance)
        }

        guard currentMode == .available, idleSeconds >= threshold else {
            return false
        }

        let currentStatusMessage = ttString(from: currentUser.szStatusMsg)
        autoAwayRestoreStatusMessage = currentStatusMessage
        let awayStatusMessage = preferencesStore.preferences.autoAwayStatusMessage.isEmpty
            ? currentStatusMessage
            : preferencesStore.preferences.autoAwayStatusMessage
        let awayBitmask = TeamTalkStatusMode.away.merged(with: currentUser.nStatusMode)
        let commandID = awayStatusMessage.withCString { TT_DoChangeStatus(instance, awayBitmask, $0) }
        guard commandID > 0 else {
            clearAutoAwayStateLocked()
            return false
        }

        do {
            try waitForCommandCompletionLocked(instance: instance, commandID: commandID)
            isAutoAwayActive = true
            autoAwayActivationTime = Date()
            appendAutoAwayActivatedHistoryLocked()
            return true
        } catch {
            clearAutoAwayStateLocked()
            return false
        }
    }

    func deactivateAutoAwayLocked(instance: UnsafeMutableRawPointer) -> Bool {
        guard isAutoAwayActive, let currentUser = currentUserLocked(instance: instance) else {
            clearAutoAwayStateLocked()
            return false
        }

        let restoredMessage = autoAwayRestoreStatusMessage
        let restoredBitmask = TeamTalkStatusMode.available.merged(with: currentUser.nStatusMode)
        let commandID = restoredMessage.withCString { TT_DoChangeStatus(instance, restoredBitmask, $0) }
        guard commandID > 0 else {
            clearAutoAwayStateLocked()
            return false
        }

        do {
            try waitForCommandCompletionLocked(instance: instance, commandID: commandID)
            clearAutoAwayStateLocked()
            appendAutoAwayDeactivatedHistoryLocked()
            return true
        } catch {
            clearAutoAwayStateLocked()
            return false
        }
    }
}
