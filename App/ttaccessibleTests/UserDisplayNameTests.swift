//
//  UserDisplayNameTests.swift
//  ttaccessibleTests
//
//  ConnectedServerUser.displayName is what every row, announcement and mixer
//  strip names a person by. A user with neither nickname nor account name (an
//  anonymous login) used to reduce it to an empty string — the row read as a
//  bare comma followed by the status, and the person could not be named at all.
//
//  Since the "Show people as" preference, the same resolver
//  (UserNameDisplayStyle.displayName) also serves the controller side (chat,
//  history, tree sort); these tests pin the three styles and their fallbacks.
//
//  The assertions stay off the exact wording of the placeholder so they survive
//  translation; what matters is that the name is never empty and carries the
//  user ID.
//

import XCTest
@testable import ttaccessible

final class UserDisplayNameTests: XCTestCase {

    private func makeUser(
        id: Int32 = 42,
        username: String,
        nickname: String,
        style: AppPreferences.UserNameDisplayStyle = .nicknameAndUsername
    ) -> ConnectedServerUser {
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
            channelPathComponents: [],
            nameDisplayStyle: style
        )
    }

    // MARK: - Nickname and username (default)

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

    // MARK: - Nickname only

    func testNicknameOnlyHidesTheUsername() {
        let user = makeUser(username: "jean", nickname: "Jean-Pierre", style: .nicknameOnly)
        XCTAssertEqual(user.displayName, "Jean-Pierre")
    }

    func testNicknameOnlyFallsBackToUsernameWhenNicknameIsEmpty() {
        let user = makeUser(username: "jean", nickname: "", style: .nicknameOnly)
        XCTAssertEqual(user.displayName, "jean")
    }

    // MARK: - Username only

    func testUsernameOnlyHidesTheNickname() {
        let user = makeUser(username: "jean", nickname: "Jean-Pierre", style: .usernameOnly)
        XCTAssertEqual(user.displayName, "jean")
    }

    func testUsernameOnlyFallsBackToNicknameForAnonymousLogin() {
        // An anonymous login has no account name; showing nothing is not an option.
        let user = makeUser(username: "", nickname: "Jean-Pierre", style: .usernameOnly)
        XCTAssertEqual(user.displayName, "Jean-Pierre")
    }

    // MARK: - Every style survives a user with no name at all

    func testEveryStyleNamesANamelessUser() {
        for style in AppPreferences.UserNameDisplayStyle.allCases {
            let user = makeUser(id: 7, username: "", nickname: "", style: style)
            XCTAssertFalse(user.displayName.isEmpty, "\(style)")
            XCTAssertTrue(user.displayName.contains("7"), "\(style): \(user.displayName)")
        }
    }
}

// MARK: - AppPreferences userNameDisplayStyle migration

final class UserNameDisplayStylePreferenceTests: XCTestCase {

    private func decode(_ json: String) throws -> AppPreferences {
        try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
    }

    func testDefaultsToBothWhenKeyAbsent() throws {
        // A preferences blob saved before this feature existed keeps the
        // historical "nickname (username)" rows.
        let prefs = try decode("{}")
        XCTAssertEqual(prefs.userNameDisplayStyle, .nicknameAndUsername)
    }

    func testDecodesExplicitStyle() throws {
        let prefs = try decode(#"{"userNameDisplayStyle": "usernameOnly"}"#)
        XCTAssertEqual(prefs.userNameDisplayStyle, .usernameOnly)
    }

    func testRoundTrips() throws {
        for style in AppPreferences.UserNameDisplayStyle.allCases {
            var prefs = AppPreferences()
            prefs.userNameDisplayStyle = style
            let data = try JSONEncoder().encode(prefs)
            let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
            XCTAssertEqual(decoded.userNameDisplayStyle, style)
        }
    }
}
