//
//  VoiceTransmissionPermissionTests.swift
//  ttaccessibleTests
//
//  Whether the server will carry our voice decides whether the app may open the
//  microphone at all. Opening it where the voice is discarded is worse than
//  refusing: the app announces an open mic, plays its sound, and the user talks
//  to no one — the exact symptom the stall guard exists to prevent.
//
//  The rule below is the server's, transcribed from `Channel::CanTransmit` in
//  the TeamTalk sources rather than inferred from the SDK header. It is pinned
//  here because it reads like a bug and is not one: the SAME `transmitUsers`
//  list means opposite things either side of CHANNEL_CLASSROOM — an allow list
//  in a classroom, a block list in every other channel. Anyone "fixing" that
//  asymmetry by hand would silence users, or let them believe they are heard.
//

import XCTest
@testable import ttaccessible

final class VoiceTransmissionPermissionTests: XCTestCase {

    // MARK: - Classroom: the list grants the right to speak

    func testClassroomAllowsListedUser() {
        XCTAssertTrue(TeamTalkConnectionController.isVoiceTransmissionAllowed(
            isClassroom: true, listedForVoice: true, freeForAllForVoice: false
        ))
    }

    func testClassroomSilencesUnlistedUser() {
        XCTAssertFalse(TeamTalkConnectionController.isVoiceTransmissionAllowed(
            isClassroom: true, listedForVoice: false, freeForAllForVoice: false
        ))
    }

    /// TT_CLASSROOM_FREEFORALL in the list opens the channel to everyone in it.
    func testClassroomFreeForAllAllowsUnlistedUser() {
        XCTAssertTrue(TeamTalkConnectionController.isVoiceTransmissionAllowed(
            isClassroom: true, listedForVoice: false, freeForAllForVoice: true
        ))
    }

    // MARK: - Ordinary channel: the very same list takes it away

    func testOrdinaryChannelSilencesListedUser() {
        XCTAssertFalse(TeamTalkConnectionController.isVoiceTransmissionAllowed(
            isClassroom: false, listedForVoice: true, freeForAllForVoice: false
        ))
    }

    func testOrdinaryChannelAllowsUnlistedUser() {
        XCTAssertTrue(TeamTalkConnectionController.isVoiceTransmissionAllowed(
            isClassroom: false, listedForVoice: false, freeForAllForVoice: false
        ))
    }

    /// Free-for-all is a classroom notion; outside one it grants nothing, and in
    /// particular never rescues a user the block list has silenced.
    func testOrdinaryChannelIgnoresFreeForAll() {
        XCTAssertFalse(TeamTalkConnectionController.isVoiceTransmissionAllowed(
            isClassroom: false, listedForVoice: true, freeForAllForVoice: true
        ))
    }

    // MARK: Changes while we sit in the channel

    func testAnOperatorTakingTheFloorIsALoss() {
        XCTAssertEqual(TeamTalkConnectionController.voiceRightChange(
            previous: (channelID: 5, allowed: true), channelID: 5, allowed: false), .lost)
    }

    func testAnOperatorGivingTheFloorIsARegain() {
        XCTAssertEqual(TeamTalkConnectionController.voiceRightChange(
            previous: (channelID: 5, allowed: false), channelID: 5, allowed: true), .regained)
    }

    func testJoiningAnotherChannelIsNotAChange() {
        XCTAssertEqual(TeamTalkConnectionController.voiceRightChange(
            previous: (channelID: 5, allowed: true), channelID: 6, allowed: false), .none)
        XCTAssertEqual(TeamTalkConnectionController.voiceRightChange(
            previous: nil, channelID: 6, allowed: false), .none)
    }

    func testAnUpdateThatLeavesTheRightAloneIsNotAChange() {
        XCTAssertEqual(TeamTalkConnectionController.voiceRightChange(
            previous: (channelID: 5, allowed: true), channelID: 5, allowed: true), .none)
    }

    // MARK: Stream types

    func testTheListIsReadPerStreamType() {
        var channel = Channel()
        withUnsafeMutableBytes(of: &channel.transmitUsers) { raw in
            let entries = raw.bindMemory(to: Int32.self)
            entries[Int(TT_TRANSMITUSERS_USERID_INDEX)] = 7
            entries[Int(TT_TRANSMITUSERS_STREAMTYPE_INDEX)] = Int32(STREAMTYPE_VOICE.rawValue)
        }
        let voice = UInt32(STREAMTYPE_VOICE.rawValue)
        let media = UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue)
        XCTAssertTrue(TeamTalkConnectionController.transmitUsersAllow(voice, in: &channel, userID: 7))
        XCTAssertFalse(TeamTalkConnectionController.transmitUsersAllow(media, in: &channel, userID: 7))
        XCTAssertFalse(TeamTalkConnectionController.transmitUsersAllow(voice, in: &channel, userID: 8))
    }
}
