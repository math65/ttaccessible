//
//  SavedServerFormView.swift
//  ttaccessible
//
//  Created by Codex on 17/03/2026.
//

import SwiftUI

enum SavedServerEditorMode {
    case add
    case edit

    var title: String {
        switch self {
        case .add:
            return L10n.text("savedServer.editor.add.title")
        case .edit:
            return L10n.text("savedServer.editor.edit.title")
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

                fieldRow(title: L10n.text("savedServer.form.nickname")) {
                    TextField("", text: $draft.nickname)
                        .focused($focusedField, equals: .nickname)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("savedServer.form.nickname"))
                }

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

                Button(L10n.text("common.save")) {
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
