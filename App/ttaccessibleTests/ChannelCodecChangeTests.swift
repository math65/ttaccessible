//
//  ChannelCodecChangeTests.swift
//  ttaccessibleTests
//
//  Editing a channel must not touch its codec unless the form really changed
//  it: the server refuses any codec change while the channel has users
//  (CHANNEL_HAS_USERS), so a stray difference makes even a topic edit fail.
//  The trap is the bitrate — the form shows whole kbps and writes kbps × 1000,
//  so a channel at 32500 bps comes back as 32000 without anyone touching it.
//

import XCTest
@testable import ttaccessible

final class ChannelCodecChangeTests: XCTestCase {

    private func channelCodec(channels: Int32 = 1, sampleRate: Int32 = 48000,
                              bitrate: Int32 = 32000, application: Int32 = 2048) -> OpusCodec {
        var codec = OpusCodec()
        codec.nChannels = channels
        codec.nSampleRate = sampleRate
        codec.nBitRate = bitrate
        codec.nApplication = application
        return codec
    }

    private func formCodec(channels: Int32 = 1, sampleRate: Int32 = 48000,
                           bitrate: Int32 = 32000, application: Int32 = 2048) -> OpusCodecSettings {
        OpusCodecSettings(channels: channels, sampleRate: sampleRate, bitrate: bitrate, application: application)
    }

    func testUntouchedFormIsNotAChange() {
        XCTAssertFalse(TeamTalkConnectionController.opusCodecChanged(channelCodec(), to: formCodec()))
    }

    func testBitrateRoundedByTheFormIsNotAChange() {
        // 32500 bps is shown as "32" and written back as 32000.
        XCTAssertFalse(TeamTalkConnectionController.opusCodecChanged(
            channelCodec(bitrate: 32500), to: formCodec(bitrate: 32000)
        ))
    }

    func testEachEditedFieldIsAChange() {
        let current = channelCodec()
        XCTAssertTrue(TeamTalkConnectionController.opusCodecChanged(current, to: formCodec(channels: 2)))
        XCTAssertTrue(TeamTalkConnectionController.opusCodecChanged(current, to: formCodec(sampleRate: 24000)))
        XCTAssertTrue(TeamTalkConnectionController.opusCodecChanged(current, to: formCodec(bitrate: 64000)))
        XCTAssertTrue(TeamTalkConnectionController.opusCodecChanged(current, to: formCodec(application: 2049)))
    }
}
