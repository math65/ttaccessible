//
//  ProcessTapUpdateTests.swift
//  ttaccessibleTests
//
//  Live: creates a real, private process tap in the test host (macOS 14.2+). An app's capture
//  follows its processes by rewriting the running tap's description in place, and the
//  aggregate device holds that tap by its UID — so rewriting it must not change the UID.
//  Skips when the tap can't be created (older macOS, no audio-capture permission).
//

import CoreAudio
import XCTest
@testable import ttaccessible

final class ProcessTapUpdateTests: XCTestCase {

    @available(macOS 14.2, *)
    private func uid(of tap: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    @available(macOS 14.2, *)
    private func setDescription(_ description: CATapDescription, on tap: AudioObjectID) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var described = description
        return withUnsafeMutablePointer(to: &described) {
            AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
    }

    func testEditingTheTapsOwnDescriptionKeepsItsUID() throws {
        guard #available(macOS 14.2, *) else { throw XCTSkip("process taps need macOS 14.2") }
        let processes = ProcessTapCaptureBackend.ownAudioProcessObjectIDs()
        let created = CATapDescription(stereoMixdownOfProcesses: processes)
        created.name = "ttaccessible-test-tap"
        created.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(created, &tap) == noErr else {
            throw XCTSkip("no process tap here (permission or hardware)")
        }
        defer { AudioHardwareDestroyProcessTap(tap) }
        let before = try XCTUnwrap(uid(of: tap))

        // What ProcessTapCaptureBackend.updateTapProcessesLocked does: read, edit, write back.
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        var current: Unmanaged<CATapDescription>?
        XCTAssertEqual(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &current), noErr)
        let described = try XCTUnwrap(current?.takeRetainedValue())
        described.processes = processes
        XCTAssertEqual(setDescription(described, on: tap), noErr)
        XCTAssertEqual(uid(of: tap), before, "editing the tap's own description keeps its UID")

        // What 29d3661 did — a fresh description — for the record in the test log.
        let fresh = CATapDescription(stereoMixdownOfProcesses: processes)
        fresh.name = "ttaccessible-test-tap"
        fresh.isPrivate = true
        let freshStatus = setDescription(fresh, on: tap)
        print("ProcessTapUpdateTests: fresh description status=\(freshStatus) uid before=\(before) after=\(uid(of: tap) ?? "nil")")
    }
}
