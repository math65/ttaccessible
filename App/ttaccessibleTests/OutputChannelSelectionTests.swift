//
//  OutputChannelSelectionTests.swift
//  ttaccessibleTests
//
//  Pure logic behind multi-channel device routing:
//   - OutputChannelSelection -> render plane indices (incl. the fallbacks that
//     keep audio audible when a selection outgrows the bound device)
//   - the option lists offered for a given channel count
//   - Codable round-trip (these are persisted per device UID)
//

import XCTest
@testable import ttaccessible

final class OutputChannelPlaneMappingTests: XCTestCase {

    func testAutoUsesFirstStereoPair() {
        let indices = OutputChannelSelection.auto.planeIndices(deviceChannels: 32)
        XCTAssertEqual(indices.left, 0)
        XCTAssertEqual(indices.right, 1)
    }

    func testAutoOnMonoDeviceCollapsesToSinglePlane() {
        let indices = OutputChannelSelection.auto.planeIndices(deviceChannels: 1)
        XCTAssertEqual(indices.left, 0)
        XCTAssertNil(indices.right)
    }

    func testStereoPairMapsToZeroBasedPlanes() {
        // "Outputs 5/6" on a 32-channel desk = planes 4 and 5.
        let indices = OutputChannelSelection.stereoPair(first: 5, second: 6).planeIndices(deviceChannels: 32)
        XCTAssertEqual(indices.left, 4)
        XCTAssertEqual(indices.right, 5)
    }

    func testMonoSelectionHasNoRightPlane() {
        let indices = OutputChannelSelection.mono(channel: 11).planeIndices(deviceChannels: 32)
        XCTAssertEqual(indices.left, 10)
        XCTAssertNil(indices.right)
    }

    /// The interface was swapped for a smaller one (or unplugged and replaced by
    /// the built-in speakers): the routing must fall back to the first pair, not
    /// address a plane that doesn't exist.
    func testOutOfRangeSelectionFallsBackToFirstPair() {
        let stereo = OutputChannelSelection.stereoPair(first: 11, second: 12).planeIndices(deviceChannels: 2)
        XCTAssertEqual(stereo.left, 0)
        XCTAssertEqual(stereo.right, 1)

        let mono = OutputChannelSelection.mono(channel: 30).planeIndices(deviceChannels: 2)
        XCTAssertEqual(mono.left, 0)
        XCTAssertEqual(mono.right, 1)
    }

    func testNoChannelsIsSafe() {
        let indices = OutputChannelSelection.stereoPair(first: 5, second: 6).planeIndices(deviceChannels: 0)
        XCTAssertEqual(indices.left, 0)
        XCTAssertNil(indices.right)
    }
}

final class OutputChannelOptionListTests: XCTestCase {

    func testOptionsForEightChannelDevice() {
        let options = InputAudioDeviceResolver.availableOutputChannelOptions(channelCount: 8)
        // Auto + 8 mono + 4 odd/even pairs.
        XCTAssertEqual(options.count, 13)
        XCTAssertEqual(options.first?.selection, .auto)
        XCTAssertTrue(options.contains { $0.selection == .mono(channel: 8) })
        XCTAssertTrue(options.contains { $0.selection == .stereoPair(first: 5, second: 6) })
        // Odd-start pairs only — 2/3 is not how interfaces pair their outputs.
        XCTAssertFalse(options.contains { $0.selection == .stereoPair(first: 2, second: 3) })
    }

    func testOptionIdentifiersAreUnique() {
        let options = InputAudioDeviceResolver.availableOutputChannelOptions(channelCount: 32)
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
    }

