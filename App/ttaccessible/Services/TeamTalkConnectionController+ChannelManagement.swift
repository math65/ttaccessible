//
//  TeamTalkConnectionController+ChannelManagement.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 30/03/2026.
//

import Foundation

extension TeamTalkConnectionController {

    func joinChannel(
        id channelID: Int32,
        password: String = "",
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

            let commandID = password.withCString { passwordPointer in
                TT_DoJoinChannelByID(instance, channelID, passwordPointer)
            }
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.withSuppressedJoinHistoryLocked {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                }
                self.channelPasswords[channelID] = password
                self.appendJoinedChannelHistoryLocked(channelID: channelID, instance: instance)
                self.saveLastChannelLocked(channelID: channelID, instance: instance)
                // Not gated on voiceTransmissionEnabled: a hot-but-muted engine
                // ("both" mode, or a mic toggled off) keeps its target format
                // too, and would meet the new channel with the old one.
                self.refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
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


    // MARK: - Speaking queue (CHANNEL_SOLO_TRANSMIT)

    /// Our position in the current channel's speaking queue, announced when it
    /// changes. In a solo-transmit channel only one person is heard at a time:
    /// everyone else waits in a server-held queue, and the server hands the
    /// floor to whoever is at its head. The Qt client marks the two ends of a
    /// turn with a sound; a client people navigate by ear can say where in the
    /// line you actually stand, which is the part you cannot see.
    ///
    /// Returns whether anything was announced, so the caller can invalidate the
    /// history it just added to.
    @discardableResult
    func updateTransmitQueueStateLocked(instance: UnsafeMutableRawPointer) -> Bool {
        let myChannelID = TT_GetMyChannelID(instance)
        var channel = Channel()
        guard myChannelID > 0, TT_GetChannel(instance, myChannelID, &channel) != 0 else {
            lastTransmitQueuePosition = nil
            return false
        }
        // Every other channel type has no queue at all — forget any position
        // silently rather than announcing a turn that just ended by leaving.
        guard (channel.uChannelType & UInt32(CHANNEL_SOLO_TRANSMIT.rawValue)) != 0 else {
            lastTransmitQueuePosition = nil
            return false
        }

        let position = Self.transmitQueuePosition(in: &channel, userID: TT_GetMyUserID(instance))
        let previous = lastTransmitQueuePosition
        guard position != previous else { return false }
        lastTransmitQueuePosition = position

        if position == 0 {
            SoundPlayer.shared.play(.txQueueStart)
            appendHistoryLocked(kind: .transmitQueueChanged,
                                message: L10n.text("history.transmitQueue.yourTurn"))
            return true
        }
        if previous == 0 {
            SoundPlayer.shared.play(.txQueueStop)
            appendHistoryLocked(kind: .transmitQueueChanged,
                                message: L10n.text("history.transmitQueue.turnEnded"))
            return true
        }
        guard let position else {
            // Left the queue without ever reaching its head: nothing happened
            // that the user needs telling about.
            return false
        }
        appendHistoryLocked(kind: .transmitQueueChanged,
                            message: L10n.format("history.transmitQueue.position", position + 1))
        return true
    }

    /// Index of `userID` in `channel.transmitUsersQueue`, or nil when absent.
    /// The array is a C `INT32[16]` — a tuple once imported — in turn order and
    /// terminated by a zero user ID, the way the Qt client reads its head.
    static func transmitQueuePosition(in channel: inout Channel, userID: Int32) -> Int? {
        guard userID > 0 else { return nil }
        return withUnsafeBytes(of: &channel.transmitUsersQueue) { raw in
            let entries = raw.bindMemory(to: Int32.self)
            for index in entries.indices {
                let queued = entries[index]
                guard queued != 0 else { return nil }
                if queued == userID { return index }
            }
            return nil
        }
    }

    func channelInfo(forChannelID channelID: Int32) -> ChannelInfo? {
        var channel = Channel()
        guard let instance, TT_GetChannel(instance, channelID, &channel) != 0 else {
            return nil
        }
        let chanType = channel.uChannelType
        let codec: OpusCodecSettings?
        if channel.audiocodec.nCodec == OPUS_CODEC {
            let opus = channel.audiocodec.opus
            codec = OpusCodecSettings(
                channels: opus.nChannels,
                sampleRate: opus.nSampleRate,
                bitrate: opus.nBitRate,
                application: opus.nApplication
            )
        } else {
            codec = nil
        }
        return ChannelInfo(
            id: channel.nChannelID,
            parentID: channel.nParentID,
            name: ttString(from: channel.szName),
            topic: ttString(from: channel.szTopic),
            password: ttString(from: channel.szPassword),
            maxUsers: channel.nMaxUsers,
            isPermanent: (chanType & UInt32(CHANNEL_PERMANENT.rawValue)) != 0,
            isSoloTransmit: (chanType & UInt32(CHANNEL_SOLO_TRANSMIT.rawValue)) != 0,
            isNoVoiceActivation: (chanType & UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue)) != 0,
            isNoRecording: (chanType & UInt32(CHANNEL_NO_RECORDING.rawValue)) != 0,
            opusCodec: codec,
            diskQuotaBytes: channel.nDiskQuota
        )
    }

