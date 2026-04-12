//
//  TeamTalkConnectionModels.swift
//  ttaccessible
//
//  Extracted from TeamTalkConnectionController.swift
//

import Foundation

// MARK: - Incoming text message

enum IncomingTextMessageKind {
    case privateMessage
    case channelMessage
    case broadcastMessage
}

struct IncomingTextMessageEvent {
    let kind: IncomingTextMessageKind
    let senderName: String
    let content: String
}

// MARK: - Server properties model

struct ServerPropertiesData {
    var name: String
    var motdRaw: String
    var maxUsers: Int32
    var userTimeout: Int32
    var loginDelayMSec: Int32
    var maxLoginAttempts: Int32
    var maxLoginsPerIPAddress: Int32
    var autoSave: Bool
    var maxVoiceTxPerSecond: Int32
    var maxVideoCaptureTxPerSecond: Int32
    var maxMediaFileTxPerSecond: Int32
    var maxDesktopTxPerSecond: Int32
    var maxTotalTxPerSecond: Int32
}

// MARK: - Banned user model

struct BannedUserProperties {
    var ipAddress: String
    var channelPath: String
    var banTime: String
    var nickname: String
    var username: String
    var banTypes: UInt32
    var owner: String

    var displayBanType: String {
        var parts: [String] = []
        if (banTypes & UInt32(BANTYPE_IPADDR.rawValue)) != 0   { parts.append(L10n.text("bans.type.ip")) }
        if (banTypes & UInt32(BANTYPE_USERNAME.rawValue)) != 0 { parts.append(L10n.text("bans.type.username")) }
        if (banTypes & UInt32(BANTYPE_CHANNEL.rawValue)) != 0  { parts.append(L10n.text("bans.type.channel")) }
        return parts.joined(separator: ", ")
    }

    var displayName: String {
        nickname.isEmpty ? username : nickname
    }
}

// MARK: - User account model

enum UserAccountType {
    case defaultUser
    case admin
    case disabled
}

struct UserAccountProperties {
    var username: String
    var password: String
    var userType: UserAccountType
    var userRights: UInt32
    var initChannel: String
    var note: String
    var audioBpsLimit: Int32
    var commandsLimit: Int32
    var commandsIntervalMSec: Int32
    var lastLoginTime: String

    static let defaultUserRights: UInt32 = {
        let bits: [UInt32] = [
            UInt32(USERRIGHT_MULTI_LOGIN.rawValue),
            UInt32(USERRIGHT_VIEW_ALL_USERS.rawValue),
            UInt32(USERRIGHT_CREATE_TEMPORARY_CHANNEL.rawValue),
            UInt32(USERRIGHT_UPLOAD_FILES.rawValue),
            UInt32(USERRIGHT_DOWNLOAD_FILES.rawValue),
            UInt32(USERRIGHT_TRANSMIT_VOICE.rawValue),
            UInt32(USERRIGHT_TEXTMESSAGE_USER.rawValue),
            UInt32(USERRIGHT_TEXTMESSAGE_CHANNEL.rawValue)
        ]
        return bits.reduce(0, |)
    }()

    init() {
        username = ""
        password = ""
        userType = .defaultUser
        userRights = UserAccountProperties.defaultUserRights
        initChannel = ""
        note = ""
        audioBpsLimit = 0
        commandsLimit = 0
        commandsIntervalMSec = 0
        lastLoginTime = ""
    }
}

// MARK: - Private messages presentation

enum PrivateMessagesPresentationReason {
    case userInitiated
    case incomingMessage
}

// MARK: - Connection error

enum TeamTalkConnectionError: LocalizedError {
    case sdkUnavailable
    case connectionStartFailed
    case loginStartFailed
    case connectionFailed
    case connectionTimeout
    case loginFailed(String)
    case incorrectChannelPassword(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return L10n.text("teamtalk.connection.error.sdkUnavailable")
        case .connectionStartFailed:
            return L10n.text("teamtalk.connection.error.connectionStartFailed")
        case .loginStartFailed:
            return L10n.text("teamtalk.connection.error.loginStartFailed")
        case .connectionFailed:
            return L10n.text("teamtalk.connection.error.connectionFailed")
        case .connectionTimeout:
            return L10n.text("teamtalk.connection.error.timeout")
        case .loginFailed(let message), .incorrectChannelPassword(let message), .internalError(let message):
            return message
        }
    }
}

// MARK: - Connect options

struct TeamTalkConnectOptions {
    var nicknameOverride: String?
    var statusMessage: String?
    var genderOverride: TeamTalkGender?
    var initialChannelPath: String?
    var initialChannelPassword: String
    var preferJoinLastChannelFromServer: Bool

    init(
        nicknameOverride: String? = nil,
        statusMessage: String? = nil,
        genderOverride: TeamTalkGender? = nil,
        initialChannelPath: String? = nil,
        initialChannelPassword: String = "",
        preferJoinLastChannelFromServer: Bool = false
    ) {
        self.nicknameOverride = nicknameOverride
        self.statusMessage = statusMessage
        self.genderOverride = genderOverride
        self.initialChannelPath = initialChannelPath
        self.initialChannelPassword = initialChannelPassword
        self.preferJoinLastChannelFromServer = preferJoinLastChannelFromServer
    }
}

// MARK: - Channel properties (extracted from TeamTalkConnectionController nested types)

struct OpusCodecSettings {
    var channels: Int32       // 1 = mono, 2 = stereo
    var sampleRate: Int32     // 8000, 12000, 16000, 24000, 48000
    var bitrate: Int32        // in bps (UI displays kbps)
    var application: Int32    // OPUS_APPLICATION_VOIP (2048) or OPUS_APPLICATION_AUDIO (2049)

    static let supportedSampleRates: [Int32] = [8000, 12000, 16000, 24000, 48000]
    static let defaultSettings = OpusCodecSettings(channels: 1, sampleRate: 48000, bitrate: 64000, application: 2048)
}

struct ChannelProperties {
    var name: String
    var topic: String
    var password: String
    var maxUsers: Int32
    var isPermanent: Bool
    var isSoloTransmit: Bool
    var isNoVoiceActivation: Bool
    var isNoRecording: Bool
    var opusCodec: OpusCodecSettings?
}

struct ChannelInfo {
    let id: Int32
    let parentID: Int32
    let name: String
    let topic: String
    let password: String
    let maxUsers: Int32
    let isPermanent: Bool
    let isSoloTransmit: Bool
    let isNoVoiceActivation: Bool
    let isNoRecording: Bool
    let opusCodec: OpusCodecSettings?
}
