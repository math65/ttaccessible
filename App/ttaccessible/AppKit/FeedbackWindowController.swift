//
//  FeedbackWindowController.swift
//  ttaccessible
//

import AppKit
import SwiftUI

/// "Contact the Developer" window: lets users without a GitHub account send
/// bug reports, suggestions and questions straight to the app backend.
/// Bug reports go to /api/feedback/report with a diagnostic snapshot and an
/// optional audio.log attachment; other types go to /api/feedback/contact.
@MainActor
final class FeedbackWindowController: NSWindowController {
    init(preferencesStore: AppPreferencesStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("feedback.window.title")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let view = FeedbackView(preferencesStore: preferencesStore) { [weak self] in
            self?.window?.close()
        }
        window.contentViewController = NSHostingController(rootView: view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct FeedbackView: View {
    let preferencesStore: AppPreferencesStore
    let onClose: () -> Void

    // Remembered across sessions, pre-filled on next open; only saved after a
    // successful send (so we never remember an address the server rejected).
    private static let savedEmailKey = "appBackendFeedbackEmail"

    @State private var contactType: AppBackendClient.ContactType = .bug
    @State private var email = ProfileContext.current.userDefaults.string(forKey: FeedbackView.savedEmailKey) ?? ""
    @State private var message = ""
    @State private var attachAudioLog = true
    @State private var isSending = false
    @State private var isShowingSuccess = false
    @State private var sendErrorMessage: String?

    private let client = AppBackendClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.text("feedback.field.type"), selection: $contactType) {
                ForEach(AppBackendClient.ContactType.allCases, id: \.self) { type in
                    Text(L10n.text(type.localizationKey)).tag(type)
                }
            }

            TextField(L10n.text("feedback.field.email"), text: $email)
                .textFieldStyle(.roundedBorder)

            Text(L10n.text("feedback.field.message"))
            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 140)
                .border(Color(nsColor: .separatorColor))
                .accessibilityLabel(L10n.text("feedback.field.message"))

            if contactType == .bug {
                Toggle(L10n.text("feedback.attachLog.toggle"), isOn: $attachAudioLog)
                Text(L10n.text("feedback.diagnostics.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("feedback.sending"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("feedback.button.cancel")) {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Button(L10n.text("feedback.button.send")) {
                    send()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canSend == false)
            }
        }
        .padding(20)
        .frame(width: 480)
        .disabled(isSending)
        .alert(L10n.text("feedback.success.title"), isPresented: $isShowingSuccess) {
            Button(L10n.text("feedback.success.button")) {
                resetForm()
                onClose()
            }
        } message: {
            Text(L10n.text("feedback.success.message"))
        }
        .alert(L10n.text("feedback.error.title"), isPresented: showsError) {
            Button(L10n.text("feedback.success.button")) {
                sendErrorMessage = nil
            }
        } message: {
            Text(sendErrorMessage ?? "")
        }
    }

    private var showsError: Binding<Bool> {
        Binding(
            get: { sendErrorMessage != nil },
            set: { if $0 == false { sendErrorMessage = nil } }
        )
    }

    private var canSend: Bool {
        isSending == false && isEmailPlausible && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    // The server fully validates the address; this only keeps the Send button
    // disabled until the field looks like an email at all.
    private var isEmailPlausible: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let atIndex = trimmed.firstIndex(of: "@"), trimmed.contains(" ") == false else {
            return false
        }
        return trimmed[trimmed.index(after: atIndex)...].contains(".")
    }

    private func send() {
        isSending = true
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let completion: (Result<Void, AppBackendClient.BackendError>) -> Void = { result in
            isSending = false
            switch result {
            case .success:
                ProfileContext.current.userDefaults.set(trimmedEmail, forKey: FeedbackView.savedEmailKey)
                isShowingSuccess = true
            case .failure(let error):
                sendErrorMessage = error.localizedMessage
            }
        }

        if contactType == .bug {
            var logFile: (name: String, data: Data)?
            if attachAudioLog, let data = try? Data(contentsOf: AudioLogger.fileURL), data.isEmpty == false {
                logFile = (name: "audio.log", data: data)
            }
            client.sendReport(
                email: trimmedEmail,
                summary: trimmedMessage,
                subjectHint: "Problème signalé depuis l'app (v\(AppBackendClient.appVersion))",
                sections: FeedbackDiagnostics.sections(preferences: preferencesStore.preferences),
                logFile: logFile,
                completion: completion
            )
        } else {
            client.sendContact(
                email: trimmedEmail,
                type: contactType,
                message: trimmedMessage,
                completion: completion
            )
        }
    }

    private func resetForm() {
        message = ""
        contactType = .bug
        attachAudioLog = true
    }
}

/// Builds the diagnostic sections attached to bug reports. Section titles and
/// values are intentionally in French: they end up in the report email, not in
/// the user interface.
private enum FeedbackDiagnostics {
    static func sections(preferences: AppPreferences) -> [AppBackendClient.ReportSection] {
        let bundle = Bundle.main
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let language = Bundle.main.preferredLocalizations.first ?? "?"

        let inputDevice = preferences.preferredInputDevice
        let outputDevice = preferences.preferredOutputDevice
        let profiles = preferences.advancedInputAudioProfiles
        let inputProfile = inputDevice.persistentID.flatMap { profiles.profilesByDeviceID[$0] }
            ?? profiles.fallbackProfile
            ?? AdvancedInputAudioPreferences()

        return [
            AppBackendClient.ReportSection(title: "Application", rows: [
                ("Version", AppBackendClient.appVersion),
                ("Build", build),
                ("Langue", language),
                ("VoiceOver actif", NSWorkspace.shared.isVoiceOverEnabled ? "oui" : "non"),
            ]),
            AppBackendClient.ReportSection(title: "Système", rows: [
                ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            ]),
            AppBackendClient.ReportSection(title: "Audio", rows: [
                ("Périphérique d'entrée", deviceDescription(inputDevice)),
                ("Périphérique de sortie", deviceDescription(outputDevice)),
                ("Annulation d'écho", inputProfile.echoCancellationEnabled ? "activée" : "désactivée"),
                ("Préréglage de canaux", inputProfile.preset.identifier),
                ("Mode micro", preferences.microphoneMode.rawValue),
            ]),
        ]
    }

    private static func deviceDescription(_ device: AudioDevicePreference) -> String {
        if device.usesSystemDefault {
            return "défaut système"
        }
        return device.displayName ?? device.persistentID ?? "?"
    }
}