    func testZeroChannelDeviceOffersAutoOnly() {
        let options = InputAudioDeviceResolver.availableOutputChannelOptions(channelCount: 0)
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.selection, .auto)
    }

    func testContainsRejectsSelectionsThatOutgrewTheDevice() {
        XCTAssertTrue(InputAudioDeviceResolver.contains(.stereoPair(first: 5, second: 6), channelCount: 8))
        XCTAssertFalse(InputAudioDeviceResolver.contains(.stereoPair(first: 5, second: 6), channelCount: 4))
        XCTAssertFalse(InputAudioDeviceResolver.contains(.mono(channel: 9), channelCount: 8))
        XCTAssertTrue(InputAudioDeviceResolver.contains(.auto, channelCount: 0))
    }
}

/// Regression test for the bug that made the picker never appear: the audio
/// store re-resolved the output device from inside the `rootStore.$preferences`
/// sink, but `@Published` fires on *willSet*, so `rootStore.preferences` there
/// still held the device the user had just switched AWAY from. Selecting a
/// 24-channel interface resolved the previous stereo device and hid the picker.
///
/// Uses an isolated UserDefaults suite — it must never touch real preferences.
@MainActor
final class OutputChannelPickerVisibilityTests: XCTestCase {

    func testPickerAppearsWhenSwitchingToMultiChannelDevice() throws {
        let outputs = InputAudioDeviceResolver.availableOutputDevices()
        guard let multiChannel = outputs.first(where: { $0.outputChannels > 2 }) else {
            throw XCTSkip("No output device with more than 2 channels on this machine")
        }

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ttaccessible.tests.outputChannels"))
        defaults.removePersistentDomain(forName: "ttaccessible.tests.outputChannels")
        let root = AppPreferencesStore(userDefaults: defaults)

        if let stereo = outputs.first(where: { $0.outputChannels <= 2 }) {
            root.updatePreferredOutputDevice(
                AudioDevicePreference(persistentID: stereo.uid, displayName: stereo.name)
            )
        }

        let controller = TeamTalkConnectionController(
            preferencesStore: root,
            passwordStore: ServerPasswordStore()
        )
        let advanced = AdvancedMicrophoneSettingsStore(
            preferencesStore: root,
            connectionController: controller
        )
        let audio = root.makeAudioStore(
            connectionController: controller,
            advancedSettingsStore: advanced
        )
        audio.prepareIfNeeded()

        // Switching devices goes through the root store, which is what feeds the
        // sink — the exact path that was reading a stale preference.
        root.updatePreferredOutputDevice(
            AudioDevicePreference(persistentID: multiChannel.uid, displayName: multiChannel.name)
        )

        XCTAssertTrue(audio.offersOutputChannelSelection,
                      "picker stayed hidden for a \(multiChannel.outputChannels)-channel device")
        XCTAssertFalse(audio.outputChannelOptions.isEmpty)
        XCTAssertEqual(audio.outputDeviceInfo?.uid, multiChannel.uid)

        defaults.removePersistentDomain(forName: "ttaccessible.tests.outputChannels")
    }
}

final class OutputChannelSelectionCodableTests: XCTestCase {

    func testRoundTripsThroughPreferences() throws {
        var preferences = AppPreferences()
        preferences.outputChannelSelections = [
            "uid-desk": .stereoPair(first: 5, second: 6),
            "uid-mono": .mono(channel: 11),
        ]
        preferences.deviceStreamChannelPresets = ["uid-desk": .monoMix(first: 3, second: 4)]

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded.outputChannelSelections["uid-desk"], .stereoPair(first: 5, second: 6))
        XCTAssertEqual(decoded.outputChannelSelections["uid-mono"], .mono(channel: 11))
        XCTAssertEqual(decoded.deviceStreamChannelPresets["uid-desk"], .monoMix(first: 3, second: 4))
    }

    /// Preferences written before this feature existed must still decode.
    func testLegacyPreferencesWithoutChannelRoutingDecode() throws {
        let json = Data(#"{"defaultNickname":"tester"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: json)
        XCTAssertTrue(decoded.outputChannelSelections.isEmpty)
        XCTAssertTrue(decoded.deviceStreamChannelPresets.isEmpty)
    }
}
