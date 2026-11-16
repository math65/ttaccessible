//
//  UserVolumeMemoryNameTests.swift
//  ttaccessibleTests
//
//  Guests (anonymous logins) have no username, and every level they were given used to be
//  dropped: nothing was saved, so nothing came back after a reconnect. They are remembered
//  by nickname now, under a key no account can collide with.
//

import XCTest
@testable import ttaccessible

final class UserVolumeMemoryNameTests: XCTestCase {

    private let suite = "ttaccessible.tests.guestVolumeMemory"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAnAccountIsRememberedByItsUsername() {
        XCTAssertEqual(UserVolumeStore.memoryName(username: "chris", nickname: "Chris B"), "chris")
    }

    func testAGuestIsRememberedByNicknameApartFromAnyAccount() {
        let guest = UserVolumeStore.memoryName(username: "", nickname: "chris")
        XCTAssertFalse(guest.isEmpty)
        XCTAssertNotEqual(guest, UserVolumeStore.memoryName(username: "chris", nickname: "x"))
    }

    func testANamelessGuestIsNotRemembered() {
        XCTAssertEqual(UserVolumeStore.memoryName(username: "", nickname: "  "), "")
    }

    func testAGuestsLevelsComeBackOnTheSameServer() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let guest = UserVolumeStore.memoryName(username: "", nickname: "Arianna")

        let before = UserVolumeStore(defaults: defaults)
        before.setServerScope("example.org:10333")
        before.setVolume(900, forUsername: guest)
        before.setVoicePan(-0.4, forUsername: guest)

        let after = UserVolumeStore(defaults: defaults)       // a relaunch
        after.setServerScope("example.org:10333")
        XCTAssertEqual(after.volume(forUsername: guest), 900)
        XCTAssertEqual(try XCTUnwrap(after.voicePan(forUsername: guest)), -0.4, accuracy: 0.0001)
        XCTAssertNil(after.volume(forUsername: "Arianna"), "an account named Arianna is someone else")
    }
}
