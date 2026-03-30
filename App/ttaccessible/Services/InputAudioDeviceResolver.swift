//
//  InputAudioDeviceResolver.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
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

        return defaultInputDevice(from: devices) ?? devices.first
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
        let sanitizedPreferences = preferences.normalized()

        guard contains(sanitizedPreferences.preset, for: device) else {
            var normalized = sanitizedPreferences
            normalized.preset = .auto
            return (normalized, true)
        }
        return (sanitizedPreferences, false)
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
        let aecSummary = preferences.echoCancellationEnabled
            ? L10n.text("preferences.audio.advanced.summary.aecEnabled")
            : L10n.text("preferences.audio.advanced.summary.aecDisabled")

        guard preferences.isEnabled else {
            return L10n.format("preferences.audio.advanced.summary.disabledWithAECState", aecSummary)
        }

        let presetTitle = title(for: preferences.preset)
        let dynamicSummary: String
        if preferences.dynamicProcessorEnabled {
            switch preferences.dynamicProcessorMode {
            case .gate:
                dynamicSummary = L10n.format(
                    "preferences.audio.advanced.summary.gateEnabled",
                    formatThresholdDB(preferences.gate.thresholdDB)
                )
            case .expander:
                dynamicSummary = L10n.format(
                    "preferences.audio.advanced.summary.expanderEnabled",
                    formatThresholdDB(preferences.expander.thresholdDB),
                    formatRatio(preferences.expander.ratio)
                )
            }
        } else {
            dynamicSummary = L10n.text("preferences.audio.advanced.summary.dynamicDisabled")
        }

        guard preferences.limiterEnabled else {
            return L10n.format("preferences.audio.advanced.summary.enabledWithoutLimiter", presetTitle, dynamicSummary) + ", " + aecSummary
        }

        let limiterSummary: String
        switch preferences.limiterMode {
        case .preset:
            limiterSummary = L10n.text(preferences.limiterPreset.localizationKey)
        case .manual:
            limiterSummary = L10n.format(
                "preferences.audio.advanced.summary.manualLimiter",
                formatThresholdDB(preferences.effectiveLimiterThresholdDB),
                Int(preferences.effectiveLimiterReleaseMilliseconds.rounded())
            )
        }

        return L10n.format(
            "preferences.audio.advanced.summary.enabledWithLimiter",
            presetTitle,
            dynamicSummary,
            limiterSummary
        ) + ", " + aecSummary
    }

    nonisolated static func formatThresholdDB(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f dB", value)
        }
        return String(format: "%.1f dB", value)
    }

    nonisolated static func formatRatio(_ value: Double) -> String {
        String(format: "%.1f:1", value)
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

        return deviceIDs.compactMap(makeDeviceInfo(for:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

    private nonisolated static func defaultInputDevice(from devices: [InputAudioDeviceInfo]) -> InputAudioDeviceInfo? {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID()
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceID) == noErr,
              let uid = stringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
              ) else {
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
