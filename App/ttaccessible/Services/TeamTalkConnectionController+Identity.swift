//
//  TeamTalkConnectionController+Identity.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 30/03/2026.
//

import CoreGraphics
import Foundation

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
            // An empty nickname falls back to the same resolution used at connection time
            // (saved-server nickname → default preference → "tt-Accessible") instead of being
            // rejected, so clearing the field returns to the default nickname.
            let resolved = trimmed.isEmpty ? self.effectiveNickname(for: record) : trimmed

            let commandID = resolved.withCString { TT_DoChangeNickname(instance, $0) }
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
        autoAwayPeakIdleSeconds = nil
    }

    /// Seconds since last keyboard/mouse input, or nil when the value cannot be read reliably.
    func currentIdleSecondsLocked() -> Double? {
        let eventTypes: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown]
        let samples = eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0)
        }.filter { $0.isFinite && $0 >= 0 }
        return samples.min()
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
        if isAutoAwayActive, !TeamTalkStatusMode.isAwayStatus(currentUser.nStatusMode) {
            // User left Away manually; stop managing auto-away.
            clearAutoAwayStateLocked()
            return false
        }

        guard let idleSeconds = currentIdleSecondsLocked() else {
            return false
        }
        let threshold = Double(timeoutMinutes * 60)

        if isAutoAwayActive {
            return updateAutoAwayWhileActiveLocked(
                instance: instance,
                idleSeconds: idleSeconds
            )
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
            autoAwayPeakIdleSeconds = idleSeconds
            appendAutoAwayActivatedHistoryLocked()
            return true
        } catch {
            clearAutoAwayStateLocked()
            return false
        }
    }

    /// Returns true when auto-away should end because the user is active again.
    func updateAutoAwayWhileActiveLocked(
        instance: UnsafeMutableRawPointer,
        idleSeconds: Double
    ) -> Bool {
        let activityThreshold = 3.0
        let minimumIdleDrop = 15.0
        let postActivationGrace: TimeInterval = 2

        if let peak = autoAwayPeakIdleSeconds {
            autoAwayPeakIdleSeconds = max(peak, idleSeconds)
        } else {
            autoAwayPeakIdleSeconds = idleSeconds
        }

        guard idleSeconds < activityThreshold else {
            return false
        }

        // Ignore brief idle glitches right after we set Away (status/UI updates).
        if let activationTime = autoAwayActivationTime,
           Date().timeIntervalSince(activationTime) < postActivationGrace {
            return false
        }

        // Real input resets the idle counter from a much higher sustained value.
        guard let peakIdle = autoAwayPeakIdleSeconds,
              peakIdle - idleSeconds >= minimumIdleDrop else {
            return false
        }

        return deactivateAutoAwayLocked(instance: instance)
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
            return false
        }

        do {
            try waitForCommandCompletionLocked(instance: instance, commandID: commandID)
            clearAutoAwayStateLocked()
            appendAutoAwayDeactivatedHistoryLocked()
            return true
        } catch {
            return false
        }
    }
}
