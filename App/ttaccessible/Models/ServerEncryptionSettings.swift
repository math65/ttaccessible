//
//  ServerEncryptionSettings.swift
//  ttaccessible
//

import Foundation
import Security

/// Per-server TLS peer-verification settings, handed to the SDK through
/// `TT_SetEncryptionContext` right before `TT_Connect`.
///
/// Without this, the SDK falls back to `ACE_SSL_Context::instance()`, a context
/// with no trust anchors and no verification: the connection is encrypted but
/// the server is never authenticated, so a self-signed (or outright forged)
/// certificate is accepted silently.
///
/// **The CA certificate is mandatory.** `SetupEncryptionContext` in the SDK only
/// calls `load_trusted_ca()` when a CA file or directory is set, and passes
/// `use_env_defaults = false`. Turning verification on without supplying a CA
/// therefore leaves the context with zero trust anchors and *every* connection
/// fails. The Qt client greys its own checkbox out for the same reason.
///
/// Scope of the guarantee: OpenSSL's `SSL_VERIFY_PEER` validates the certificate
/// *chain*. Nothing in TeamTalkLib calls `X509_VERIFY_PARAM_set1_host`, so the
/// certificate's name is never matched against the host we dialed. Pinning a
/// private CA (the usual case: a self-signed server certificate used as its own
/// authority) is thus genuinely strong, because only that issuer is trusted;
/// pointing this at a public root bundle would not be, since any certificate
/// from any public CA would satisfy the chain check.
struct ServerEncryptionSettings: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case verifyServerCertificate
        case caCertificatePEM
        case clientCertificatePEM
    }

    /// Requests `SSL_VERIFY_PEER`. Only honoured when a CA certificate is also
    /// present — see `isActive`.
    var verifyServerCertificate: Bool

    /// PEM text of the authority the server's certificate must chain up to.
    /// Stored as text rather than a file path so it survives sandbox bookmark
    /// expiry and travels inside exported `.tt` files, matching the Qt client.
    var caCertificatePEM: String

    /// PEM text of the client certificate, for servers that verify the client
    /// in turn (`bVerifyPeer` on the server side). Its private key is NOT here:
    /// it is a secret and lives in the keychain with the server password.
    var clientCertificatePEM: String

    init(
        verifyServerCertificate: Bool = false,
        caCertificatePEM: String = "",
        clientCertificatePEM: String = ""
    ) {
        self.verifyServerCertificate = verifyServerCertificate
        self.caCertificatePEM = caCertificatePEM
        self.clientCertificatePEM = clientCertificatePEM
    }

    /// Whether verification can be switched on at all.
    var canVerify: Bool {
        caCertificatePEM.isEmpty == false
    }

    /// Whether the next connection will actually authenticate the server.
    var isActive: Bool {
        verifyServerCertificate && canVerify
    }

    /// Whether anything at all needs to reach the SDK. A record with only a
    /// client certificate still does (mutual TLS without server verification).
    var isConfigured: Bool {
        caCertificatePEM.isEmpty == false || clientCertificatePEM.isEmpty == false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verifyServerCertificate = try container.decodeIfPresent(Bool.self, forKey: .verifyServerCertificate) ?? false
        caCertificatePEM = try container.decodeIfPresent(String.self, forKey: .caCertificatePEM) ?? ""
        clientCertificatePEM = try container.decodeIfPresent(String.self, forKey: .clientCertificatePEM) ?? ""
    }

    // MARK: - PEM validation

    /// Rejects a file the user picked by mistake before it reaches OpenSSL,
    /// where the only symptom would be a connection that fails with a cryptic
    /// error. Deliberately shallow: it checks the armour, not the contents.
    static func containsCertificate(_ text: String) -> Bool {
        text.contains("-----BEGIN CERTIFICATE-----")
    }

    static func containsPrivateKey(_ text: String) -> Bool {
        text.contains("-----BEGIN PRIVATE KEY-----")
            || text.contains("-----BEGIN RSA PRIVATE KEY-----")
            || text.contains("-----BEGIN EC PRIVATE KEY-----")
            || text.contains("-----BEGIN ENCRYPTED PRIVATE KEY-----")
    }
}

// MARK: - Reading a PEM back

extension ServerEncryptionSettings {
    /// Subject of the first certificate in a PEM blob, for display next to the
    /// import button. Lets the user confirm at a glance that they picked the
    /// right file — "tt.example.com" rather than "a certificate is loaded".
    /// Returns nil for anything unreadable; the caller falls back to a generic
    /// label rather than treating it as an error.
    static func certificateSubjectSummary(from pem: String) -> String? {
        guard let der = firstCertificateDER(in: pem),
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return nil
        }
        guard let summary = SecCertificateCopySubjectSummary(certificate) as String?,
              summary.isEmpty == false else {
            return nil
        }
        return summary
    }

    private static func firstCertificateDER(in pem: String) -> Data? {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        guard let start = pem.range(of: begin),
              let stop = pem.range(of: end, range: start.upperBound..<pem.endIndex) else {
            return nil
        }
        let body = pem[start.upperBound..<stop.lowerBound]
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return Data(base64Encoded: body)
    }
}
