//
//  ServerCertificateVerificationTests.swift
//  ttaccessibleTests
//
//  Peer verification was reported by a tester who set up a TeamTalk Pro server
//  with a deliberately self-signed certificate: the app connected, the TLS
//  handshake was genuine, and nothing anywhere said the server's identity had
//  never been checked. It had not — `TT_SetEncryptionContext` was never called,
//  so the SDK ran on a context with no trust anchors and no verification.
//
//  Two invariants are worth pinning down here, both silent failures if broken:
//  a record written by an older build must still decode, and a "verify" flag
//  must never survive into a state where the SDK cannot honour it. The second
//  matters because the SDK loads its trust anchors from the record's CA alone —
//  verification requested without a CA does not fall back to something weaker,
//  it fails every connection.
//

import XCTest
@testable import ttaccessible

final class ServerCertificateVerificationTests: XCTestCase {

    // MARK: - Decoding a record written before the feature existed

    /// Every saved server on every existing install lacks the `encryption` key.
    /// Losing them all to a decode failure is the one unacceptable outcome.
    func testRecordFromOlderBuildDecodesWithVerificationOff() throws {
        let json = """
        {
            "id": "6C6E5C3E-1F2B-4E19-8C1E-7A0B1D2E3F40",
            "name": "Old entry",
            "host": "tt.example.com",
            "tcpPort": 10333,
            "udpPort": 10333,
            "encrypted": true,
            "nickname": "Someone",
            "username": "someone"
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(SavedServerRecord.self, from: json)

        XCTAssertTrue(record.encrypted)
        XCTAssertFalse(record.encryption.verifyServerCertificate)
        XCTAssertEqual(record.encryption.caCertificatePEM, "")
        XCTAssertFalse(record.encryption.isActive)
    }

    /// A half-written block — the flag persisted, the CA not yet — must decode
    /// rather than throw, and land on the safe side.
    func testPartialEncryptionBlockDecodes() throws {
        let json = """
        { "verifyServerCertificate": true }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(ServerEncryptionSettings.self, from: json)

        XCTAssertTrue(settings.verifyServerCertificate)
        XCTAssertFalse(settings.canVerify)
        XCTAssertFalse(settings.isActive, "no CA means the SDK has nothing to verify against")
    }

    func testRoundTripPreservesSettings() throws {
        let original = ServerEncryptionSettings(
            verifyServerCertificate: true,
            caCertificatePEM: "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----",
            clientCertificatePEM: "-----BEGIN CERTIFICATE-----\nBBBB\n-----END CERTIFICATE-----"
        )

        let decoded = try JSONDecoder().decode(
            ServerEncryptionSettings.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isActive)
    }

    // MARK: - isActive is the only thing the connect path may trust

    func testVerificationNeedsBothTheFlagAndTheAuthority() {
        let ca = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----"

        XCTAssertFalse(ServerEncryptionSettings(verifyServerCertificate: true).isActive)
        XCTAssertFalse(ServerEncryptionSettings(verifyServerCertificate: false, caCertificatePEM: ca).isActive)
        XCTAssertTrue(ServerEncryptionSettings(verifyServerCertificate: true, caCertificatePEM: ca).isActive)
    }

    /// A client certificate alone still has to reach the SDK: mutual TLS without
    /// server verification is a legitimate configuration.
    func testClientCertificateAloneCountsAsConfigured() {
        let settings = ServerEncryptionSettings(
            clientCertificatePEM: "-----BEGIN CERTIFICATE-----\nBBBB\n-----END CERTIFICATE-----"
        )

        XCTAssertTrue(settings.isConfigured)
        XCTAssertFalse(settings.isActive)
    }

    // MARK: - Normalisation on save

    /// Turning encryption back off must not leave a verification flag behind for
    /// a later re-enable to resurrect against a CA that is no longer there.
    func testDraftDropsEncryptionSettingsWhenConnectionIsPlaintext() {
        var draft = SavedServerDraft(name: "S", host: "h", encrypted: false)
        draft.encryption = ServerEncryptionSettings(
            verifyServerCertificate: true,
            caCertificatePEM: "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----"
        )

        XCTAssertEqual(draft.sanitizedEncryption, ServerEncryptionSettings())
    }

    func testDraftClearsVerifyFlagWhenTheAuthorityWasRemoved() {
        var draft = SavedServerDraft(name: "S", host: "h", encrypted: true)
        draft.encryption = ServerEncryptionSettings(verifyServerCertificate: true, caCertificatePEM: "")

        XCTAssertFalse(draft.sanitizedEncryption.verifyServerCertificate)
    }

    func testDraftKeepsVerificationWhenFullyConfigured() {
        var draft = SavedServerDraft(name: "S", host: "h", encrypted: true)
        draft.encryption = ServerEncryptionSettings(
            verifyServerCertificate: true,
            caCertificatePEM: "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----"
        )

        XCTAssertTrue(draft.sanitizedEncryption.isActive)
        XCTAssertTrue(draft.makeRecord(id: UUID())?.encryption.isActive == true)
    }

    // MARK: - PEM shape checks, which is all the import panel promises

