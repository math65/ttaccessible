//
//  TeamTalkConnectionController+Administration.swift
//  ttaccessible
//
//  Created by Codex on 30/03/2026.
//

import Foundation

extension TeamTalkConnectionController {

    // MARK: - File transfers

    func sendFile(toChannelID channelID: Int32, localPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let result = localPath.withCString { TT_DoSendFile(instance, channelID, $0) }
            DispatchQueue.main.async {
                if result > 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("files.error.uploadFailed"))))
                }
            }
        }
    }

    func receiveFile(fromChannelID channelID: Int32, fileID: Int32, toLocalPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let result = toLocalPath.withCString { TT_DoRecvFile(instance, channelID, fileID, $0) }
            DispatchQueue.main.async {
                if result > 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("files.error.downloadFailed"))))
                }
            }
        }
    }

    func cancelFileTransfer(transferID: Int32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            TT_CancelFileTransfer(instance, transferID)
        }
    }

    func deleteChannelFile(channelID: Int32, fileID: Int32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }
            let result = TT_DoDeleteFile(instance, channelID, fileID)
            DispatchQueue.main.async {
                if result > 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("files.error.deleteFailed"))))
                }
            }
        }
    }

    // MARK: - User account management

    func listUserAccounts() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            let cmdID = TT_DoListUserAccounts(instance, 0, 100000)
            if cmdID > 0 {
                self.pendingUserAccounts = []
                self.listUserAccountsCmdID = cmdID
            }
        }
    }

    func createUserAccount(_ account: UserAccountProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            var sdkAccount = self.makeSDKAccount(from: account)
            let cmdID = TT_DoNewUserAccount(instance, &sdkAccount)
            if cmdID > 0 {
                do {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: cmdID)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError("createUserAccount failed"))) }
            }
        }
    }

    func updateUserAccount(originalUsername: String, updated account: UserAccountProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            do {
                // SDK has no update: delete then recreate
                let deleteCmdID = originalUsername.withCString { TT_DoDeleteUserAccount(instance, $0) }
                if deleteCmdID > 0 {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: deleteCmdID)
                }
                var sdkAccount = self.makeSDKAccount(from: account)
                let createCmdID = TT_DoNewUserAccount(instance, &sdkAccount)
                if createCmdID > 0 {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: createCmdID)
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError("updateUserAccount create failed"))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func deleteUserAccount(username: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let cmdID = username.withCString { TT_DoDeleteUserAccount(instance, $0) }
            if cmdID > 0 {
                do {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: cmdID)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError("deleteUserAccount failed"))) }
            }
        }
    }

    func makeSDKAccount(from properties: UserAccountProperties) -> UserAccount {
        var account = UserAccount()
        copyTTString(properties.username, into: &account.szUsername)
        copyTTString(properties.password, into: &account.szPassword)
        switch properties.userType {
        case .admin:
            account.uUserType = UInt32(USERTYPE_ADMIN.rawValue)
        case .defaultUser:
            account.uUserType = UInt32(USERTYPE_DEFAULT.rawValue)
        case .disabled:
            account.uUserType = UInt32(USERTYPE_NONE.rawValue)
        }
        account.uUserRights = properties.userRights
        copyTTString(properties.initChannel, into: &account.szInitChannel)
        copyTTString(properties.note, into: &account.szNote)
        account.nAudioCodecBpsLimit = properties.audioBpsLimit
        account.abusePrevent.nCommandsLimit = properties.commandsLimit
        account.abusePrevent.nCommandsIntervalMSec = properties.commandsIntervalMSec
        return account
    }

    func makeUserAccountProperties(from account: UserAccount) -> UserAccountProperties {
        var props = UserAccountProperties()
        props.username = ttString(from: account.szUsername)
        props.password = ttString(from: account.szPassword)
        if (account.uUserType & UInt32(USERTYPE_ADMIN.rawValue)) != 0 {
            props.userType = .admin
        } else if account.uUserType == UInt32(USERTYPE_DEFAULT.rawValue) {
            props.userType = .defaultUser
        } else {
            props.userType = .disabled
        }
        props.userRights = account.uUserRights
        props.initChannel = ttString(from: account.szInitChannel)
        props.note = ttString(from: account.szNote)
        props.audioBpsLimit = account.nAudioCodecBpsLimit
        props.commandsLimit = account.abusePrevent.nCommandsLimit
        props.commandsIntervalMSec = account.abusePrevent.nCommandsIntervalMSec
        return props
    }

    // MARK: - Ban management

    func listBans() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            let cmdID = TT_DoListBans(instance, 0, 0, 100000)
            if cmdID > 0 {
                self.pendingBannedUsers = []
                self.listBansCmdID = cmdID
            }
        }
    }

    func kickAndBanUser(userID: Int32, banTypes: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let banCmdID = TT_DoBanUserEx(instance, userID, banTypes)
            let kickCmdID = TT_DoKickUser(instance, userID, 0)
            DispatchQueue.main.async {
                completion(banCmdID > 0 && kickCmdID > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError("kickAndBanUser failed")))
            }
        }
    }

    func addBan(_ ban: BannedUserProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            var sdkBan = BannedUser()
            self.copyTTString(ban.ipAddress, into: &sdkBan.szIPAddress)
            self.copyTTString(ban.username, into: &sdkBan.szUsername)
            self.copyTTString(ban.channelPath, into: &sdkBan.szChannelPath)
            sdkBan.uBanTypes = ban.banTypes
            let cmdID = TT_DoBan(instance, &sdkBan)
            DispatchQueue.main.async {
                completion(cmdID > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError("addBan failed")))
            }
        }
    }

    func removeBan(_ ban: BannedUserProperties, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            var sdkBan = BannedUser()
            self.copyTTString(ban.ipAddress, into: &sdkBan.szIPAddress)
            self.copyTTString(ban.username, into: &sdkBan.szUsername)
            self.copyTTString(ban.channelPath, into: &sdkBan.szChannelPath)
            sdkBan.uBanTypes = ban.banTypes
            let cmdID = TT_DoUnBanUserEx(instance, &sdkBan)
            DispatchQueue.main.async {
                completion(cmdID > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError("removeBan failed")))
            }
        }
    }

    func makeBannedUserProperties(from ban: BannedUser) -> BannedUserProperties {
        BannedUserProperties(
            ipAddress:   ttString(from: ban.szIPAddress),
            channelPath: ttString(from: ban.szChannelPath),
            banTime:     ttString(from: ban.szBanTime),
            nickname:    ttString(from: ban.szNickname),
            username:    ttString(from: ban.szUsername),
            banTypes:    ban.uBanTypes,
            owner:       ttString(from: ban.szOwner)
        )
    }

    func handleFileTransferEventLocked(_ transfer: FileTransfer) {
        switch transfer.nStatus {
        case FILETRANSFER_ACTIVE:
            activeTransferProgress[transfer.nTransferID] = FileTransferProgress(
                transferID: transfer.nTransferID,
                fileName: ttString(from: transfer.szRemoteFileName),
                transferred: transfer.nTransferred,
                total: transfer.nFileSize,
                isDownload: transfer.bInbound != 0
            )
        case FILETRANSFER_FINISHED:
            activeTransferProgress.removeValue(forKey: transfer.nTransferID)
            SoundPlayer.shared.play(.fileTxComplete)
            let fileName = ttString(from: transfer.szRemoteFileName)
            let isDownload = transfer.bInbound != 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.teamTalkConnectionController(self, didFinishFileTransfer: fileName, isDownload: isDownload, success: true)
            }
        case FILETRANSFER_ERROR:
            activeTransferProgress.removeValue(forKey: transfer.nTransferID)
            let fileName = ttString(from: transfer.szRemoteFileName)
            let isDownload = transfer.bInbound != 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.teamTalkConnectionController(self, didFinishFileTransfer: fileName, isDownload: isDownload, success: false)
            }
        default:
            break
        }
    }

    // MARK: - User moderation

    func kickUser(userID: Int32, channelID: Int32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let result = TT_DoKickUser(instance, userID, channelID)
            DispatchQueue.main.async {
                completion(result > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.action.kickFailed"))))
            }
        }
    }

    func muteUser(userID: Int32, mute: Bool, completion: (@MainActor (Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_SetUserMute(instance, userID, STREAMTYPE_VOICE, mute ? 1 : 0)
            _ = TT_PumpMessage(instance, CLIENTEVENT_USER_STATECHANGE, userID)
            if let completion {
                DispatchQueue.main.async { completion(mute) }
            }
        }
    }

    func moveUser(userID: Int32, toChannelID: Int32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let result = TT_DoMoveUser(instance, userID, toChannelID)
            DispatchQueue.main.async {
                completion(result > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.action.moveFailed"))))
            }
        }
    }

    // MARK: - Channel operator

    func channelOp(userID: Int32, channelID: Int32, makeOperator: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let result = TT_DoChannelOp(instance, userID, channelID, makeOperator ? 1 : 0)
            DispatchQueue.main.async {
                completion(result > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.op.error"))))
            }
        }
    }

    func channelOpEx(userID: Int32, channelID: Int32, password: String, makeOperator: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.sdkUnavailable)) }
                return
            }
            let result = password.withCString { cPassword in
                TT_DoChannelOpEx(instance, userID, channelID, cPassword, makeOperator ? 1 : 0)
            }
            DispatchQueue.main.async {
                completion(result > 0 ? .success(()) : .failure(TeamTalkConnectionError.internalError(L10n.text("connectedServer.op.error"))))
            }
        }
    }

    func hasOperatorEnableRight() -> Bool {
        guard let instance else { return false }
        return queue.sync {
            (TT_GetMyUserRights(instance) & UInt32(USERRIGHT_OPERATOR_ENABLE.rawValue)) != 0
        }
    }

    // MARK: - Server management

    func queryServerStats() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_DoQueryServerStats(instance)
        }
    }

    func getServerProperties() -> ServerPropertiesData? {
        var result: ServerPropertiesData?
        queue.sync { [weak self] in
            guard let self, let instance = self.instance else { return }
            var sp = ServerProperties()
            guard TT_GetServerProperties(instance, &sp) != 0 else { return }
            result = ServerPropertiesData(
                name: self.ttString(from: sp.szServerName),
                motdRaw: self.ttString(from: sp.szMOTDRaw),
                maxUsers: sp.nMaxUsers,
                userTimeout: sp.nUserTimeout,
                loginDelayMSec: sp.nLoginDelayMSec,
                maxLoginAttempts: sp.nMaxLoginAttempts,
                maxLoginsPerIPAddress: sp.nMaxLoginsPerIPAddress,
                autoSave: sp.bAutoSave != 0,
                maxVoiceTxPerSecond: sp.nMaxVoiceTxPerSecond,
                maxVideoCaptureTxPerSecond: sp.nMaxVideoCaptureTxPerSecond,
                maxMediaFileTxPerSecond: sp.nMaxMediaFileTxPerSecond,
                maxDesktopTxPerSecond: sp.nMaxDesktopTxPerSecond,
                maxTotalTxPerSecond: sp.nMaxTotalTxPerSecond
            )
        }
        return result
    }

    func updateServerProperties(_ props: ServerPropertiesData, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var sp = ServerProperties()
            guard TT_GetServerProperties(instance, &sp) != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            self.copyTTString(props.name, into: &sp.szServerName)
            self.copyTTString(props.motdRaw, into: &sp.szMOTDRaw)
            sp.nMaxUsers = props.maxUsers
            sp.nUserTimeout = props.userTimeout
            sp.nLoginDelayMSec = props.loginDelayMSec
            sp.nMaxLoginAttempts = props.maxLoginAttempts
            sp.nMaxLoginsPerIPAddress = props.maxLoginsPerIPAddress
            sp.bAutoSave = props.autoSave ? 1 : 0
            sp.nMaxVoiceTxPerSecond = props.maxVoiceTxPerSecond
            sp.nMaxVideoCaptureTxPerSecond = props.maxVideoCaptureTxPerSecond
            sp.nMaxMediaFileTxPerSecond = props.maxMediaFileTxPerSecond
            sp.nMaxDesktopTxPerSecond = props.maxDesktopTxPerSecond
            sp.nMaxTotalTxPerSecond = props.maxTotalTxPerSecond

            let commandID = withUnsafeMutablePointer(to: &sp) { TT_DoUpdateServer(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - User volume

    func setUserVoiceVolume(userID: Int32, username: String, volume: Int32) {
        userVolumeStore.setVolume(volume, forUsername: username)
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_SetUserVolume(instance, userID, STREAMTYPE_VOICE, volume)
        }
    }

    func setUserStereo(userID: Int32, leftSpeaker: Bool, rightSpeaker: Bool) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_SetUserStereo(instance, userID, STREAMTYPE_VOICE, leftSpeaker ? 1 : 0, rightSpeaker ? 1 : 0)
        }
    }

    func getUserStereo(userID: Int32, completion: @escaping @MainActor (Bool, Bool) -> Void) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else {
                DispatchQueue.main.async { completion(true, true) }
                return
            }
            var user = User()
            if TT_GetUser(instance, userID, &user) != 0 {
                let left = user.stereoPlaybackVoice.0 != 0
                let right = user.stereoPlaybackVoice.1 != 0
                DispatchQueue.main.async { completion(left, right) }
            } else {
                DispatchQueue.main.async { completion(true, true) }
            }
        }
    }

    func setUserVoiceVolumeImmediate(userID: Int32, volume: Int32) {
        queue.async { [weak self] in
            guard let self, let instance = self.instance else { return }
            _ = TT_SetUserVolume(instance, userID, STREAMTYPE_VOICE, volume)
        }
    }

    // MARK: - Subscriptions

    func setSubscription(
        _ option: UserSubscriptionOption,
        forUserIDs userIDs: [Int32],
        enabled: Bool,
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

            let uniqueUserIDs = Array(Set(userIDs)).sorted()
            guard uniqueUserIDs.isEmpty == false else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.internalError(L10n.text("subscriptions.error.noSelectedUser"))))
                }
                return
            }

            for userID in uniqueUserIDs {
                let commandID = self.setSubscriptionLocked(instance: instance, userID: userID, option: option, enabled: enabled)
                guard commandID > 0 else {
                    DispatchQueue.main.async {
                        completion(.failure(TeamTalkConnectionError.internalError(L10n.text("subscriptions.error.updateFailed"))))
                    }
                    return
                }
                let userName = self.displayName(forUserID: userID, instance: instance)
                self.updateObservedSubscriptionStateLocked(option, enabled: enabled, userID: userID)
                self.appendSubscriptionHistoryLocked(
                    option,
                    userName: userName,
                    enabled: enabled,
                    userID: userID
                )
            }

            self.publishSessionLocked(instance: instance, record: record)
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    func applyDefaultSubscriptionPreferences() {
        queue.async { [weak self] in
            guard let self, let instance = self.instance, let record = self.connectedRecord else {
                return
            }
            self.applyDefaultSubscriptionPreferencesLocked(instance: instance, preferences: self.preferencesStore.preferences)
            self.publishSessionLocked(instance: instance, record: record)
        }
    }

    func applyDefaultSubscriptionPreferencesLocked(
        instance: UnsafeMutableRawPointer,
        preferences: AppPreferences
    ) {
        let myUserID = TT_GetMyUserID(instance)
        for user in fetchServerUsersLocked(instance: instance) where user.nUserID != myUserID {
            applyDefaultSubscriptionPreferencesLocked(instance: instance, userID: user.nUserID, preferences: preferences)
        }
    }

    func applyDefaultSubscriptionPreferencesLocked(
        instance: UnsafeMutableRawPointer,
        userID: Int32,
        preferences: AppPreferences
    ) {
        for option in UserSubscriptionOption.allCases {
            let enabled = preferences.isSubscriptionEnabledByDefault(option)
            let commandID = setSubscriptionLocked(instance: instance, userID: userID, option: option, enabled: enabled)
            if commandID > 0 {
                updateObservedSubscriptionStateLocked(option, enabled: enabled, userID: userID)
            }
        }
    }

    @discardableResult
    func setSubscriptionLocked(
        instance: UnsafeMutableRawPointer,
        userID: Int32,
        option: UserSubscriptionOption,
        enabled: Bool
    ) -> Int32 {
        if enabled {
            return TT_DoSubscribe(instance, userID, Subscriptions(option.subscriptionMask))
        }
        return TT_DoUnsubscribe(instance, userID, Subscriptions(option.subscriptionMask))
    }

    func updateObservedSubscriptionStateLocked(
        _ option: UserSubscriptionOption,
        enabled: Bool,
        userID: Int32
    ) {
        var states = observedSubscriptionStates[userID] ?? [:]
        states[option] = enabled
        observedSubscriptionStates[userID] = states
    }
}
