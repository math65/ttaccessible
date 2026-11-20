//
//  ChannelInputGainTests.swift
//  ttaccessibleTests
//
//  A channel can impose the microphone gain. Its level is read on the official clients'
//  scale (0–32000 up to 49.9 dB), held to what our gain stage can do without clipping.
//

import XCTest
@testable import ttaccessible

final class ChannelInputGainTests: XCTestCase {

    func testAChannelThatImposesNothingLeavesTheGainToTheUser() {
        XCTAssertNil(TeamTalkConnectionController.channelInputGainDB(enabled: false, level: 9600))
    }

    func testTheOfficialDefaultLevelIsFifteenDecibels() throws {
        let gain = try XCTUnwrap(TeamTalkConnectionController.channelInputGainDB(enabled: true, level: 9600))
        XCTAssertEqual(gain, 14.97, accuracy: 0.01)
    }

    func testLevelZeroIsUnityNotSilence() {
        XCTAssertEqual(TeamTalkConnectionController.channelInputGainDB(enabled: true, level: 0), 0)
    }

    func testALevelPastTheSliderStopsAtItsTop() {
        XCTAssertEqual(TeamTalkConnectionController.channelInputGainDB(enabled: true, level: 32000),
                       AppPreferences.maxGainDB)
    }

    func testAnOutOfRangeLevelIsHeldInRange() {
        XCTAssertEqual(TeamTalkConnectionController.channelInputGainDB(enabled: true, level: -5), 0)
        XCTAssertEqual(TeamTalkConnectionController.channelInputGainDB(enabled: true, level: 40000),
                       AppPreferences.maxGainDB)
    }
}
