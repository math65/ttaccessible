//
//  StreamSourceCatalogTests.swift
//  ttaccessibleTests
//
//  The stream-source list's search and its Recently used group. The search is how a long
//  list of running applications stays usable by ear; Recently used is what makes the usual
//  choice one line away. Both are plain data, pinned here.
//

import XCTest
@testable import ttaccessible

final class StreamSourceCatalogTests: XCTestCase {

    private let music = DeviceStreamCaptureSpec.application(bundleID: "com.apple.Music", displayName: "Music")
    private let safari = DeviceStreamCaptureSpec.application(bundleID: "com.apple.Safari", displayName: "Safari")
    private let cafe = DeviceStreamCaptureSpec.application(bundleID: "com.example.cafe", displayName: "Café Radio")

    private func catalog(recent: [DeviceStreamCaptureSpec] = []) -> StreamSourceCatalog {
        StreamSourceCatalog(systemAudio: .systemAudio(), recent: recent, devices: [],
                            applications: [music, safari, cafe])
    }

    // MARK: Search

    func testAnEmptyQueryKeepsEverythingButEmptyGroups() {
        let result = catalog(recent: [music]).filtered(by: "  ")
        XCTAssertEqual(result.systemAudio, .systemAudio())
        XCTAssertEqual(result.sections.map(\.group), [.recent, .applications], "no devices, so no Devices group")
        XCTAssertEqual(result.sections.last?.sources, [music, safari, cafe])
    }

    func testTheSearchIgnoresCaseAndAccents() {
        XCTAssertEqual(catalog().filtered(by: "MUS").sections.first?.sources, [music])
        XCTAssertEqual(catalog().filtered(by: "cafe").sections.first?.sources, [cafe])
    }

    func testAGroupWithNoMatchIsLeftOut() {
        let result = catalog(recent: [music]).filtered(by: "safari")
        XCTAssertEqual(result.sections.map(\.group), [.applications])
        XCTAssertNil(result.systemAudio)
    }

    func testTheSearchFindsTheSameSourceInEveryGroupItIsIn() {
        let result = catalog(recent: [music]).filtered(by: "music")
        XCTAssertEqual(result.sections.map(\.group), [.recent, .applications])
    }

    // MARK: Recently used

    func testStreamingPutsTheSourceFirstWithoutRepeats() {
        XCTAssertEqual(StreamSourceCatalog.recentTokens(["app:a", "voiceover", "app:b"], afterStreaming: "voiceover"),
                       ["voiceover", "app:a", "app:b"])
    }

    func testACumulatedStreamIsRememberedOneSourceAtATime() {
        XCTAssertEqual(StreamSourceCatalog.recentTokens(["device:x"], afterStreaming: "multi:app:a+voiceover"),
                       ["app:a", "voiceover", "device:x"])
    }

    func testTheListStopsAtItsLimit() {
        let old = (1...9).map { "app:\($0)" }
        let updated = StreamSourceCatalog.recentTokens(old, afterStreaming: "voiceover")
        XCTAssertEqual(updated.count, StreamSourceCatalog.recentLimit)
        XCTAssertEqual(updated.first, "voiceover")
    }

    func testRecentTokensResolveToWhatIsOnOffer() {
        let resolved = StreamSourceCatalog.resolveRecent(
            tokens: ["app:com.apple.Safari", "device:gone", "app:com.apple.Music"],
            available: [music, safari],
            resolveMissing: { _ in nil })
        XCTAssertEqual(resolved, [safari, music], "the unplugged device is left out, the order kept")
    }

    func testAnApplicationNotRunningCanStillBeOffered() {
        let waited = DeviceStreamCaptureSpec.application(bundleID: "com.example.later", displayName: "Later")
        let resolved = StreamSourceCatalog.resolveRecent(
            tokens: ["app:com.example.later"], available: [music],
            resolveMissing: { $0 == "app:com.example.later" ? waited : nil })
        XCTAssertEqual(resolved, [waited])
    }

    // MARK: Checked sources stay in reach

    private let mic = DeviceStreamCaptureSpec.inputDevice(
        InputAudioDeviceInfo(uid: "BuiltInMic", name: "Microphone", inputChannels: 1, nominalSampleRate: 48_000))

    private func catalogWithDevices(recent: [DeviceStreamCaptureSpec] = []) -> StreamSourceCatalog {
        StreamSourceCatalog(systemAudio: .systemAudio(), recent: recent, devices: [mic],
                            applications: [music, safari])
    }

    func testACheckedDeviceOpensTheDevicesGroup() {
        // A fresh profile preselects the default input: it must not sit in a closed group.
        XCTAssertEqual(catalogWithDevices().groupsRevealing([mic], open: [.recent]), [.recent, .devices])
    }

    func testACheckedApplicationOpensTheApplicationsGroup() {
        XCTAssertEqual(catalogWithDevices().groupsRevealing([mic, safari], open: []),
                       [.devices, .applications])
    }

    func testASourceShownInAnOpenRecentGroupOpensNothingMore() {
        XCTAssertEqual(catalogWithDevices(recent: [mic]).groupsRevealing([mic], open: [.recent]), [.recent])
    }

    func testAllAudioNeedsNoGroup() {
        XCTAssertEqual(catalogWithDevices().groupsRevealing([.systemAudio()], open: []), [])
    }

    func testAnApplicationOnlyInRecentOpensRecent() {
        let waited = DeviceStreamCaptureSpec.application(bundleID: "com.example.later", displayName: "Later")
        XCTAssertEqual(catalogWithDevices(recent: [waited]).groupsRevealing([waited], open: []), [.recent])
    }
}
