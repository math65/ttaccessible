//
//  SavedServerFormView.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SavedServerEditorMode {
    case add
    case edit
    case copyLink

    var title: String {
        switch self {
        case .add:
            return L10n.text("savedServer.editor.add.title")
        case .edit:
            return L10n.text("savedServer.editor.edit.title")
        case .copyLink:
            return L10n.text("connectedServer.serverLink.copy")
        }
    }
}

struct SavedServerFormView: View {
    @State private var draft: SavedServerDraft

    private let mode: SavedServerEditorMode
    private let onCancel: () -> Void
    private let onSave: (SavedServerDraft) -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case host
        case tcpPort
        case udpPort
        case encrypted
        case nickname
        case username
        case password
        case initialChannelPath
        case initialChannelPassword
    }

    init(
        mode: SavedServerEditorMode,
        draft: SavedServerDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SavedServerDraft) -> Void
    ) {
        self.mode = mode
        self._draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 14) {
                fieldRow(title: L10n.text("savedServer.form.name")) {
                    TextField("", text: $draft.name)
                        .focused($focusedField, equals: .name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.name"))
                }

                fieldRow(title: L10n.text("savedServer.form.host")) {
                    TextField("", text: $draft.host)
                        .focused($focusedField, equals: .host)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.host"))
                }

                fieldRow(title: L10n.text("savedServer.form.tcpPort")) {
                    TextField("", text: $draft.tcpPort)
                        .focused($focusedField, equals: .tcpPort)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.tcpPort"))
                }

                fieldRow(title: L10n.text("savedServer.form.udpPort")) {
                    TextField("", text: $draft.udpPort)
                        .focused($focusedField, equals: .udpPort)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.udpPort"))
                }

                Toggle(L10n.text("savedServer.form.encrypted"), isOn: $draft.encrypted)
                    .focused($focusedField, equals: .encrypted)
                    .accessibilityLabel(L10n.text("savedServer.form.encrypted"))

                if draft.encrypted {
                    encryptionSection
                }

                fieldRow(title: L10n.text("savedServer.form.nickname")) {
                    TextField("", text: $draft.nickname)
                        .focused($focusedField, equals: .nickname)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.nickname"))
                }

                Toggle(L10n.text("savedServer.form.webLogin"), isOn: $draft.useWebLogin)
                    .accessibilityLabel(L10n.text("savedServer.form.webLogin"))

                if draft.useWebLogin {
                    Text(L10n.text("savedServer.form.webLogin.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    fieldRow(title: L10n.text("savedServer.form.username")) {
                        TextField("", text: $draft.username)
                            .focused($focusedField, equals: .username)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("savedServer.form.username"))
                    }

                    fieldRow(title: L10n.text("savedServer.form.password")) {
                        SecureField("", text: $draft.password)
                            .focused($focusedField, equals: .password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("savedServer.form.password"))
                    }
                }

                fieldRow(title: L10n.text("savedServer.form.initialChannelPath")) {
                    TextField("", text: $draft.initialChannelPath)
                        .focused($focusedField, equals: .initialChannelPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.initialChannelPath"))
                }

                fieldRow(title: L10n.text("savedServer.form.initialChannelPassword")) {
                    SecureField("", text: $draft.initialChannelPassword)
                        .focused($focusedField, equals: .initialChannelPassword)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.initialChannelPassword"))
                }
            }

            HStack {
                Spacer()

                Button(L10n.text("common.cancel")) {
                    onCancel()
                }

                Button(mode == .copyLink ? L10n.text("connectedServer.serverLink.copyButton") : L10n.text("common.save")) {
                    onSave(draft)
                }
                .disabled(draft.isValid == false)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 460)
        .task {
            focusedField = .name
        }
    }

    // MARK: - Server certificate verification

    /// Peer verification, shown only for an encrypted server.
    ///
    /// The "verify" toggle stays disabled until a CA certificate is loaded — not
    /// as a nicety but because the SDK loads trust anchors from that CA alone,
    /// so turning verification on without one makes every connection fail.
    @ViewBuilder
    private var encryptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("savedServer.form.encryption.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Toggle(L10n.text("savedServer.form.encryption.verify"), isOn: $draft.encryption.verifyServerCertificate)
                .disabled(draft.encryption.canVerify == false)
                .accessibilityLabel(L10n.text("savedServer.form.encryption.verify"))
                .accessibilityHint(
                    draft.encryption.canVerify
                        ? L10n.text("savedServer.form.encryption.verify.hint")
                        : L10n.text("savedServer.form.encryption.verify.needsCA")
                )

            Text(verificationStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            certificateRow(
                title: L10n.text("savedServer.form.encryption.ca"),
                summary: summary(
                    for: draft.encryption.caCertificatePEM,
                    empty: L10n.text("savedServer.form.encryption.ca.none")
                ),
                importTitle: L10n.text("savedServer.form.encryption.ca.import"),
                removeTitle: L10n.text("savedServer.form.encryption.ca.remove"),
                hasValue: draft.encryption.caCertificatePEM.isEmpty == false,
                onImport: importCertificateAuthority,
                onRemove: removeCertificateAuthority
            )

            DisclosureGroup(L10n.text("savedServer.form.encryption.client.title")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("savedServer.form.encryption.client.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    certificateRow(
                        title: L10n.text("savedServer.form.encryption.client.certificate"),
                        summary: summary(
                            for: draft.encryption.clientCertificatePEM,
                            empty: L10n.text("savedServer.form.encryption.client.certificate.none")
                        ),
                        importTitle: L10n.text("savedServer.form.encryption.client.certificate.import"),
                        removeTitle: L10n.text("savedServer.form.encryption.client.certificate.remove"),
                        hasValue: draft.encryption.clientCertificatePEM.isEmpty == false,
                        onImport: importClientCertificate,
                        onRemove: removeClientCertificate
                    )

                    certificateRow(
                        title: L10n.text("savedServer.form.encryption.client.key"),
                        summary: draft.clientPrivateKeyPEM.isEmpty
                            ? L10n.text("savedServer.form.encryption.client.key.none")
                            : L10n.text("savedServer.form.encryption.client.key.loaded"),
                        importTitle: L10n.text("savedServer.form.encryption.client.key.import"),
                        removeTitle: L10n.text("savedServer.form.encryption.client.key.remove"),
                        hasValue: draft.clientPrivateKeyPEM.isEmpty == false,
                        onImport: importClientPrivateKey,
                        onRemove: removeClientPrivateKey
                    )
                }
                .padding(.top, 6)
            }
        }
        .padding(12)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// One line of the certificate area: what is loaded, and the two actions on
    /// it. The summary is folded into each button's accessibility label so a
    /// VoiceOver user hears what they are about to replace or remove without
    /// having to leave the button.
    @ViewBuilder
    private func certificateRow(
        title: String,
        summary: String,
        importTitle: String,
        removeTitle: String,
        hasValue: Bool,
        onImport: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                // The summary below announces itself as "<title>, <value>", so
                // leaving this visible to VoiceOver says the title twice in a row.
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(L10n.format("savedServer.form.encryption.a11y.itemStatus", title, summary))

                Spacer(minLength: 8)

                Button(importTitle, action: onImport)
                    .accessibilityLabel(L10n.format("savedServer.form.encryption.a11y.itemStatus", importTitle, summary))

                Button(removeTitle, action: onRemove)
                    .disabled(hasValue == false)
                    .accessibilityLabel(removeTitle)
            }
        }
    }

    private var verificationStatusText: String {
        if draft.encryption.isActive {
            return L10n.text("savedServer.form.encryption.status.verified")
        }
        if draft.encryption.canVerify {
            return L10n.text("savedServer.form.encryption.status.available")
        }
        return L10n.text("savedServer.form.encryption.status.unverified")
    }

    private func summary(for pem: String, empty: String) -> String {
        guard pem.isEmpty == false else { return empty }
        guard let subject = ServerEncryptionSettings.certificateSubjectSummary(from: pem) else {
            return L10n.text("savedServer.form.encryption.certificate.loaded")
        }
        return subject
    }

    // MARK: - Importing and removing certificates

    /// Importing or removing a certificate changes nothing a VoiceOver user can
    /// hear on their own: the file panel closes, focus returns to a button whose
    /// label has changed underneath it, and a changed label is never re-read.
    /// Each action therefore says the row's new state out loud.

    private func importCertificateAuthority() {
        importPEM(
            panelMessage: L10n.text("savedServer.form.encryption.ca.panelMessage"),
            validate: ServerEncryptionSettings.containsCertificate,
            invalidMessage: L10n.text("savedServer.form.encryption.error.notACertificate")
        ) { text in
            draft.encryption.caCertificatePEM = text
            announceRow(
                title: L10n.text("savedServer.form.encryption.ca"),
                summary: summary(for: text, empty: L10n.text("savedServer.form.encryption.ca.none"))
            )
        }
    }

    private func removeCertificateAuthority() {
        // Nothing left to verify against; leaving the flag set would silently
        // break the next connection. That side effect is announced too — the
        // checkbox it turns off is elsewhere on screen.
        let wasVerifying = draft.encryption.verifyServerCertificate
        draft.encryption.caCertificatePEM = ""
        draft.encryption.verifyServerCertificate = false

        var message = rowStatus(
            title: L10n.text("savedServer.form.encryption.ca"),
            summary: L10n.text("savedServer.form.encryption.ca.none")
        )
        if wasVerifying {
            message += ". " + L10n.text("savedServer.form.encryption.a11y.verificationTurnedOff")
        }
        announce(message)
    }

    private func importClientCertificate() {
        importPEM(
            panelMessage: L10n.text("savedServer.form.encryption.client.certificate.panelMessage"),
            validate: ServerEncryptionSettings.containsCertificate,
            invalidMessage: L10n.text("savedServer.form.encryption.error.notACertificate")
        ) { text in
            draft.encryption.clientCertificatePEM = text
            announceRow(
                title: L10n.text("savedServer.form.encryption.client.certificate"),
                summary: summary(
                    for: text,
                    empty: L10n.text("savedServer.form.encryption.client.certificate.none")
                )
            )
        }
    }

    private func removeClientCertificate() {
        draft.encryption.clientCertificatePEM = ""
        announceRow(
            title: L10n.text("savedServer.form.encryption.client.certificate"),
            summary: L10n.text("savedServer.form.encryption.client.certificate.none")
        )
    }

    private func importClientPrivateKey() {
        importPEM(
            panelMessage: L10n.text("savedServer.form.encryption.client.key.panelMessage"),
            validate: ServerEncryptionSettings.containsPrivateKey,
            invalidMessage: L10n.text("savedServer.form.encryption.error.notAPrivateKey")
        ) { text in
            draft.clientPrivateKeyPEM = text
            announceRow(
                title: L10n.text("savedServer.form.encryption.client.key"),
                summary: L10n.text("savedServer.form.encryption.client.key.loaded")
            )
        }
    }

    private func removeClientPrivateKey() {
        draft.clientPrivateKeyPEM = ""
        announceRow(
            title: L10n.text("savedServer.form.encryption.client.key"),
            summary: L10n.text("savedServer.form.encryption.client.key.none")
        )
    }

    private func rowStatus(title: String, summary: String) -> String {
        L10n.format("savedServer.form.encryption.a11y.itemStatus", title, summary)
    }

    private func announceRow(title: String, summary: String) {
        announce(rowStatus(title: title, summary: summary))
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp.accessibilityWindow() ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority:
                    NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func importPEM(
        panelMessage: String,
        validate: (String) -> Bool,
        invalidMessage: String,
        assign: (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("savedServer.form.encryption.panelTitle")
        panel.message = panelMessage
        panel.prompt = L10n.text("savedServer.form.encryption.panelPrompt")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // PEM has no UTI of its own — .pem/.crt/.cer/.key arrive as plain text or
        // as unclassified data — so the panel accepts any file and the armour
        // check below does the real filtering.
        panel.allowedContentTypes = [.data]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            presentImportError(L10n.text("savedServer.form.encryption.error.unreadable"))
            return
        }
        guard validate(text) else {
            presentImportError(invalidMessage)
            return
        }
        assign(text)
    }

    private func presentImportError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("savedServer.form.encryption.error.title")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.text("common.ok"))
        alert.runModal()
    }

    @ViewBuilder
    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity)
        }
    }
}
