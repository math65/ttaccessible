//
//  UserDisplayNameTests.swift
//  ttaccessibleTests
//
//  ConnectedServerUser.displayName is what every row, announcement and mixer
//  strip names a person by. A user with neither nickname nor account name (an
//  anonymous login) used to reduce it to an empty string — the row read as a
//  bare comma followed by the status, and the person could not be named at all.
//
//  The assertions stay off the exact wording so they survive translation; what
//  matters is that the name is never empty and carries the user ID.
//

import XCTest
@testable import ttaccessible

final class UserDisplayNameTests: XCTestCase {

    private func makeUser(id: Int32 = 42, username: String, nickname: String) -> ConnectedServerUser {
        ConnectedServerUser(
            id: id,
            username: username,
            nickname: nickname,
            channelID: 1,
            statusMode: .available,
            statusMessage: "",
            gender: .neutral,
            isCurrentUser: false,
            isAdministrator: false,
            isChannelOperator: false,
            isTalking: false,
            isMuted: false,
            isMediaFileMuted: false,
            isStreamingMediaFileVideo: false,
            isAway: false,
            isQuestion: false,
            ipAddress: "",
            clientName: "",
            clientVersion: "",
            volumeVoice: 0,
            volumeMediaFile: 0,
            subscriptionStates: [:],
            channelPathComponents: []
        )
    }

    func testNicknameAndUsernameAreShownTogether() {
        let user = makeUser(username: "jean", nickname: "Jean-Pierre")
        XCTAssertEqual(user.displayName, "Jean-Pierre (jean)")
    }

    func testSameNicknameAndUsernameIsShownOnce() {
        let user = makeUser(username: "dom", nickname: "Dom")
        XCTAssertEqual(user.displayName, "Dom")
    }

    func testAnonymousUserFallsBackToUsername() {
        let user = makeUser(username: "jean", nickname: "")
        XCTAssertEqual(user.displayName, "jean")
    }

    func testUserWithNoNameAtAllStillHasADisplayName() {
        let user = makeUser(id: 7, username: "", nickname: "")
        XCTAssertFalse(user.displayName.isEmpty)
        XCTAssertTrue(user.displayName.contains("7"), "the fallback must carry the user ID: \(user.displayName)")
    }

    func testFallbackNameIsUniquePerUser() {
        let first = makeUser(id: 7, username: "", nickname: "")
        let second = makeUser(id: 8, username: "", nickname: "")
        XCTAssertNotEqual(first.displayName, second.displayName)
    }
}
