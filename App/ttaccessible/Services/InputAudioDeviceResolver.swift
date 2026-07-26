//
//  InputAudioDeviceResolver.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import AudioToolbox
import CoreAudio
import Foundation

enum InputAudioDeviceResolver {
    nonisolated static func currentInputDeviceID(
        for preference: AudioDevicePreference
    ) -> String? {
        resolveCurrentInputDevice(for: preference)?.uid
    }

    nonisolated static func resolveCurrentInputDevice(for preference: AudioDevicePreference) -> InputAudioDeviceInfo? {
        let devices = availableInputDevices()
        guard devices.isEmpty == false else {
            return nil
        }

        if preference.usesSystemDefault {
            return defaultInputDevice(from: devices) ?? devices.first
        }

        if let persistentID = preference.persistentID,
           let exactUIDMatch = devices.first(where: { $0.uid == persistentID }) {
            return exactUIDMatch
        }

        if let displayName = preference.displayName,
           let nameMatch = devices.first(where: { $0.name == displayName }) {
            return nameMatch
        }

        // The user explicitly chose a specific input device and it isn't present.
        // Return nil rather than silently substituting the default / first device —
        // grabbing the "wrong mic" without telling anyone is worse than reporting the
        // device as unavailable. This mirrors resolveOutputDevice's no-match semantics;
        // callers that need a device surface a "device unavailable" error instead.
        return nil
    }

    nonisolated static func availablePresetOptions(for device: InputAudioDeviceInfo?) -> [InputChannelPresetOption] {
        guard let device, device.inputChannels > 0 else {
            return [InputChannelPresetOption(preset: .auto, title: title(for: .auto))]
        }

        var options = [InputChannelPresetOption(preset: .auto, title: title(for: .auto))]

        for channel in 1...device.inputChannels {
            let preset = InputChannelPreset.mono(channel: channel)
            options.append(InputChannelPresetOption(preset: preset, title: title(for: preset)))
        }

        var firstChannel = 1
        while firstChannel + 1 <= device.inputChannels {
            let secondChannel = firstChannel + 1
            let stereoPreset = InputChannelPreset.stereoPair(first: firstChannel, second: secondChannel)
            let monoMixPreset = InputChannelPreset.monoMix(first: firstChannel, second: secondChannel)
            options.append(InputChannelPresetOption(preset: stereoPreset, title: title(for: stereoPreset)))
            options.append(InputChannelPresetOption(preset: monoMixPreset, title: title(for: monoMixPreset)))
            firstChannel += 2
        }

        return options
    }

    nonisolated static func normalizedPreferences(
        _ preferences: AdvancedInputAudioPreferences,
        for device: InputAudioDeviceInfo?
    ) -> (preferences: AdvancedInputAudioPreferences, didFallbackToAuto: Bool) {
        guard contains(preferences.preset, for: device) else {
            var normalized = preferences
            normalized.preset = .auto
            return (normalized, true)
        }
        return (preferences, false)
    }

    nonisolated static func title(for preset: InputChannelPreset) -> String {
        switch preset {
        case .auto:
            return L10n.text("preferences.audio.advanced.preset.auto")
        case .mono(let channel):
            return L10n.format("preferences.audio.advanced.preset.mono", channel)
        case .stereoPair(let first, let second):
            return L10n.format("preferences.audio.advanced.preset.stereoPair", first, second)
        case .monoMix(let first, let second):
            return L10n.format("preferences.audio.advanced.preset.monoMix", first, second)
        }
    }

    nonisolated static func summary(for preferences: AdvancedInputAudioPreferences) -> String {
        let presetTitle = title(for: preferences.preset)
        let processingStatus: String
        switch preferences.processingMode {
        case .none:
            processingStatus = L10n.text("preferences.audio.advanced.summary.processingNone")
        case .noiseSuppression:
            processingStatus = L10n.text("preferences.audio.advanced.summary.processingNoiseSuppression")
        case .echoAndNoise:
            processingStatus = L10n.text("preferences.audio.advanced.summary.processingEchoAndNoise")
        }
        return L10n.format("preferences.audio.advanced.summary.active", presetTitle, processingStatus)
    }

