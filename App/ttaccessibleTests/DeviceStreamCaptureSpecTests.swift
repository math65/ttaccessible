//
//  DeviceStreamCaptureSpecTests.swift
//  ttaccessibleTests
//
//  The stream-source picker saves what you picked as one token and rebuilds the
//  selection from it next time. Several applications — VoiceOver counts as one —
//  fuse into a single "multi:" token; a device or all-system audio never fuses.
//  None of that had a test, and it is the whole of "your last choice is ticked
//  again next time".
//

import XCTest
@testable import ttaccessible

final class DeviceStreamCaptureSpecTests: XCTestCase {

    private let music = DeviceStreamCaptureSpec.application(bundleID: "com.apple.Music", displayName: "Music")
    private let safari = DeviceStreamCaptureSpec.application(bundleID: "com.apple.Safari", displayName: "Safari")

    func testNothingToStreamMergesToNil() {
        XCTAssertNil(DeviceStreamCaptureSpec.merging([]))
    }

    func testASingleApplicationIsReturnedUnchanged() {
        XCTAssertEqual(DeviceStreamCaptureSpec.merging([music]), music)
    }

    func testSeveralApplicationsFuseIntoOneMultiToken() {
        let merged = DeviceStreamCaptureSpec.merging([music, .voiceOver()])
        XCTAssertEqual(merged?.persistenceToken, "multi:app:com.apple.Music+voiceover")
    }

    func testAFusedSelectionCapturesEachPrefixOnce() {
        guard case .processes(let selection)? = DeviceStreamCaptureSpec.merging([music, safari, music]) else {
            return XCTFail("expected a process selection")
        }
        XCTAssertEqual(selection.bundleIDPrefixes, ["com.apple.Music", "com.apple.Safari"])
    }

    func testAllSystemAudioNeverFuses() {
        XCTAssertNil(DeviceStreamCaptureSpec.merging([.systemAudio()]))
        XCTAssertEqual(DeviceStreamCaptureSpec.merging([.systemAudio(), music]), music)
    }

