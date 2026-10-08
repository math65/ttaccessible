//
//  TransmitUsersListTests.swift
//  ttaccessibleTests
//
//  The "Transmit Control" menu edits one list whose meaning flips with
//  CHANNEL_CLASSROOM: listed = allowed in a classroom, listed = blocked
//  everywhere else (the server's `Channel::CanTransmit`). Ticking "Allow" must
//  therefore ADD an entry in one kind of channel and REMOVE it in the other —
//  get it backwards and the menu silences the person it meant to give the
//  floor to. Also pinned: the C array round trip, and that only the toggled
//  stream's bits move.
//

import XCTest
@testable import ttaccessible

final class TransmitUsersListTests: XCTestCase {

    private let voice = UInt32(STREAMTYPE_VOICE.rawValue)
    private let channelMessages = UInt32(STREAMTYPE_CHANNELMSG.rawValue)
    private let mediaFile = UInt32(STREAMTYPE_MEDIAFILE.rawValue)
    private let mediaFileAudio = UInt32(STREAMTYPE_MEDIAFILE_AUDIO.rawValue)

    // MARK: - Reading

    func testClassroomAllowsOnlyListedUsers() {
        let list = TransmitUsersList(isClassroom: true, entries: [.init(userID: 7, streamTypes: voice)])
        XCTAssertTrue(list.isAllowed(.voice, userID: 7))
        XCTAssertFalse(list.isAllowed(.voice, userID: 8))
        XCTAssertFalse(list.isAllowed(.channelMessages, userID: 7))
    }

    func testOrdinaryChannelBlocksOnlyListedUsers() {
        let list = TransmitUsersList(isClassroom: false, entries: [.init(userID: 7, streamTypes: voice)])
        XCTAssertFalse(list.isAllowed(.voice, userID: 7))
        XCTAssertTrue(list.isAllowed(.voice, userID: 8))
        XCTAssertTrue(list.isAllowed(.channelMessages, userID: 7))
    }

    /// "Everyone" is its own line, as in the Qt client: it does not tick the
    /// per-user line, and outside a classroom it means nothing.
    func testEveryoneIsReadSeparately() {
        let entries = [TransmitUsersList.Entry(userID: TransmitUsersList.everyoneUserID, streamTypes: voice)]
        let classroom = TransmitUsersList(isClassroom: true, entries: entries)
        XCTAssertTrue(classroom.isAllowedForEveryone(.voice))
        XCTAssertFalse(classroom.isAllowed(.voice, userID: 7))
        XCTAssertFalse(TransmitUsersList(isClassroom: false, entries: entries).isAllowedForEveryone(.voice))
    }

    // MARK: - Editing

    func testAllowingInClassroomAddsEntry() throws {
        let list = try XCTUnwrap(TransmitUsersList(isClassroom: true).setting(.voice, allowed: true, userID: 7))
        XCTAssertEqual(list.entries, [.init(userID: 7, streamTypes: voice)])
        XCTAssertTrue(list.isAllowed(.voice, userID: 7))
    }

    func testBlockingInOrdinaryChannelAddsEntry() throws {
        let list = try XCTUnwrap(TransmitUsersList(isClassroom: false).setting(.voice, allowed: false, userID: 7))
        XCTAssertEqual(list.entries, [.init(userID: 7, streamTypes: voice)])
        XCTAssertFalse(list.isAllowed(.voice, userID: 7))
    }

    func testAllowingInOrdinaryChannelRemovesTheBlock() throws {
        let blocked = TransmitUsersList(isClassroom: false, entries: [.init(userID: 7, streamTypes: voice)])
        let list = try XCTUnwrap(blocked.setting(.voice, allowed: true, userID: 7))
        XCTAssertTrue(list.entries.isEmpty, "an entry with no stream left frees its slot")
        XCTAssertTrue(list.isAllowed(.voice, userID: 7))
    }

    /// Toggling voice must not touch the other streams of the same entry —
    /// including bits another client wrote that this menu has no line for.
    func testOnlyTheToggledStreamMoves() throws {
        let unknownBit: UInt32 = 0x0100_0000
        let start = TransmitUsersList(
            isClassroom: true,
            entries: [.init(userID: 7, streamTypes: voice | channelMessages | unknownBit)]
        )
        let list = try XCTUnwrap(start.setting(.voice, allowed: false, userID: 7))
        XCTAssertEqual(list.entries, [.init(userID: 7, streamTypes: channelMessages | unknownBit)])
    }

    /// A media file is audio and video together: one line sets both bits, and
    /// either bit alone already counts as listed (the Qt client's test).
    func testMediaFileCoversAudioAndVideo() throws {
        let list = try XCTUnwrap(TransmitUsersList(isClassroom: true).setting(.mediaFile, allowed: true, userID: 7))
        XCTAssertEqual(list.entries.first?.streamTypes, mediaFile)
        let audioOnly = TransmitUsersList(isClassroom: true, entries: [.init(userID: 7, streamTypes: mediaFileAudio)])
        XCTAssertTrue(audioOnly.isAllowed(.mediaFile, userID: 7))
        let cleared = try XCTUnwrap(audioOnly.setting(.mediaFile, allowed: false, userID: 7))
        XCTAssertTrue(cleared.entries.isEmpty)
    }

    func testNoOpLeavesListUnchanged() throws {
        let list = TransmitUsersList(isClassroom: true, entries: [.init(userID: 7, streamTypes: voice)])
        XCTAssertEqual(try XCTUnwrap(list.setting(.voice, allowed: true, userID: 7)), list)
        XCTAssertEqual(try XCTUnwrap(list.setting(.voice, allowed: false, userID: 8)), list)
    }

    func testFullListRefusesNewEntryButStillEditsExistingOnes() throws {
        let entries = (1 ... Int32(TransmitUsersList.capacity)).map {
            TransmitUsersList.Entry(userID: $0, streamTypes: voice)
        }
        let full = TransmitUsersList(isClassroom: true, entries: entries)
        XCTAssertNil(full.setting(.voice, allowed: true, userID: 9999))
        let edited = try XCTUnwrap(full.setting(.channelMessages, allowed: true, userID: 1))
        XCTAssertEqual(edited.entries.first?.streamTypes, voice | channelMessages)
        XCTAssertEqual(try XCTUnwrap(full.setting(.voice, allowed: false, userID: 1)).entries.count, entries.count - 1)
    }

    // MARK: - C array round trip

    func testRoundTripThroughChannel() {
        var channel = Channel()
        channel.uChannelType = UInt32(CHANNEL_CLASSROOM.rawValue)
        let list = TransmitUsersList(isClassroom: true, entries: [
            .init(userID: 7, streamTypes: voice),
            .init(userID: TransmitUsersList.everyoneUserID, streamTypes: channelMessages),
        ])
        list.write(into: &channel)
        XCTAssertEqual(TransmitUsersList(channel: &channel), list)
    }

    /// Writing a shorter list must clear what the longer one left behind, or
    /// a removed user would come back from the stale slots.
    func testWritingShorterListClearsOldSlots() {
        var channel = Channel()
        TransmitUsersList(isClassroom: false, entries: [
            .init(userID: 7, streamTypes: voice),
            .init(userID: 8, streamTypes: voice),
        ]).write(into: &channel)
        let shorter = TransmitUsersList(isClassroom: false, entries: [.init(userID: 8, streamTypes: voice)])
        shorter.write(into: &channel)
        XCTAssertEqual(TransmitUsersList(channel: &channel), shorter)
    }
}