    func createChannel(
        parentID: Int32,
        properties: ChannelProperties,
        joinAfterCreate: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var chan = Channel()
            chan.nParentID = parentID
            self.copyTTString(properties.name, into: &chan.szName)
            self.copyTTString(properties.topic, into: &chan.szTopic)
            self.copyTTString(properties.password, into: &chan.szPassword)
            chan.nMaxUsers = properties.maxUsers
            chan.nDiskQuota = properties.diskQuotaBytes

            var chanType: UInt32 = UInt32(CHANNEL_DEFAULT.rawValue)
            if properties.isPermanent { chanType |= UInt32(CHANNEL_PERMANENT.rawValue) }
            if properties.isSoloTransmit { chanType |= UInt32(CHANNEL_SOLO_TRANSMIT.rawValue) }
            if properties.isNoVoiceActivation { chanType |= UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue) }
            if properties.isNoRecording { chanType |= UInt32(CHANNEL_NO_RECORDING.rawValue) }
            chan.uChannelType = chanType

            // Apply audio codec: use provided settings or copy from parent
            if let opus = properties.opusCodec {
                chan.audiocodec.nCodec = OPUS_CODEC
                chan.audiocodec.opus.nChannels = opus.channels
                chan.audiocodec.opus.nSampleRate = opus.sampleRate
                chan.audiocodec.opus.nBitRate = opus.bitrate
                chan.audiocodec.opus.nApplication = opus.application
                chan.audiocodec.opus.nComplexity = 10
                chan.audiocodec.opus.bFEC = 1
                chan.audiocodec.opus.bDTX = 0
                chan.audiocodec.opus.bVBR = 1
                chan.audiocodec.opus.bVBRConstraint = 0
                chan.audiocodec.opus.nTxIntervalMSec = 40
                chan.audiocodec.opus.nFrameSizeMSec = 40
            } else {
                var parentChan = Channel()
                if TT_GetChannel(instance, parentID, &parentChan) != 0 {
                    chan.audiocodec = parentChan.audiocodec
                }
            }

            if joinAfterCreate {
                let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoJoinChannel(instance, $0) }
                guard commandID > 0 else {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                    return
                }
                do {
                    try self.withSuppressedJoinHistoryLocked {
                        try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                    }
                    self.channelPasswords[TT_GetMyChannelID(instance)] = properties.password
                    self.publishSessionLocked(instance: instance, record: record)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } else {
                let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoMakeChannel(instance, $0) }
                guard commandID > 0 else {
                    DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                    return
                }
                do {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                    self.publishSessionLocked(instance: instance, record: record)
                    DispatchQueue.main.async { completion(.success(())) }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    func updateChannel(
        channelID: Int32,
        properties: ChannelProperties,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var chan = Channel()
            guard TT_GetChannel(instance, channelID, &chan) != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            self.copyTTString(properties.name, into: &chan.szName)
            self.copyTTString(properties.topic, into: &chan.szTopic)
            self.copyTTString(properties.password, into: &chan.szPassword)
            chan.nMaxUsers = properties.maxUsers
            chan.nDiskQuota = properties.diskQuotaBytes

            var chanType: UInt32 = chan.uChannelType
            // Clear the flags we manage
            let managedFlags: UInt32 = UInt32(CHANNEL_PERMANENT.rawValue)
                | UInt32(CHANNEL_SOLO_TRANSMIT.rawValue)
                | UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue)
                | UInt32(CHANNEL_NO_RECORDING.rawValue)
            chanType &= ~managedFlags
            if properties.isPermanent { chanType |= UInt32(CHANNEL_PERMANENT.rawValue) }
            if properties.isSoloTransmit { chanType |= UInt32(CHANNEL_SOLO_TRANSMIT.rawValue) }
            if properties.isNoVoiceActivation { chanType |= UInt32(CHANNEL_NO_VOICEACTIVATION.rawValue) }
            if properties.isNoRecording { chanType |= UInt32(CHANNEL_NO_RECORDING.rawValue) }
            chan.uChannelType = chanType

            if let opus = properties.opusCodec {
                chan.audiocodec.nCodec = OPUS_CODEC
                chan.audiocodec.opus.nChannels = opus.channels
                chan.audiocodec.opus.nSampleRate = opus.sampleRate
                chan.audiocodec.opus.nBitRate = opus.bitrate
                chan.audiocodec.opus.nApplication = opus.application
            }

            let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoUpdateChannel(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func deleteChannel(
        channelID: Int32,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            let commandID = TT_DoRemoveChannel(instance, channelID)
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func leaveCurrentChannel(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            let commandID = TT_DoLeaveChannel(instance)
            let previousChannelID = TT_GetMyChannelID(instance)
            guard commandID > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(TeamTalkConnectionError.connectionFailed))
                }
                return
            }

            do {
                try self.withSuppressedJoinHistoryLocked {
                    try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                }
                if previousChannelID > 0 {
                    self.appendLeftChannelHistoryLocked(channelID: previousChannelID, instance: instance)
                }
                self.refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
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
}
