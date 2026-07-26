//
//  PreferencesAndAudioMathTests.swift
//  ttaccessibleTests
//
//  POC unit tests for pure / deterministic logic:
//   - gain dB <-> percent curve (AudioGainControlView, AppPreferences.clampGainDB)
//   - user volume <-> percent piecewise-linear curve (TeamTalkConnectionController)
//   - Codable migrations of preference structs (legacy-key handling)
//
//  These cover regression-prone math and decoding. They do NOT touch AppKit UI,
//  CoreAudio, or the TeamTalk SDK runtime — those stay verified manually.
//

import XCTest
@testable import ttaccessible

// MARK: - Gain dB <-> percent curve

final class GainCurveTests: XCTestCase {

    func testPercentForGainDBAnchors() {
        XCTAssertEqual(AudioGainControlView.percent(forGainDB: -24), 0, accuracy: 0.001)
        XCTAssertEqual(AudioGainControlView.percent(forGainDB: 0), 50, accuracy: 0.001)
        XCTAssertEqual(AudioGainControlView.percent(forGainDB: 24), 100, accuracy: 0.001)
    }

    func testPercentForGainDBClampsOutOfRange() {
        XCTAssertEqual(AudioGainControlView.percent(forGainDB: -100), 0, accuracy: 0.001)
        XCTAssertEqual(AudioGainControlView.percent(forGainDB: 100), 100, accuracy: 0.001)
    }

    func testGainDBForPercentAnchors() {
        XCTAssertEqual(AudioGainControlView.gainDB(forPercent: 0), -24, accuracy: 0.001)
        XCTAssertEqual(AudioGainControlView.gainDB(forPercent: 50), 0, accuracy: 0.001)
        XCTAssertEqual(AudioGainControlView.gainDB(forPercent: 100), 24, accuracy: 0.001)
    }

    func testGainDBForPercentClampsOutOfRange() {
        XCTAssertEqual(AudioGainControlView.gainDB(forPercent: -10), -24, accuracy: 0.001)
        XCTAssertEqual(AudioGainControlView.gainDB(forPercent: 150), 24, accuracy: 0.001)
    }

    func testGainRoundTrip() {
        for percent in stride(from: 0.0, through: 100.0, by: 5.0) {
            let db = AudioGainControlView.gainDB(forPercent: percent)
            let back = AudioGainControlView.percent(forGainDB: db)
            XCTAssertEqual(back, percent, accuracy: 0.5, "round-trip failed at \(percent)%")
        }
    }

    func testFormatPercentClampsAndFormats() {
        XCTAssertEqual(AudioGainControlView.format(percent: 50), "50%")
        XCTAssertEqual(AudioGainControlView.format(percent: -5), "0%")
        XCTAssertEqual(AudioGainControlView.format(percent: 150), "100%")
        XCTAssertEqual(AudioGainControlView.format(percent: 49.6), "50%") // rounds up
    }
}

// MARK: - clampGainDB

final class ClampGainDBTests: XCTestCase {

    func testClampBounds() {
        XCTAssertEqual(AppPreferences.clampGainDB(-100), -24, accuracy: 0.0001)
        XCTAssertEqual(AppPreferences.clampGainDB(100), 24, accuracy: 0.0001)
        XCTAssertEqual(AppPreferences.clampGainDB(-24), -24, accuracy: 0.0001)
        XCTAssertEqual(AppPreferences.clampGainDB(24), 24, accuracy: 0.0001)
    }

    func testClampPassThroughInRange() {
        XCTAssertEqual(AppPreferences.clampGainDB(5), 5, accuracy: 0.0001)
        XCTAssertEqual(AppPreferences.clampGainDB(-12.5), -12.5, accuracy: 0.0001)
        XCTAssertEqual(AppPreferences.clampGainDB(0), 0, accuracy: 0.0001)
    }
}

// MARK: - User volume <-> percent piecewise-linear curve

final class UserVolumeCurveTests: XCTestCase {

    func testMonotonicNonDecreasing() {
        var last = Int32.min
        for p in stride(from: 0.0, through: 100.0, by: 1.0) {
            let v = TeamTalkConnectionController.userVolumeFromPercent(p)
            XCTAssertGreaterThanOrEqual(v, last, "volume curve not monotonic at \(p)%")
            last = v
        }
    }

