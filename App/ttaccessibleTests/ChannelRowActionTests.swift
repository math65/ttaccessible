import XCTest
@testable import ttaccessible

@MainActor
final class ChannelRowActionTests: XCTestCase {
    private let serverID = UUID()
    private func user(_ id: Int32, name: String) -> ConnectedServerUser {
        ConnectedServerUser(id: id, username: name, nickname: name, channelID: 1,
            statusMode: .available, statusMessage: "", gender: .neutral,
            isCurrentUser: false, isAdministrator: false, isChannelOperator: false,
            isTalking: false, isMuted: false, isMediaFileMuted: false,
            isStreamingMediaFileVideo: false, isAway: false, isQuestion: false,
            ipAddress: "", clientName: "", clientVersion: "", volumeVoice: 1000,
            volumeMediaFile: 1000, subscriptionStates: [:], channelPathComponents: [],
            nameDisplayStyle: .nicknameOnly)
    }

    private func session(_ users: [ConnectedServerUser]) -> ConnectedServerSession {
        let channel = ConnectedServerChannel(id: 1, parentID: 0, name: "Test", topic: "",
            isPasswordProtected: false, isHidden: false, isCurrentChannel: true,
            pathComponents: ["Test"], children: [], users: users, canMoveUsersOut: false,
            transmitUsers: TransmitUsersList(isClassroom: false), canControlTransmission: false)
        return ConnectedServerSession(savedServer: SavedServerRecord(id: serverID, name: "Test",
            host: "invalid.example", tcpPort: 10333, udpPort: 10333, encrypted: false,
            nickname: "", username: ""), displayName: "Test", currentNickname: "",
            currentStatusMode: .available, currentStatusMessage: "", currentGender: .neutral,
            statusText: "", currentChannelID: 1, isAdministrator: false,
            rootChannels: [channel], usersWithoutChannel: [], channelChatHistory: [],
            sessionHistory: [], privateConversations: [], selectedPrivateConversationUserID: nil,
            channelFiles: [], activeTransfers: [], outputAudioReady: false, inputAudioReady: false,
            voiceTransmissionEnabled: false, canSendBroadcast: false, canBanUsers: false,
            canKickUsers: false, isNicknameLocked: false, isStatusLocked: false, audioStatusText: "",
            inputGainDB: 0, outputGainDB: 0, recordingActive: false, mediaStreamingActive: false,
            mediaStreamingFileName: nil, mediaStreamingHasVideo: false)
    }

    private func makeController(_ users: [ConnectedServerUser]) -> ConnectedServerViewController {
        let defaults = UserDefaults(suiteName: "ttaccessible.tests.row-actions")!
        let preferences = AppPreferencesStore(userDefaults: defaults)
        let connection = TeamTalkConnectionController(preferencesStore: preferences,
            passwordStore: ServerPasswordStore(serviceName: "ttaccessible.tests.row-actions", defaults: defaults))
        let controller = ConnectedServerViewController(session: session(users),
            preferencesStore: preferences, connectionController: connection,
            menuState: .shared, appDelegate: AppDelegate())
        _ = controller.view
        controller.outlineView.expandItem(nil, expandChildren: true)
        return controller
    }

    private func muteAction(_ controller: ConnectedServerViewController,
                            user: ConnectedServerUser) throws -> NSAccessibilityCustomAction {
        let cell = try XCTUnwrap(controller.outlineView(controller.outlineView,
            viewFor: nil, item: ServerTreeNode.user(user)))
        return try XCTUnwrap(cell.accessibilityCustomActions()?.first {
            $0.name == L10n.text("connectedServer.menu.muteUser")
        })
    }

    func testVoiceOverActionTargetsItsRowNotKeyboardSelection() throws {
        let alice = user(7, name: "Alice"), bob = user(8, name: "Bob")
        let controller = makeController([alice, bob])
        XCTAssertTrue(controller.selectNode(matching: .user(bob.id)))
        let action = try muteAction(controller, user: alice)
        XCTAssertTrue(try XCTUnwrap(action.handler)())
        XCTAssertEqual(controller.localMuteState[alice.id], true)
        XCTAssertNil(controller.localMuteState[bob.id], "Never act on another keyboard-selected person")
    }

    func testRemovedRowDoesNotFallThroughToAnotherUser() throws {
        let alice = user(7, name: "Alice"), bob = user(8, name: "Bob")
        let controller = makeController([alice, bob])
        XCTAssertTrue(controller.selectNode(matching: .user(bob.id)))
        let action = try muteAction(controller, user: alice)
        controller.session = session([bob])
        XCTAssertFalse(try XCTUnwrap(action.handler)())
        XCTAssertTrue(controller.localMuteState.isEmpty)
    }
    func testReusedUserIDDoesNotReceiveStaleAction() throws {
        let alice = user(7, name: "Alice"), bob = user(8, name: "Bob")
        let controller = makeController([alice, bob])
        let action = try muteAction(controller, user: alice)
        controller.session = session([user(7, name: "Someone else"), bob])
        XCTAssertFalse(try XCTUnwrap(action.handler)())
        XCTAssertTrue(controller.localMuteState.isEmpty)
    }

}
