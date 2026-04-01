//
//  TeamTalkConnectionController.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import AVFoundation
import CoreAudio
import Foundation
import IOKit

@MainActor
protocol TeamTalkConnectionControllerDelegate: AnyObject {
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateSession session: ConnectedServerSession)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateAudioRuntime update: ConnectedServerAudioRuntimeUpdate)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didUpdateActiveTransfers transfers: [FileTransferProgress], currentChannelID: Int32)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didDisconnectWithMessage message: String?)
    func teamTalkConnectionControllerDidStartReconnecting(_ controller: TeamTalkConnectionController)
    func teamTalkConnectionController(
        _ controller: TeamTalkConnectionController,
        didRequestPrivateMessagesWindowFor userID: Int32?,
        reason: PrivateMessagesPresentationReason
    )
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didFinishFileTransfer fileName: String, isDownload: Bool, success: Bool)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveServerStatistics stats: ServerStatistics)
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveUserAccounts accounts: [UserAccountProperties])
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveBannedUsers users: [BannedUserProperties])
    func teamTalkConnectionController(_ controller: TeamTalkConnectionController, didReceiveIncomingTextMessage event: IncomingTextMessageEvent)
}

final class TeamTalkConnectionController {
    struct SessionPublishInvalidation: OptionSet {
        let rawValue: Int

        static let rootTree = SessionPublishInvalidation(rawValue: 1 << 0)
        static let chat = SessionPublishInvalidation(rawValue: 1 << 1)
        static let history = SessionPublishInvalidation(rawValue: 1 << 2)
        static let privateConversations = SessionPublishInvalidation(rawValue: 1 << 3)
        static let channelFiles = SessionPublishInvalidation(rawValue: 1 << 4)
        static let activeTransfers = SessionPublishInvalidation(rawValue: 1 << 5)
        static let audio = SessionPublishInvalidation(rawValue: 1 << 6)
        static let identity = SessionPublishInvalidation(rawValue: 1 << 7)
        static let permissions = SessionPublishInvalidation(rawValue: 1 << 8)

        static let all: SessionPublishInvalidation = [
            .rootTree,
            .chat,
            .history,
            .privateConversations,
            .channelFiles,
            .activeTransfers,
            .audio,
            .identity,
            .permissions
        ]
    }

    let queueKey = DispatchSpecificKey<Void>()
    let queue = DispatchQueue(label: "com.math65.ttaccessible.teamtalk")
    let clientName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TTAccessible"
    let preferencesStore: AppPreferencesStore
    let userVolumeStore = UserVolumeStore()
    let lastChannelStore = LastChannelStore()


    @MainActor weak var delegate: TeamTalkConnectionControllerDelegate?
    @MainActor var sessionSnapshot: ConnectedServerSession?
    @MainActor var isConnected = false