    func testAnchorsAreOrdered() {
        let v0 = TeamTalkConnectionController.userVolumeFromPercent(0)
        let v50 = TeamTalkConnectionController.userVolumeFromPercent(50)
        let v100 = TeamTalkConnectionController.userVolumeFromPercent(100)
        XCTAssertLessThan(v0, v50, "0% should map below 50% (default)")
        XCTAssertLessThan(v50, v100, "50% (default) should map below 100% (max)")
    }

    func testPercentRoundTripAtAnchors() {
        let v0 = TeamTalkConnectionController.userVolumeFromPercent(0)
        let v50 = TeamTalkConnectionController.userVolumeFromPercent(50)
        let v100 = TeamTalkConnectionController.userVolumeFromPercent(100)
        XCTAssertEqual(TeamTalkConnectionController.percentFromUserVolume(v0), 0)
        XCTAssertEqual(TeamTalkConnectionController.percentFromUserVolume(v50), 50)
        XCTAssertEqual(TeamTalkConnectionController.percentFromUserVolume(v100), 100)
    }

    func testPercentClampsOutOfRange() {
        XCTAssertEqual(
            TeamTalkConnectionController.userVolumeFromPercent(-10),
            TeamTalkConnectionController.userVolumeFromPercent(0)
        )
        XCTAssertEqual(
            TeamTalkConnectionController.userVolumeFromPercent(150),
            TeamTalkConnectionController.userVolumeFromPercent(100)
        )
    }

    func testRoundTripApprox() {
        for p in stride(from: 0.0, through: 100.0, by: 5.0) {
            let v = TeamTalkConnectionController.userVolumeFromPercent(p)
            let back = TeamTalkConnectionController.percentFromUserVolume(v)
            XCTAssertEqual(Double(back), p, accuracy: 1.5, "volume round-trip failed at \(p)%")
        }
    }
}

// MARK: - Preference Codable migrations

