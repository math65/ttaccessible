//
//  MacOSTextToSpeechAnnouncementService.swift
//  ttaccessible
//

import AVFoundation
import Foundation

struct MacOSTextToSpeechVoiceOption: Identifiable, Equatable {
    let id: String?
    let name: String
    let languageName: String?
    let isEloquence: Bool

    var displayName: String {
        if let languageName, languageName.isEmpty == false {
            return "\(name) (\(languageName))"
        }
        return name
    }

    static let systemDefault = MacOSTextToSpeechVoiceOption(
        id: nil,
        name: L10n.text("preferences.notifications.tts.voice.systemDefault"),
        languageName: nil,
        isEloquence: false
    )
}

@MainActor
final class MacOSTextToSpeechAnnouncementService {
    private static let eloquenceVoiceNames: Set<String> = [
        "Eddy",
        "Flo",
        "Grandma",
        "Grandpa",
        "Jacques",
        "Reed",
        "Rocko",
        "Sandy",
        "Shelley"
    ]

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = AudioDiagnosticsLogger.shared

    static var minimumSpeechRate: Double { Double(AVSpeechUtteranceMinimumSpeechRate) }
    static var maximumSpeechRate: Double { Double(AVSpeechUtteranceMaximumSpeechRate) }
    static var defaultSpeechRate: Double { Double(AVSpeechUtteranceDefaultSpeechRate) }

    static func availableVoices() -> [MacOSTextToSpeechVoiceOption] {
        let locale = Locale.current
        let voices: [MacOSTextToSpeechVoiceOption] = AVSpeechSynthesisVoice.speechVoices()
            .map { voice in
                let languageName = locale.localizedString(forIdentifier: voice.language) ?? voice.language
                return (
                    languageName: languageName,
                    option: MacOSTextToSpeechVoiceOption(
                        id: voice.identifier,
                        name: voice.name,
                        languageName: languageName,
                        isEloquence: Self.eloquenceVoiceNames.contains(voice.name)
                            || voice.name.localizedCaseInsensitiveContains("eloquence")
                    )
                )
            }
            .sorted { lhs, rhs in
                let languageOrder = lhs.languageName.localizedCaseInsensitiveCompare(rhs.languageName)
                if languageOrder != .orderedSame {
                    return languageOrder == .orderedAscending
                }
                if lhs.option.isEloquence != rhs.option.isEloquence {
                    return lhs.option.isEloquence == false
                }
                return lhs.option.name.localizedCaseInsensitiveCompare(rhs.option.name) == .orderedAscending
            }
            .map(\.option)
        return [MacOSTextToSpeechVoiceOption.systemDefault] + voices
    }

    func announce(
        _ message: String,
        voiceIdentifier: String?,
        speechRate: Double,
        volume: Double
    ) {
        guard message.isEmpty == false else {
            return
        }

        logger.log("macos-tts", "announce requested text=\(message)")
        if synthesizer.isSpeaking {
            logger.log("macos-tts", "stopping previous utterance before speaking new message")
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: message)
        if let voiceIdentifier, voiceIdentifier.isEmpty == false {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
            logger.log("macos-tts", "using configured voice identifier=\(voiceIdentifier)")
        } else {
            logger.log("macos-tts", "using system default voice")
        }
        utterance.rate = Float(min(max(speechRate, Self.minimumSpeechRate), Self.maximumSpeechRate))
        utterance.volume = Float(min(max(volume, 0), 1))

        logger.log(
            "macos-tts",
            "speaking with rate=\(utterance.rate) volume=\(utterance.volume)"
        )
        synthesizer.speak(utterance)
    }
}