    var instance: UnsafeMutableRawPointer?
    var pollTimer: DispatchSourceTimer?
    var connectedRecord: SavedServerRecord?
    var channelChatHistory: [ChannelChatMessage] = []
    var sessionHistory: [SessionHistoryEntry] = []
    var activeTransferProgress: [Int32: FileTransferProgress] = [:]
    var pendingTextMessages: [UInt64: [TextMessage]] = [:]
    var pendingChannelMessageCommandIDs = Set<Int32>()
    var observedSubscriptionStates: [Int32: [UserSubscriptionOption: Bool]] = [:]
    var suppressLoginHistoryDepth = 0
    var suppressJoinHistoryDepth = 0
    var suppressLoginHistoryUntil = Date.distantPast
    var suppressJoinHistoryUntil = Date.distantPast
    var channelPasswords: [Int32: String] = [:]
    var privateConversations: [Int32: PrivateConversation] = [:]
    var selectedPrivateConversationUserID: Int32?
    var visiblePrivateConversationUserID: Int32?
    var isPrivateMessagesWindowVisible = false
    var outputAudioReady = false
    var inputAudioReady = false
    var voiceTransmissionEnabled = false
    var masterMuted = false
    var teamTalkVirtualInputReady = false
    var advancedMicrophoneTargetFormat: AdvancedMicrophoneAudioTargetFormat?
    var reconnectTimer: DispatchSourceTimer?
    var reconnectRecord: SavedServerRecord?
    var reconnectPassword: String?
    var reconnectOptions = TeamTalkConnectOptions()
    var lastChannelID: Int32 = 0
    var lastAutoAwayCheckTime: CFAbsoluteTime = 0
    var isAutoAwayActive = false
    var autoAwayRestoreStatusMessage = ""
    var pendingUserAccounts: [UserAccountProperties] = []
    var listUserAccountsCmdID: Int32 = -1
    var pendingBannedUsers: [BannedUserProperties] = []
    var listBansCmdID: Int32 = -1
    var lastBuiltSessionSnapshot: ConnectedServerSession?
    var cachedSoundDevices: [SoundDevice] = []
    var cachedAudioDeviceCatalog: AudioDeviceCatalog?
    lazy var advancedMicrophoneEngine = AdvancedMicrophoneAudioEngine { [weak self] chunk in
        self?.queue.async { [weak self] in
            self?.insertAdvancedMicrophoneAudioChunkLocked(chunk)
        }
    }

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        queue.setSpecific(key: queueKey, value: ())
    }

    var isAnyMicrophoneEngineRunning: Bool {
        advancedMicrophoneEngine.isRunning
    }

    // MARK: - Audio (see TeamTalkConnectionController+Audio.swift)

    // MARK: - applyDefaultSubscriptionPreferences (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Private messaging (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Identity (see TeamTalkConnectionController+Identity.swift)

    // MARK: - Channel management (see TeamTalkConnectionController+ChannelManagement.swift)

    // MARK: - Administration (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Channel & broadcast messaging (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Connection lifecycle (see TeamTalkConnectionController+Connection.swift)

    // MARK: - Auto-away (see TeamTalkConnectionController+Identity.swift)

    // MARK: - Session snapshot and publishing (see TeamTalkConnectionController+SessionSnapshot.swift)

    // MARK: - Session history (see TeamTalkConnectionController+SessionHistory.swift)

    // MARK: - Text message handling (see TeamTalkConnectionController+Messaging.swift)

    func copyTTString<T>(_ string: String, into target: inout T) {
        var copy = target
        withUnsafeMutablePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                memset(charPointer, 0, MemoryLayout<T>.size)
                _ = string.withCString { source in
                    strlcpy(charPointer, source, MemoryLayout<T>.size)
                }
            }
        }
        target = copy
    }

    func displayName(forUserID userID: Int32, instance: UnsafeMutableRawPointer) -> String {
        var user = User()
        if TT_GetUser(instance, userID, &user) != 0 {
            return displayName(for: user)
        }

        return L10n.format("connectedServer.chat.sender.unknown", String(userID))
    }

    func currentUserLocked(instance: UnsafeMutableRawPointer) -> User? {
        let currentUserID = TT_GetMyUserID(instance)
        guard currentUserID > 0 else {
            return nil
        }

        var user = User()
        guard TT_GetUser(instance, currentUserID, &user) != 0 else {
            return nil
        }
        return user
    }

    // MARK: - Private conversation helpers (see TeamTalkConnectionController+Messaging.swift)

    // MARK: - Subscription helpers (see TeamTalkConnectionController+Administration.swift)

    // MARK: - Message publishing helpers (see TeamTalkConnectionController+Messaging.swift)

    func fetchServerChannelsLocked(instance: UnsafeMutableRawPointer) -> [Channel] {
        var count: INT32 = 0
        guard TT_GetServerChannels(instance, nil, &count) != 0, count > 0 else {
            return []
        }

        var channels = Array(repeating: Channel(), count: Int(count))
        var actualCount = count
        let didFetch = channels.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }

            return TT_GetServerChannels(instance, baseAddress, &actualCount) != 0
        }

        guard didFetch else {
            return []
        }

        return Array(channels.prefix(Int(actualCount)))
    }

    func fetchServerUsersLocked(instance: UnsafeMutableRawPointer) -> [User] {
        var count: INT32 = 0
        guard TT_GetServerUsers(instance, nil, &count) != 0, count > 0 else {
            return []
        }

        var users = Array(repeating: User(), count: Int(count))
        var actualCount = count
        let didFetch = users.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }

            return TT_GetServerUsers(instance, baseAddress, &actualCount) != 0
        }

        guard didFetch else {
            return []
        }

        return Array(users.prefix(Int(actualCount)))
    }

    func displayName(for user: User) -> String {
        let nickname = ttString(from: user.szNickname)
        if nickname.isEmpty == false {
            return nickname
        }
        return ttString(from: user.szUsername)
    }

    func effectiveNickname(for record: SavedServerRecord, override nicknameOverride: String? = nil) -> String {
        let overriddenNickname = nicknameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if overriddenNickname.isEmpty == false {
            return overriddenNickname
        }

        let recordNickname = record.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if recordNickname.isEmpty == false {
            return recordNickname
        }

        let preferredNickname = preferencesStore.preferences.defaultNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferredNickname.isEmpty == false {
            return preferredNickname
        }

        return "TTAccessible"
    }

    func clientVersion(for user: User) -> String {
        "\(user.uVersion >> 16).\((user.uVersion >> 8) & 0xFF).\(user.uVersion & 0xFF)"
    }

    func ttString<T>(from value: T) -> String {
        var copy = value
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                String(cString: charPointer)
            }
        }
    }
}
