//
//  AudioDeviceChangeMonitor.swift
//  ttaccessible
//

import AudioToolbox
import CoreAudio
import Foundation

/// Monitors CoreAudio for hardware device additions, removals, and default device changes.
/// Posts `Notification.Name.audioDevicesDidChange` on the main thread when a change is detected.
final class AudioDeviceChangeMonitor {
    static let audioDevicesDidChange = Notification.Name("TTAccessibleAudioDevicesDidChange")

    private var isListening = false

    init() {}

    deinit {
        stopListening()
    }

    func startListening() {
        guard isListening == false else { return }
        isListening = true

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            audioDeviceChangeCallback,
            selfPointer
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            audioDeviceChangeCallback,
            selfPointer
        )

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            audioDeviceChangeCallback,
            selfPointer
        )
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            audioDeviceChangeCallback,
            selfPointer
        )

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            audioDeviceChangeCallback,
            selfPointer
        )

        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            audioDeviceChangeCallback,
            selfPointer
        )
    }

    fileprivate func handleDeviceChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.audioDevicesDidChange, object: nil)
        }
    }
}

private func audioDeviceChangeCallback(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let monitor = Unmanaged<AudioDeviceChangeMonitor>.fromOpaque(clientData).takeUnretainedValue()
    monitor.handleDeviceChange()
    return noErr
}
