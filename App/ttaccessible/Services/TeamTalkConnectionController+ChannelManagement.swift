//
//  TeamTalkConnectionController+ChannelManagement.swift
//  ttaccessible
//
//  Created by Codex on 30/03/2026.
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
                if self.voiceTransmissionEnabled, self.isAnyMicrophoneEngineRunning {
                    self.refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
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
            opusCodec: codec
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
                if self.voiceTransmissionEnabled, self.isAnyMicrophoneEngineRunning {
                    self.refreshAdvancedMicrophoneTargetIfNeededLocked(instance: instance)
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
}