    func testAMultiTokenSplitsBackIntoItsParts() {
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: "multi:app:com.apple.Music+voiceover"),
                       ["app:com.apple.Music", "voiceover"])
    }

    func testAPlainTokenIsItsOwnOnlyPart() {
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: "voiceover"), ["voiceover"])
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: "device:BuiltInMic"), ["device:BuiltInMic"])
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: "system"), ["system"])
    }

    func testFusingThenSplittingGivesBackEverySourceInOrder() {
        let picked = [music, .voiceOver(), safari]
        let token = DeviceStreamCaptureSpec.merging(picked)?.persistenceToken ?? ""
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: token), picked.map(\.persistenceToken))
    }

    // MARK: Combining devices and applications
    //
    // Any mix of devices and applications streams together; all audio from this Mac goes
    // with devices but not with applications, which it already contains.

    private let mic = DeviceStreamCaptureSpec.inputDevice(
        InputAudioDeviceInfo(uid: "BuiltInMic", name: "Microphone", inputChannels: 1, nominalSampleRate: 48_000))
    private let interface = DeviceStreamCaptureSpec.inputDevice(
        InputAudioDeviceInfo(uid: "iD44", name: "Audient iD44", inputChannels: 22, nominalSampleRate: 96_000))

    func testALoneSourceIsStreamedAsItself() {
        XCTAssertNil(DeviceStreamCaptureSpec.combining([]))
        XCTAssertEqual(DeviceStreamCaptureSpec.combining([mic]), mic)
        XCTAssertEqual(DeviceStreamCaptureSpec.combining([music]), music)
        XCTAssertEqual(DeviceStreamCaptureSpec.combining([music, safari]), DeviceStreamCaptureSpec.merging([music, safari]))
    }

    func testDevicesAndApplicationsCombine() {
        guard case .combined(let parts, _)? = DeviceStreamCaptureSpec.combining([mic, music, .voiceOver()]) else {
            return XCTFail("expected a combination")
        }
        XCTAssertEqual(parts, [mic, DeviceStreamCaptureSpec.merging([music, .voiceOver()])])
    }

    func testSeveralDevicesCombine() {
        guard case .combined(let parts, _)? = DeviceStreamCaptureSpec.combining([mic, interface]) else {
            return XCTFail("expected a combination")
        }
        XCTAssertEqual(parts, [mic, interface])
    }

    func testAllAudioGoesWithDevicesButLeavesApplicationsOut() {
        guard case .combined(let parts, _)? = DeviceStreamCaptureSpec.combining([mic, .systemAudio(), music]) else {
            return XCTFail("expected a combination")
        }
        XCTAssertEqual(parts, [mic, .systemAudio()])
    }

    func testACombinationIsNamedAfterEverythingInIt() {
        let name = DeviceStreamCaptureSpec.combining([mic, music])?.displayName ?? ""
        XCTAssertTrue(name.contains("Microphone") && name.contains("Music"), name)
    }

    func testACombinationSavesAsOneTokenThatSplitsIntoEverySource() {
        let token = DeviceStreamCaptureSpec.combining([mic, music, .voiceOver()])?.persistenceToken ?? ""
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: token),
                       ["device:BuiltInMic", "app:com.apple.Music", "voiceover"])
    }

    func testADeviceWithAPlusInItsUIDSurvivesACombination() {
        // USB UIDs carry the product name verbatim: a Shure MV7+ or a Rode NT-USB+.
        let plus = DeviceStreamCaptureSpec.inputDevice(
            InputAudioDeviceInfo(uid: "AppleUSBAudioEngine:Shure:MV7+:1%2:1", name: "MV7+",
                                 inputChannels: 1, nominalSampleRate: 48_000))
        let token = DeviceStreamCaptureSpec.combining([plus, music])?.persistenceToken ?? ""
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: token),
                       ["device:AppleUSBAudioEngine:Shure:MV7+:1%2:1", "app:com.apple.Music"])
    }

    func testATokenSavedBeforeTheEscapingStillReads() {
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: "multi:device:BuiltInMic+app:com.apple.Music"),
                       ["device:BuiltInMic", "app:com.apple.Music"])
    }

    // MARK: Channels of a device

    private let desk = InputAudioDeviceInfo(uid: "Desk+1", name: "Desk", inputChannels: 6, nominalSampleRate: 48000)
    private let stereo = InputAudioDeviceInfo(uid: "USB", name: "USB", inputChannels: 2, nominalSampleRate: 48000)

    func testADeviceOffersItsLaterPairsThenEachChannel() {
        let presets = DeviceStreamCaptureSpec.channelChoices(for: desk).compactMap { spec -> InputChannelPreset? in
            guard case .deviceChannels(_, let preset) = spec else { return nil }
            return preset
        }
        XCTAssertEqual(presets, [
            .stereoPair(first: 3, second: 4), .stereoPair(first: 5, second: 6),
            .mono(channel: 1), .mono(channel: 2), .mono(channel: 3),
            .mono(channel: 4), .mono(channel: 5), .mono(channel: 6),
        ])
    }

    func testAStereoDeviceOffersNoChannelLines() {
        XCTAssertTrue(DeviceStreamCaptureSpec.channelChoices(for: stereo).isEmpty)
    }

    func testAnOddChannelCountLeavesTheLastChannelSingle() {
        let device = InputAudioDeviceInfo(uid: "Odd", name: "Odd", inputChannels: 3, nominalSampleRate: 48000)
        XCTAssertFalse(DeviceStreamCaptureSpec.channelChoices(for: device)
            .contains(.deviceChannels(device, .stereoPair(first: 3, second: 4))))
    }

    func testTwoPairsOfOneDeviceCombineAndSurviveTheirToken() throws {
        let first = DeviceStreamCaptureSpec.deviceChannels(desk, .stereoPair(first: 3, second: 4))
        let second = DeviceStreamCaptureSpec.deviceChannels(desk, .mono(channel: 5))
        let combined = try XCTUnwrap(DeviceStreamCaptureSpec.combining([.inputDevice(desk), first, second]))
        guard case .combined(let parts, _) = combined else { return XCTFail("expected a combination") }
        XCTAssertEqual(parts, [.inputDevice(desk), first, second])
        XCTAssertEqual(DeviceStreamCaptureSpec.componentTokens(of: combined.persistenceToken),
                       parts.map(\.persistenceToken))
    }

    func testAChosenChannelKeepsItsOwnNameAndToken() {
        let spec = DeviceStreamCaptureSpec.deviceChannels(desk, .stereoPair(first: 3, second: 4))
        XCTAssertNotEqual(spec.persistenceToken, DeviceStreamCaptureSpec.inputDevice(desk).persistenceToken)
        XCTAssertTrue(spec.displayName.hasPrefix("Desk"), spec.displayName)
        XCTAssertTrue(spec.displayName.contains("3"), spec.displayName)
    }
}
