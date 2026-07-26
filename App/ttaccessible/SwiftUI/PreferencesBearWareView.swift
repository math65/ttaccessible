//
//  PreferencesBearWareView.swift
//  ttaccessible
//
//  BearWare web-login (bearware.dk) account setup. A free BearWare account lets
//  the user log in to any server that has web login enabled, without a local
//  account on that server. Web login is then enabled per server in its settings.
//

import SwiftUI

struct PreferencesBearWareView: View {
    @State private var credential: BearWareCredential?
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private let credentialStore = BearWareCredentialStore()
    private let webLoginClient = BearWareWebLoginClient()

    var body: some View {
        PreferencesPaneScrollView(accessibilityLabel: L10n.text("preferences.bearware.title")) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("preferences.bearware.section"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if let credential {
                    Text(L10n.format(
                        "preferences.bearware.signedInAs",
                        credential.nickname.isEmpty ? credential.username : credential.nickname
                    ))
                    Button(L10n.text("preferences.bearware.signOut")) {
                        credentialStore.clear()
                        self.credential = nil
                        errorMessage = nil
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.bearware.username"))
                        TextField("", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("preferences.bearware.username"))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("preferences.bearware.password"))
                        SecureField("", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(L10n.text("preferences.bearware.password"))
                    }

                    HStack(spacing: 8) {
                        Button(L10n.text("preferences.bearware.signIn")) {
                            Task { await signIn() }
                        }
                        .disabled(canSubmit == false)

                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Text(L10n.text("preferences.bearware.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            credential = credentialStore.load()
        }
    }

    private var canSubmit: Bool {
        isBusy == false
            && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && password.isEmpty == false
    }

    @MainActor
    private func signIn() async {
        guard canSubmit else { return }
        errorMessage = nil
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        isBusy = true
        defer { isBusy = false }

        do {
            let result = try await webLoginClient.authenticate(username: trimmedUsername, password: password)
            try credentialStore.save(result)
            credential = result
            username = ""
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
