//
//  AudioRouteChangeTests.swift
//  ttaccessibleTests
//
//  After coreaudiod restarted, every device came back with the same UID but a new
//  object ID (measured: the input went from 93 to 728), the snapshot compared only
//  UIDs, and the output stayed silent. The same held for unplugging and replugging
//  the chosen output. These pin what each change calls for: a restart when the input
//  moved, an output switch that leaves the microphone running when only the output
//  did, and nothing at all when nothing did.
//

import AudioToolbox
import XCTest
@testable import ttaccessible

final class AudioRouteChangeTests: XCTestCase {

    private let audient = "AppleUSBAudioEngine:Audient:Audient iD44:100000:1,2"
    private let speakers = "BuiltInSpeakerDevice"
    private let blackHole = "BlackHole_UID"

    private var chooseAudient: AudioDevicePreference {
        AudioDevicePreference(persistentID: audient, displayName: "Audient iD44")
    }

    private func snapshot(
        input: String? = "BlackHole_UID", inputID: UInt32? = 93,
        defaultInput: String? = "BlackHole_UID", defaultOutput: String? = "BuiltInSpeakerDevice",
        output: String?, outputID: UInt32?, chosenOutputPresent: Bool = true
    ) -> AudioRoutingSnapshot {
        AudioRoutingSnapshot(
            resolvedInputUID: input,
            defaultInputUID: defaultInput,
            defaultOutputUID: defaultOutput,
            preferredOutputPersistentID: audient,
            chosenOutputPresent: chosenOutputPresent,
            activeInputSampleRate: 48_000,
            inputDeviceObjectID: inputID,
            outputEngineDeviceUID: output,
            outputEngineDeviceObjectID: outputID
        )
    }

    private func reaction(
        _ a: AudioRoutingSnapshot, _ b: AudioRoutingSnapshot,
        input: AudioDevicePreference = .systemDefault, output: AudioDevicePreference? = nil,
        outputOpen: Bool = true, inputOpen: Bool = true, awaiting: Bool = false
    ) -> TeamTalkConnectionController.AudioRouteReaction {
        TeamTalkConnectionController.audioRouteReaction(
            previous: a, current: b,
            inputPreference: input, outputPreference: output ?? chooseAudient,
            selector: kAudioHardwarePropertyDevices,
            outputOpen: outputOpen, inputOpen: inputOpen, microphoneAwaitingInput: awaiting
        )
    }

    func testNothingChangedIsNotARouteChange() {
        let s = snapshot(output: audient, outputID: 120)
        XCTAssertEqual(reaction(s, s), .none)
    }

    func testCoreAudioRestartRestartsEverything() {
        // Every object ID changes: the microphone's too, so the full restart.
        XCTAssertEqual(reaction(
            snapshot(inputID: 93, output: audient, outputID: 120),
            snapshot(inputID: 728, output: audient, outputID: 731)
        ), .restartSoundSystem)
    }

    func testANewOutputObjectIDOnlySwitchesTheOutput() {
        XCTAssertEqual(reaction(
            snapshot(output: audient, outputID: 120),
            snapshot(output: audient, outputID: 731)
        ), .switchOutput)
    }

    func testANewMicrophoneObjectIDRestarts() {
        XCTAssertEqual(reaction(
            snapshot(inputID: 93, output: audient, outputID: 120),
            snapshot(inputID: 728, output: audient, outputID: 120)
        ), .restartSoundSystem)
    }

    func testUnpluggingTheChosenOutputSwitchesToTheFallbackAndKeepsTheMicrophone() {
        XCTAssertEqual(reaction(
            snapshot(output: audient, outputID: 120),
            snapshot(output: speakers, outputID: 45, chosenOutputPresent: false)
        ), .switchOutput)
    }

    func testPluggingItBackSwitchesBack() {
        XCTAssertEqual(reaction(
            snapshot(output: speakers, outputID: 45, chosenOutputPresent: false),
            snapshot(output: audient, outputID: 740)
        ), .switchOutput)
    }

    func testTheChosenOutputReturningOpensAClosedOutput() {
        XCTAssertEqual(reaction(
            snapshot(output: speakers, outputID: 45, chosenOutputPresent: false),
            snapshot(output: audient, outputID: 740),
            outputOpen: false
        ), .restartSoundSystem)
    }

    func testAClosedOutputIsNotReopenedForANewObjectID() {
        XCTAssertEqual(reaction(
            snapshot(output: audient, outputID: 120),
            snapshot(output: audient, outputID: 731),
            outputOpen: false, inputOpen: false
        ), .none)
    }

    func testAnIdleMicrophoneDeviceIsNotAReason() {
        XCTAssertEqual(reaction(
            snapshot(inputID: 93, output: audient, outputID: 120),
            snapshot(inputID: 728, output: audient, outputID: 120),
            inputOpen: false
        ), .none)
    }

    func testANewSystemDefaultOutputOnlySwitchesTheOutput() {
        XCTAssertEqual(reaction(
            snapshot(defaultOutput: speakers, output: speakers, outputID: 45),
            snapshot(defaultOutput: audient, output: audient, outputID: 120),
            output: .systemDefault
        ), .switchOutput)
    }

    func testANewSystemDefaultInputRestarts() {
        XCTAssertEqual(reaction(
            snapshot(input: blackHole, defaultInput: blackHole, output: audient, outputID: 120),
            snapshot(input: "BuiltInMic", inputID: 60, defaultInput: "BuiltInMic", output: audient, outputID: 120)
        ), .restartSoundSystem)
    }

    func testNoOutputChosenIgnoresOutputDevices() {
        // "No output": the output devices come and go, and no output is ever opened for them.
        XCTAssertEqual(reaction(
            snapshot(defaultOutput: speakers, output: nil, outputID: nil),
            snapshot(defaultOutput: audient, output: nil, outputID: nil),
            output: .noOutput, outputOpen: false
        ), .none)
    }

    // The chosen microphone unplugged and plugged back in.

    private var chooseBlackHole: AudioDevicePreference {
        AudioDevicePreference(persistentID: blackHole, displayName: "BlackHole 2ch")
    }

    func testTheChosenMicrophoneGoingAwayRestarts() {
        XCTAssertEqual(reaction(
            snapshot(input: blackHole, output: audient, outputID: 120),
            snapshot(input: nil, inputID: nil, output: audient, outputID: 120),
            input: chooseBlackHole
        ), .restartSoundSystem)
    }

    func testTheChosenMicrophoneComingBackRestoresTheOneWaitingForIt() {
        XCTAssertEqual(reaction(
            snapshot(input: nil, inputID: nil, output: audient, outputID: 120),
            snapshot(input: blackHole, inputID: 812, output: audient, outputID: 120),
            input: chooseBlackHole, inputOpen: false, awaiting: true
        ), .restartSoundSystem)
    }

    func testTheChosenMicrophoneComingBackOpensNothingWhenNothingWaits() {
        XCTAssertEqual(reaction(
            snapshot(input: nil, inputID: nil, output: audient, outputID: 120),
            snapshot(input: blackHole, inputID: 812, output: audient, outputID: 120),
            input: chooseBlackHole, inputOpen: false, awaiting: false
        ), .none)
    }
}
