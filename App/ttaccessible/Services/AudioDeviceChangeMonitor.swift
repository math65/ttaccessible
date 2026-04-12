//
//  AudioDeviceChangeMonitor.swift
//  ttaccessible
//

import AudioToolbox
import CoreAudio
import Foundation

/// Monitors CoreAudio for hardware device additions, removals, default device changes,
/// and sample rate changes on the current default input device.
/// Posts `Notification.Name.audioDevicesDidChange` on the main thread when a change is detected.
final class AudioDeviceChangeMonitor {
    static let audioDevicesDidChange = Notification.Name("TTAccessibleAudioDevicesDidChange")

    private var isListening = false
    private var monitoredInputDeviceID: AudioDeviceID = kAudioObjectUnknown

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

        updateSampleRateMonitoring()
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        removeSampleRateListener(selfPointer)

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

    fileprivate func handleDeviceChange(selector: UInt32) {
        if selector == kAudioHardwarePropertyDefaultInputDevice {
            updateSampleRateMonitoring()
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.audioDevicesDidChange, object: nil)
        }
    }

    // MARK: - Sample Rate Monitoring

    /// Monitor sample rate changes on a specific device (e.g. the active input device).
    /// Pass nil to monitor the system default input device.
    func monitorSampleRate(forDeviceID deviceID: AudioDeviceID?) {
        guard isListening else { return }
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        removeSampleRateListener(selfPointer)

        if let deviceID, deviceID != kAudioObjectUnknown {
            monitoredInputDeviceID = deviceID
            addSampleRateListener(deviceID, selfPointer)
        } else {
            updateSampleRateMonitoringToDefault()
        }
    }

    private func updateSampleRateMonitoring() {
        updateSampleRateMonitoringToDefault()
    }

    private func updateSampleRateMonitoringToDefault() {
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        removeSampleRateListener(selfPointer)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else {
            return
        }

        monitoredInputDeviceID = deviceID
        addSampleRateListener(deviceID, selfPointer)
    }

    private func addSampleRateListener(_ deviceID: AudioDeviceID, _ selfPointer: UnsafeMutableRawPointer) {
        var sampleRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(
            deviceID,
            &sampleRateAddress,
            audioDeviceChangeCallback,
            selfPointer
        )
        AudioLogger.log("AudioDeviceChangeMonitor: monitoring sample rate on device %u", deviceID)
    }

    private func removeSampleRateListener(_ selfPointer: UnsafeMutableRawPointer) {
        guard monitoredInputDeviceID != kAudioObjectUnknown else { return }
        var sampleRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListener(
            monitoredInputDeviceID,
            &sampleRateAddress,
            audioDeviceChangeCallback,
            selfPointer
        )
        monitoredInputDeviceID = kAudioObjectUnknown
    }
}

private func audioDeviceChangeCallback(
    _ objectID: AudioObjectID,
    _ numberAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    var firstSelector: UInt32 = 0
    for i in 0..<Int(numberAddresses) {
        let selector = addresses[i].mSelector
        if firstSelector == 0 { firstSelector = selector }
        let name: String
        switch selector {
        case kAudioHardwarePropertyDevices: name = "kAudioHardwarePropertyDevices"
        case kAudioHardwarePropertyDefaultInputDevice: name = "kAudioHardwarePropertyDefaultInputDevice"
        case kAudioHardwarePropertyDefaultOutputDevice: name = "kAudioHardwarePropertyDefaultOutputDevice"
        case kAudioDevicePropertyNominalSampleRate: name = "kAudioDevicePropertyNominalSampleRate"
        default: name = String(format: "0x%08X", selector)
        }
        AudioLogger.log("AudioDeviceChangeMonitor: property changed — %@", name)
    }
    let monitor = Unmanaged<AudioDeviceChangeMonitor>.fromOpaque(clientData).takeUnretainedValue()
    monitor.handleDeviceChange(selector: firstSelector)
    return noErr
}