    func testPEMArmourDetection() {
        let certificate = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----"
        let key = "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----"
        let ecKey = "-----BEGIN EC PRIVATE KEY-----\nAAAA\n-----END EC PRIVATE KEY-----"

        XCTAssertTrue(ServerEncryptionSettings.containsCertificate(certificate))
        XCTAssertFalse(ServerEncryptionSettings.containsCertificate(key))
        XCTAssertTrue(ServerEncryptionSettings.containsPrivateKey(key))
        XCTAssertTrue(ServerEncryptionSettings.containsPrivateKey(ecKey))
        XCTAssertFalse(ServerEncryptionSettings.containsPrivateKey(certificate))
        XCTAssertFalse(ServerEncryptionSettings.containsCertificate("just some text"))
    }

    /// Garbage between the armour must come back nil, not crash and not be
    /// mistaken for a readable subject.
    func testCertificateSubjectSummaryRejectsGarbage() {
        XCTAssertNil(ServerEncryptionSettings.certificateSubjectSummary(from: "not a pem"))
        XCTAssertNil(ServerEncryptionSettings.certificateSubjectSummary(
            from: "-----BEGIN CERTIFICATE-----\n!!!!\n-----END CERTIFICATE-----"
        ))
    }

    // MARK: - Import keeps what it was given

    private static let caPEM = "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----"
    private static let keyPEM = "-----BEGIN PRIVATE KEY-----\nBBBB\n-----END PRIVATE KEY-----"

    private func record(
        id: UUID = UUID(),
        encryption: ServerEncryptionSettings = ServerEncryptionSettings()
    ) -> SavedServerRecord {
        SavedServerRecord(
            id: id,
            name: "Secure",
            host: "tt.example.com",
            tcpPort: 10333,
            udpPort: 10333,
            encrypted: true,
            nickname: "Someone",
            username: "someone",
            encryption: encryption
        )
    }

    /// `withID` rebuilt the record field by field and forgot this one, so every
    /// import came out encrypted but unverified.
    func testWithIDKeepsEncryptionSettings() {
        let settings = ServerEncryptionSettings(verifyServerCertificate: true, caCertificatePEM: Self.caPEM)
        let copy = record(encryption: settings).withID(UUID())
        XCTAssertEqual(copy.encryption, settings)
        XCTAssertTrue(copy.encryption.isActive)
    }

    /// A Qt INI or plist config never carries a CA: re-importing one over a
    /// verified server must not switch its verification off.
    func testReimportWithoutTLSMaterialKeepsTheExistingSettings() {
        let settings = ServerEncryptionSettings(verifyServerCertificate: true, caCertificatePEM: Self.caPEM)
        let existing = record(encryption: settings)

        let replaced = record().replacing(existing)

        XCTAssertEqual(replaced.id, existing.id)
        XCTAssertEqual(replaced.encryption, settings)
    }

    func testReimportWithTLSMaterialReplacesTheExistingSettings() {
        let existing = record(encryption: ServerEncryptionSettings(verifyServerCertificate: true, caCertificatePEM: Self.caPEM))
        let newer = ServerEncryptionSettings(
            verifyServerCertificate: false,
            caCertificatePEM: "-----BEGIN CERTIFICATE-----\nCCCC\n-----END CERTIFICATE-----"
        )

        let replaced = record(encryption: newer).replacing(existing)

        XCTAssertEqual(replaced.id, existing.id)
        XCTAssertEqual(replaced.encryption, newer)
    }

    /// The whole path Rocco traced: a .tt file with a trusted certificate,
    /// exported then imported, keeps its authority, its verify flag and its key.
    func testTTFileImportKeepsVerificationAndKey() throws {
        let settings = ServerEncryptionSettings(verifyServerCertificate: true, caCertificatePEM: Self.caPEM)
        let data = try XCTUnwrap(TTFileService().generateFileContents(
            record: record(encryption: settings),
            password: "secret",
            clientPrivateKeyPEM: Self.keyPEM
        ))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-import-\(UUID().uuidString).tt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try XCTUnwrap(TeamTalkConfigImporter().loadServers(from: url).first)
        let saved = imported.record.withID(UUID())
        let resaved = imported.record.replacing(record())

        XCTAssertEqual(saved.encryption, settings)
        XCTAssertTrue(saved.encryption.isActive)
        XCTAssertEqual(resaved.encryption, settings)
        XCTAssertEqual(imported.clientPrivateKeyPEM, Self.keyPEM)
    }

    /// `EncryptionContext` has no passphrase field: both encrypted PEM forms
    /// must be caught before they reach OpenSSL.
    func testPassphraseProtectedKeysAreRecognised() {
        let pkcs8 = "-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----"
        let legacy = """
        -----BEGIN RSA PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        DEK-Info: AES-128-CBC,00112233445566778899AABBCCDDEEFF

        AAAA
        -----END RSA PRIVATE KEY-----
        """

        XCTAssertTrue(ServerEncryptionSettings.isPassphraseProtected(pkcs8))
        XCTAssertTrue(ServerEncryptionSettings.isPassphraseProtected(legacy))
        XCTAssertFalse(ServerEncryptionSettings.isPassphraseProtected(Self.keyPEM))
        XCTAssertTrue(ServerEncryptionSettings.containsPrivateKey(legacy))
    }
}
