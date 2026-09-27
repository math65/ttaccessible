//
//  DevicePickerPreferenceTests.swift
//  ttaccessibleTests
//
//  With the Audio pane open, unplugging the chosen output left its picker with no
//  row for it, so the picker showed System Default and saved that as the choice.
//  Plugged back in, the Audient stayed unused: the app no longer wanted it. A missing
//  device now keeps a "(not connected)" row of its own, so it stays the choice and
//  System Default can still be picked on purpose.
//

import XCTest
@testable import ttaccessible

@MainActor
final class DevicePickerPreferenceTests: XCTestCase {

    private let audient = AudioDeviceOption(id: "audient", persistentID: "audient", displayName: "Audient iD44")
    private let speakers = AudioDeviceOption(id: "speakers", persistentID: "speakers", displayName: "Mac Studio Speakers")
    private let savedAudient = AudioDevicePreference(persistentID: "audient", displayName: "Audient iD44")
    private let defaultTag = "__system_default__"

    private func resolve(_ pickerID: String, saved: AudioDevicePreference, devices: [AudioDeviceOption]) -> AudioDevicePreference {
        AudioPreferencesStore.preference(forPickerID: pickerID, saved: saved, devices: devices)
    }

    /// The case that lost the choice: device gone. It keeps a row of its own, named as not
    /// connected, and the picker stays on it.
    func testAMissingDeviceKeepsItsSavedChoice() {
        XCTAssertEqual(AudioPreferencesStore.selectionID(for: savedAudient, devices: [speakers]), "audient")
        XCTAssertEqual(resolve("audient", saved: savedAudient, devices: [speakers]), savedAudient)
        let missing = AudioPreferencesStore.missingDevice(for: savedAudient, devices: [speakers])
        XCTAssertEqual(missing?.id, "audient")
        XCTAssertTrue(missing?.name.contains("Audient iD44") ?? false)
    }

    /// With the device unplugged, System Default is a different row, so it can be chosen.
    func testSystemDefaultCanBeChosenWhileTheSavedDeviceIsMissing() {
        XCTAssertEqual(resolve(defaultTag, saved: savedAudient, devices: [speakers]), .systemDefault)
    }

    func testAPluggedInDeviceHasNoExtraRow() {
        XCTAssertNil(AudioPreferencesStore.missingDevice(for: savedAudient, devices: [audient, speakers]))
        XCTAssertNil(AudioPreferencesStore.missingDevice(for: .systemDefault, devices: [speakers]))
        XCTAssertNil(AudioPreferencesStore.missingDevice(for: .noOutput, devices: [speakers]))
    }

    func testPickingSystemDefaultOnPurposeStillSavesIt() {
        XCTAssertEqual(resolve(defaultTag, saved: savedAudient, devices: [audient, speakers]), .systemDefault)
    }

    func testPickingAnotherDeviceSavesIt() {
        XCTAssertEqual(
            resolve("speakers", saved: savedAudient, devices: [audient, speakers]),
            AudioDevicePreference(persistentID: "speakers", displayName: "Mac Studio Speakers")
        )
    }

    func testAnUnchangedPickerKeepsItsChoice() {
        XCTAssertEqual(resolve("audient", saved: savedAudient, devices: [audient, speakers]), savedAudient)
    }
}
