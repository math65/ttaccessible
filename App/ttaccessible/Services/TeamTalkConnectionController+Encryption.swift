//
//  TeamTalkConnectionController+Encryption.swift
//  ttaccessible
//
//  TLS peer verification: hands the SDK an EncryptionContext before every
//  TT_Connect.
//

import Foundation

extension TeamTalkConnectionController {

    /// Errors raised while preparing the TLS context. They abort the connect
    /// deliberately: a record that asks for verification must never fall back to
    /// an unverified connection, which would be worse than failing — the user
    /// would believe the server was authenticated when it was not.
    enum EncryptionContextError: LocalizedError {
        case materializationFailed
        case sdkRejectedContext

        var errorDescription: String? {
            switch self {
            case .materializationFailed:
                return L10n.text("teamtalk.connection.error.encryptionMaterializeFailed")
            case .sdkRejectedContext:
                return L10n.text("teamtalk.connection.error.encryptionContextRejected")
            }
        }
    }

    /// Configures (or clears) peer verification on `instance` for `record`.
    ///
    /// Must be called before every `TT_Connect`, including on the reconnect
    /// path, and including when the record needs nothing: instances are reused
    /// (background prewarm, plus the warm instance kept across a disconnect), and
    /// `TT_SetEncryptionContext` is what destroys and recreates the underlying
    /// `ACE_SSL_Context`. Skipping the call would let one server's pinned CA — or
    /// its client certificate — silently apply to the next connection.
    ///
    /// Runs on the TeamTalk serial queue, like every other SDK call.
    func applyEncryptionContextLocked(
        instance: UnsafeMutableRawPointer,
        record: SavedServerRecord,
        options: TeamTalkConnectOptions
    ) throws {
        // A plaintext server takes no material at all: skipping the keychain read
        // here keeps the connect path off it entirely for the common case.
        let settings = record.encrypted ? record.encryption : ServerEncryptionSettings()
        let privateKey = record.encrypted
            ? (options.clientPrivateKeyOverride ?? (try? passwordStore.clientPrivateKey(for: record.id)) ?? "")
            : ""

        var context = EncryptionContext()
        // -1 means "no certificate check" and is what keeps SetupEncryptionContext
        // from calling set_verify_peer at all. A zeroed struct would leave 0 here,
        // which the SDK reads as a request to configure verification.
        context.nVerifyDepth = -1

        guard settings.isConfigured || privateKey.isEmpty == false else {
            try setEncryptionContextLocked(instance: instance, context: &context, verifying: false)
            return
        }

        // The SDK takes file paths, so the stored PEM text has to touch the disk.
        // It is read synchronously inside TT_SetEncryptionContext
        // (SSL_CTX_use_certificate_file / _load_verify_locations), so the whole
        // directory goes away the moment the call returns — the client private
        // key never outlives it.
        let directory: URL
        do {
            directory = try makePEMScratchDirectory()
        } catch {
            AudioLogger.log("encryption: cannot create PEM scratch dir: %@", error.localizedDescription)
            throw EncryptionContextError.materializationFailed
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            if settings.caCertificatePEM.isEmpty == false {
                let path = try writePEM(settings.caCertificatePEM, named: "ca.pem", in: directory)
                copyTTString(path, into: &context.szCAFile)
            }
            if settings.clientCertificatePEM.isEmpty == false {
                let path = try writePEM(settings.clientCertificatePEM, named: "client.pem", in: directory)
                copyTTString(path, into: &context.szCertificateFile)
            }
            if privateKey.isEmpty == false {
                let path = try writePEM(privateKey, named: "client-key.pem", in: directory)
                copyTTString(path, into: &context.szPrivateKeyFile)
            }
        } catch {
            AudioLogger.log("encryption: cannot write PEM material: %@", error.localizedDescription)
            throw EncryptionContextError.materializationFailed
        }

        if settings.isActive {
            context.bVerifyPeer = 1
            // Chain depth. Deliberately not the SDK's documented default of 0,
            // which the Qt client leaves in place: what ACE does with a depth of 0
            // was NOT verified here (its source is not vendored with the SDK), and
            // if it forwards the literal to SSL_CTX_set_verify_depth, a chain with
            // an intermediate would be rejected. 9 is OpenSSL's traditional limit
            // and relaxes nothing the pinned CA does not already enforce.
            context.nVerifyDepth = 9
        }

        try setEncryptionContextLocked(instance: instance, context: &context, verifying: settings.isActive)
    }

    private func setEncryptionContextLocked(
        instance: UnsafeMutableRawPointer,
        context: inout EncryptionContext,
        verifying: Bool
    ) throws {
        guard TT_SetEncryptionContext(instance, &context) != 0 else {
            AudioLogger.log("encryption: TT_SetEncryptionContext refused the context (verifying=%@)", verifying ? "yes" : "no")
            throw EncryptionContextError.sdkRejectedContext
        }
        AudioLogger.log("encryption: context applied, server verification %@", verifying ? "ON" : "off")
    }

    // MARK: - PEM scratch files

    private func makePEMScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func writePEM(_ text: String, named name: String, in directory: URL) throws -> String {
        let url = directory.appendingPathComponent(name)
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url.path
    }
}
