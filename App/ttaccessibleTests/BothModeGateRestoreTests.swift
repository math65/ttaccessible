//
//  BothModeGateRestoreTests.swift
//  ttaccessibleTests
//
//  "Both" mode keeps the capture engine hot behind a gate, so the gate — not the
//  engine — is the user's mic switch. That gate lived only in memory: the engine
//  dies with the session, and the rearm that follows every join is deliberately
//  gate-closed, so a reconnect always came back mute however the user had left
//  it. Reported from the field as "I reconnect and the mic is still off", and it
//  hit this one mode only: always-on and push-to-talk restore themselves from
//  `lastVoiceTransmissionEnabled`.
//
//  What the rule below must get right is the difference between a session that
//  ended and a channel that merely changed — the second keeps the engine, and
//  rewriting the gate under it would open a mic the user had closed.
//

import XCTest
@testable import ttaccessible

final class BothModeGateRestoreTests: XCTestCase {

    // MARK: - Fresh session: the persisted intent decides

    /// The bug: mic open, disconnect, reconnect. Engine cold on the way back.
    func testReconnectRestoresGateTheUserHadOpen() {
        XCTAssertTrue(TeamTalkConnectionController.shouldRestoreBothModeGate(
            engineWasHot: false, reopenAfterSilentChannel: false, lastVoiceTransmissionEnabled: true
        ))
    }

    /// The other half of the same rule: a mic left closed stays closed. Opening
    /// one without the user asking is the worse failure of the two.
    func testReconnectLeavesGateClosedWhenTheUserHadClosedIt() {
        XCTAssertFalse(TeamTalkConnectionController.shouldRestoreBothModeGate(
            engineWasHot: false, reopenAfterSilentChannel: false, lastVoiceTransmissionEnabled: false
        ))
    }

    // MARK: - Same session: the engine is what tells them apart

    /// A plain channel change returns early from the arm and keeps the gate the
    /// user set. The persisted intent must not overrule it — someone who closed
    /// the mic in this session would have it reopened under them at every hop.
    func testChannelChangeWithHotEngineDoesNotRewriteTheGate() {
        XCTAssertFalse(TeamTalkConnectionController.shouldRestoreBothModeGate(
            engineWasHot: true, reopenAfterSilentChannel: false, lastVoiceTransmissionEnabled: true
        ))
    }

    /// Leaving a channel that carries no voice gives back the mic that channel
    /// took. The engine was torn down there, so this arrives engine-cold too, but
    /// the flag is what carries the intent — it was set from the live gate.
    func testLeavingASilentChannelGivesTheGateBack() {
        XCTAssertTrue(TeamTalkConnectionController.shouldRestoreBothModeGate(
            engineWasHot: false, reopenAfterSilentChannel: true, lastVoiceTransmissionEnabled: false
        ))
    }

    /// The silent-channel guard can also fire without tearing the engine down for
    /// good — the flag stands on its own and does not need a cold engine.
    func testSilentChannelFlagWinsOverAHotEngine() {
        XCTAssertTrue(TeamTalkConnectionController.shouldRestoreBothModeGate(
            engineWasHot: true, reopenAfterSilentChannel: true, lastVoiceTransmissionEnabled: false
        ))
    }
}