    nonisolated static func availableInputDevices() -> [InputAudioDeviceInfo] {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(), count: count)
        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        let result = deviceIDs.compactMap(makeDeviceInfo(for:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let names = result.map { "\($0.name) (\($0.inputChannels)ch, \(Int($0.nominalSampleRate))Hz)" }.joined(separator: ", ")
        AudioLogger.log("InputAudioDeviceResolver: %d input devices — %@", result.count, names)
        return result
    }

    nonisolated static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: CFString = uid as CFString
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &dataSize,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    struct OutputAudioDeviceInfo: Equatable {
        let deviceID: AudioDeviceID
        let uid: String
        let name: String
        let nominalSampleRate: Double
    }

    /// Resolve the user's selected output device to a CoreAudio device so preview
    /// monitoring can bind to it. The stored preference's persistentID is the
    /// TeamTalk szDeviceID, which on macOS does NOT translate via
    /// kAudioHardwarePropertyTranslateUIDToDevice, so we match the CoreAudio
    /// output device by UID first and fall back to the (shared) device name.
    nonisolated static func resolveOutputDevice(persistentID: String?, displayName: String?) -> OutputAudioDeviceInfo? {
        let devices = availableOutputDevices()
        if let persistentID, persistentID.isEmpty == false,
           let match = devices.first(where: { $0.uid == persistentID }) {
            return match
        }
        if let displayName, displayName.isEmpty == false,
           let match = devices.first(where: { $0.name.localizedCaseInsensitiveCompare(displayName) == .orderedSame }) {
            return match
        }
        return nil
    }

    nonisolated static func availableOutputDevices() -> [OutputAudioDeviceInfo] {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = Array(repeating: AudioObjectID(), count: count)
        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs.compactMap(makeOutputDeviceInfo(for:))
    }

    private nonisolated static func makeOutputDeviceInfo(for objectID: AudioObjectID) -> OutputAudioDeviceInfo? {
        guard outputChannelCount(for: objectID) > 0,
              let name = stringProperty(objectID: objectID, selector: kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal),
              let uid = stringProperty(objectID: objectID, selector: kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal) else {
            return nil
        }
        let sampleRate = doubleProperty(
            objectID: objectID,
            selector: kAudioDevicePropertyNominalSampleRate,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 48_000
        return OutputAudioDeviceInfo(deviceID: objectID, uid: uid, name: name, nominalSampleRate: sampleRate)
    }

    private nonisolated static func outputChannelCount(for objectID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }
        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else {
            return 0
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    nonisolated static func contains(_ preset: InputChannelPreset, for device: InputAudioDeviceInfo?) -> Bool {
        guard let device, device.inputChannels > 0 else {
            switch preset {
            case .auto:
                return true
            default:
                return false
            }
        }

        switch preset {
        case .auto:
            return true
        case .mono(let channel):
            return (1...device.inputChannels).contains(channel)
        case .stereoPair(let first, let second), .monoMix(let first, let second):
            return first >= 1 && second == first + 1 && second <= device.inputChannels
        }
    }

    nonisolated static func defaultInputDeviceUID() -> String? {
        coreAudioDefaultDeviceUID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    nonisolated static func defaultOutputDeviceUID() -> String? {
        coreAudioDefaultDeviceUID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private nonisolated static func coreAudioDefaultDeviceUID(selector: AudioObjectPropertySelector) -> String? {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceID) == noErr else {
            return nil
        }
        return stringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private nonisolated static func defaultInputDevice(from devices: [InputAudioDeviceInfo]) -> InputAudioDeviceInfo? {
        guard let uid = defaultInputDeviceUID() else {
            return nil
        }
        return devices.first(where: { $0.uid == uid })
    }

    private nonisolated static func makeDeviceInfo(for objectID: AudioObjectID) -> InputAudioDeviceInfo? {
        let channelCount = inputChannelCount(for: objectID)
        guard channelCount > 0,
              let name = stringProperty(objectID: objectID, selector: kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal),
              let uid = stringProperty(objectID: objectID, selector: kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal) else {
            return nil
        }

        let sampleRate = doubleProperty(
            objectID: objectID,
            selector: kAudioDevicePropertyNominalSampleRate,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 48_000

        return InputAudioDeviceInfo(
            uid: uid,
            name: name,
            inputChannels: channelCount,
            nominalSampleRate: sampleRate
        )
    }

    private nonisolated static func inputChannelCount(for objectID: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    private nonisolated static func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfString) { stringPointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, stringPointer)
        }
        guard status == noErr,
              let cfString else {
            return nil
        }
        return cfString as String
    }

    private nonisolated static func doubleProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64.zero
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }
        return Double(value)
    }
}