@MainActor
final class PreferencesCodableTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // VoiceOverAnnouncementPreferences: legacy `sessionHistoryEnabled` Bool -> disabledSessionHistoryKinds

    func testVoiceOverLegacyEnabledFalseDisablesAllAnnounceable() throws {
        let prefs = try decode(VoiceOverAnnouncementPreferences.self, #"{"sessionHistoryEnabled": false}"#)
        XCTAssertEqual(prefs.disabledSessionHistoryKinds, Set(SessionHistoryEntry.Kind.announceable))
        XCTAssertFalse(prefs.sessionHistoryEnabled)
    }

    func testVoiceOverLegacyEnabledTrueLeavesAllEnabled() throws {
        let prefs = try decode(VoiceOverAnnouncementPreferences.self, #"{"sessionHistoryEnabled": true}"#)
        XCTAssertTrue(prefs.disabledSessionHistoryKinds.isEmpty)
        XCTAssertTrue(prefs.sessionHistoryEnabled)
    }

    func testVoiceOverModernKeyRespected() throws {
        let prefs = try decode(VoiceOverAnnouncementPreferences.self,
                               #"{"disabledSessionHistoryKinds": ["connected","disconnected"]}"#)
        XCTAssertEqual(prefs.disabledSessionHistoryKinds, [.connected, .disconnected])
    }

    func testVoiceOverEmptyJSONUsesDefaults() throws {
        let prefs = try decode(VoiceOverAnnouncementPreferences.self, "{}")
        XCTAssertTrue(prefs.disabledSessionHistoryKinds.isEmpty)
        XCTAssertTrue(prefs.channelMessagesEnabled)
        XCTAssertTrue(prefs.privateMessagesEnabled)
        XCTAssertTrue(prefs.broadcastMessagesEnabled)
    }

    // AdvancedInputAudioPreferences: removed keys (gate/expander/limiter/isEnabled) must decode without crashing

    func testAdvancedInputAudioIgnoresRemovedLegacyKeys() throws {
        // Old saved prefs carried gate/expander/limiter/isEnabled keys (since removed).
        // Decoding must ignore them without throwing, keep modern keys, and fall back
        // to the default preset (.auto) when no preset is present.
        let json = #"{"isEnabled": true, "gate": {"threshold": -40}, "limiter": {"enabled": true}, "echoCancellationEnabled": true}"#
        let prefs = try decode(AdvancedInputAudioPreferences.self, json)
        XCTAssertTrue(prefs.echoCancellationEnabled)
        XCTAssertEqual(prefs.preset, .auto)
    }

    func testAdvancedInputAudioEmptyJSONUsesDefaults() throws {
        let prefs = try decode(AdvancedInputAudioPreferences.self, "{}")
        XCTAssertEqual(prefs.preset, .auto)
        XCTAssertEqual(prefs.processingMode, .none)
        XCTAssertFalse(prefs.echoCancellationEnabled)
        XCTAssertFalse(prefs.noiseSuppressionEnabled)
    }

    // Migration: legacy boolean `echoCancellationEnabled` maps to the processing mode.

    func testAdvancedInputAudioLegacyAECTrueMigratesToEchoAndNoise() throws {
        let prefs = try decode(AdvancedInputAudioPreferences.self, #"{"echoCancellationEnabled": true}"#)
        XCTAssertEqual(prefs.processingMode, .echoAndNoise)
        XCTAssertTrue(prefs.echoCancellationEnabled)
        XCTAssertTrue(prefs.noiseSuppressionEnabled)
    }

    func testAdvancedInputAudioLegacyAECFalseMigratesToNone() throws {
        let prefs = try decode(AdvancedInputAudioPreferences.self, #"{"echoCancellationEnabled": false}"#)
        XCTAssertEqual(prefs.processingMode, .none)
        XCTAssertFalse(prefs.echoCancellationEnabled)
        XCTAssertFalse(prefs.noiseSuppressionEnabled)
    }

    func testAdvancedInputAudioNoiseSuppressionOnlyMode() throws {
        let prefs = try decode(AdvancedInputAudioPreferences.self, #"{"processingMode": "noiseSuppression"}"#)
        XCTAssertEqual(prefs.processingMode, .noiseSuppression)
        XCTAssertFalse(prefs.echoCancellationEnabled)
        XCTAssertTrue(prefs.noiseSuppressionEnabled)
    }

    func testAdvancedInputAudioModernKeyTakesPrecedenceOverLegacy() throws {
        // When both the new mode and the legacy boolean are present, the new key wins.
        let json = #"{"processingMode": "noiseSuppression", "echoCancellationEnabled": true}"#
        let prefs = try decode(AdvancedInputAudioPreferences.self, json)
        XCTAssertEqual(prefs.processingMode, .noiseSuppression)
    }

    func testAdvancedInputAudioProcessingModeRoundTrips() throws {
        for mode in MicrophoneProcessingMode.allCases {
            let original = AdvancedInputAudioPreferences(preset: .auto, processingMode: mode)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AdvancedInputAudioPreferences.self, from: data)
            XCTAssertEqual(decoded.processingMode, mode)
        }
    }
}

// MARK: - UserVolumeStore server scoping (issue #24)

final class UserVolumeStoreScopingTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "UserVolumeStoreScopingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // A non-default value so it actually persists (default is pruned to "no entry").
    private let louder = Int32(SOUND_VOLUME_DEFAULT.rawValue) + 1000

    func testVolumeIsIsolatedBetweenServers() {
        let store = UserVolumeStore(defaults: defaults)

        store.setServerScope("serverA:10333")
        store.setVolume(louder, forUsername: "guest")
        XCTAssertEqual(store.volume(forUsername: "guest"), louder)

        // Same generic username on a different server must NOT inherit the value.
        store.setServerScope("serverB:10333")
        XCTAssertNil(store.volume(forUsername: "guest"))

        // Back to the first server: the value is still there.
        store.setServerScope("serverA:10333")
        XCTAssertEqual(store.volume(forUsername: "guest"), louder)
    }

    func testPanAndStereoAreAlsoScoped() {
        let store = UserVolumeStore(defaults: defaults)

        store.setServerScope("serverA:10333")
        store.setVoicePan(0.5, forUsername: "guest")
        store.setMediaPan(-0.25, forUsername: "guest")
        store.setStereoBalance(.init(left: true, right: false), forUsername: "guest")

        store.setServerScope("serverB:10333")
        XCTAssertNil(store.voicePan(forUsername: "guest"))
        XCTAssertNil(store.mediaPan(forUsername: "guest"))
        XCTAssertNil(store.stereoBalance(forUsername: "guest"))

        store.setServerScope("serverA:10333")
        XCTAssertEqual(store.voicePan(forUsername: "guest"), 0.5)
        XCTAssertEqual(store.mediaPan(forUsername: "guest"), -0.25)
        XCTAssertEqual(store.stereoBalance(forUsername: "guest"), .init(left: true, right: false))
    }

    func testLegacyUnscopedEntriesDoNotMatchScopedLookup() {
        // Simulate a pre-fix entry written with no scope (bare-username key)...
        let legacy = UserVolumeStore(defaults: defaults)
        legacy.setVolume(louder, forUsername: "guest")   // scope is "" → key is "guest"
        XCTAssertEqual(legacy.volume(forUsername: "guest"), louder)

        // ...once connected (scope set), the polluted value no longer applies → 50% default.
        let scoped = UserVolumeStore(defaults: defaults)
        scoped.setServerScope("serverA:10333")
        XCTAssertNil(scoped.volume(forUsername: "guest"))
    }

    func testDefaultVolumePrunesEntry() {
        let store = UserVolumeStore(defaults: defaults)
        store.setServerScope("serverA:10333")
        store.setVolume(louder, forUsername: "guest")
        store.setVolume(Int32(SOUND_VOLUME_DEFAULT.rawValue), forUsername: "guest")
        XCTAssertNil(store.volume(forUsername: "guest"))
    }

    func testEmptyUsernameIsNeverStored() {
        let store = UserVolumeStore(defaults: defaults)
        store.setServerScope("serverA:10333")
        store.setVolume(louder, forUsername: "")
        XCTAssertNil(store.volume(forUsername: ""))
    }

    // MARK: Memory mode (off / session / persistent)

    func testOffModeNeverRemembers() {
        let store = UserVolumeStore(defaults: defaults)
        store.setServerScope("serverA:10333")
        store.setMemoryMode(.off)
        store.setVolume(louder, forUsername: "guest")
        XCTAssertNil(store.volume(forUsername: "guest"))
        // Nothing was written to the persistent backing either.
        let other = UserVolumeStore(defaults: defaults)
        other.setServerScope("serverA:10333")
        XCTAssertNil(other.volume(forUsername: "guest"))
    }

    func testSessionModeRemembersInMemoryButNotPersisted() {
        let store = UserVolumeStore(defaults: defaults)
        store.setServerScope("serverA:10333")
        store.setMemoryMode(.session)
        store.setVolume(louder, forUsername: "guest")
        // Same store instance (same app run) remembers it.
        XCTAssertEqual(store.volume(forUsername: "guest"), louder)
        // A fresh instance (simulating a relaunch) does NOT — nothing hit UserDefaults.
        let relaunched = UserVolumeStore(defaults: defaults)
        relaunched.setServerScope("serverA:10333")
        relaunched.setMemoryMode(.session)
        XCTAssertNil(relaunched.volume(forUsername: "guest"))
    }

    func testPersistentModeSurvivesNewInstance() {
        let store = UserVolumeStore(defaults: defaults)
        store.setServerScope("serverA:10333")
        store.setMemoryMode(.persistent)
        store.setVolume(louder, forUsername: "guest")

        let relaunched = UserVolumeStore(defaults: defaults)
        relaunched.setServerScope("serverA:10333")
        relaunched.setMemoryMode(.persistent)
        XCTAssertEqual(relaunched.volume(forUsername: "guest"), louder)
    }

    func testSwitchingToOffStopsReadingPersistedValue() {
        let store = UserVolumeStore(defaults: defaults)
        store.setServerScope("serverA:10333")
        store.setMemoryMode(.persistent)
        store.setVolume(louder, forUsername: "guest")
        XCTAssertEqual(store.volume(forUsername: "guest"), louder)

        store.setMemoryMode(.off)
        XCTAssertNil(store.volume(forUsername: "guest"))

        // Switching back exposes the still-persisted value (off doesn't erase).
        store.setMemoryMode(.persistent)
        XCTAssertEqual(store.volume(forUsername: "guest"), louder)
    }
}

// MARK: - AppPreferences userVolumeMemoryMode migration

final class UserVolumeMemoryModePreferenceTests: XCTestCase {

    private func decode(_ json: String) throws -> AppPreferences {
        try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
    }

    func testDefaultsToPersistentWhenKeyAbsent() throws {
        // A preferences blob saved before this feature existed.
        let prefs = try decode("{}")
        XCTAssertEqual(prefs.userVolumeMemoryMode, .persistent)
    }

    func testDecodesExplicitMode() throws {
        for mode in AppPreferences.UserVolumeMemoryMode.allCases {
            let prefs = try decode("{\"userVolumeMemoryMode\": \"\(mode.rawValue)\"}")
            XCTAssertEqual(prefs.userVolumeMemoryMode, mode)
        }
    }

    func testRoundTrips() throws {
        for mode in AppPreferences.UserVolumeMemoryMode.allCases {
            var prefs = AppPreferences()
            prefs.userVolumeMemoryMode = mode
            let data = try JSONEncoder().encode(prefs)
            let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
            XCTAssertEqual(decoded.userVolumeMemoryMode, mode)
        }
    }
}
