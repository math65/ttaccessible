//
//  BearWareWebLogin.swift
//  ttaccessible
//
//  TeamTalk "web login" (bearware.dk accounts). This is NOT an SDK feature: it
//  is an HTTP handshake with bearware.dk wrapped around the normal SDK login.
//
//  Two phases:
//   - Phase A (one-time setup, `authenticate`): exchange the user's bearware.dk
//     credentials for a long-lived token. The token (not the password) is then
//     stored in the keychain via `BearWareCredentialStore`.
//   - Phase B (per connection, `clientAuth`): after the TCP connection succeeds
//     the TeamTalk server hands us a random `szAccessToken`. We post it to
//     bearware.dk together with the stored token; bearware confirms the login
//     and returns the username to pass to `TT_DoLoginEx` (password empty).
//
//  Mirrors the Qt client (`appinfo.h`, `bearwarelogindlg.cpp`, `mainwindow.cpp`).
//

import Foundation

/// Persisted bearware.dk identity. The password is never stored — only the token.
struct BearWareCredential: Codable, Equatable {
    var username: String
    var nickname: String
    var token: String
}

enum BearWareWebLogin {
    /// Literal username stored on a server record when web login is enabled.
    static let username = "bearware"
    /// Alternative username form some accounts use (e.g. `john@bearware.dk`).
    static let usernamePostfix = "@bearware.dk"

    private static let endpoint = "https://www.bearware.dk/teamtalk/weblogin.php"

    /// True when a server record's username designates a bearware web login.
    static func isWebLogin(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(usernamePostfix) {
            return true
        }
        return trimmed.caseInsensitiveCompare(Self.username) == .orderedSame
    }

    /// Common query items identifying this client to bearware.dk.
    private static var baseQueryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "client", value: "ttaccessible"),
            URLQueryItem(name: "version", value: appVersion),
            URLQueryItem(name: "dllversion", value: sdkVersion),
            URLQueryItem(name: "os", value: "mac")
        ]
    }

    static func authURL(username: String, password: String) -> URL? {
        makeURL(items: baseQueryItems + [
            URLQueryItem(name: "service", value: "bearware"),
            URLQueryItem(name: "action", value: "auth"),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ])
    }

    static func clientAuthURL(username: String, token: String, accessToken: String) -> URL? {
        makeURL(items: baseQueryItems + [
            URLQueryItem(name: "service", value: "bearware"),
            URLQueryItem(name: "action", value: "clientauth"),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "accesstoken", value: accessToken)
        ])
    }

    private static func makeURL(items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: endpoint)
        // URLComponents.queryItems leaves '+' (and other sub-delimiters)
        // unescaped in values. bearware.dk decodes '+' as a space, which
        // corrupts tokens/access-tokens/passwords that contain '+'. Percent-
        // encode every value down to RFC 3986 unreserved characters so '+',
        // '/', '&', '=' etc. survive the round-trip. The names are all safe
        // ASCII literals and need no encoding.
        components?.percentEncodedQueryItems = items.map { item in
            URLQueryItem(name: item.name, value: item.value.map(percentEncode))
        }
        return components?.url
    }

    private static let unreservedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? value
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static var sdkVersion: String {
        String(cString: TT_GetVersion())
    }
}

enum BearWareWebLoginError: LocalizedError {
    /// Network / transport failure reaching bearware.dk.
    case network(Error)
    /// bearware.dk responded but the payload could not be parsed.
    case invalidResponse
    /// bearware.dk rejected the credentials or token.
    case rejected

    var errorDescription: String? {
        switch self {
        case .network:
            return L10n.text("bearware.error.network")
        case .invalidResponse:
            return L10n.text("bearware.error.invalidResponse")
        case .rejected:
            return L10n.text("bearware.error.rejected")
        }
    }
}

/// URLSession client for the two bearware.dk web-login HTTP calls.
final class BearWareWebLoginClient {
    private let session: URLSession

    init(session: URLSession = BearWareWebLoginClient.makeDefaultSession()) {
        self.session = session
    }

    /// A dedicated session with a short request timeout. The synchronous
    /// `clientAuth` runs on the serial TeamTalk SDK queue; without a tight
    /// timeout a slow/unreachable bearware.dk would block every SDK operation
    /// (and starve auto-reconnect) for up to URLSession's 60s default.
    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Phase A — exchange bearware.dk credentials for a token. Async; called
    /// from the Preferences UI.
    func authenticate(username: String, password: String) async throws -> BearWareCredential {
        guard let url = BearWareWebLogin.authURL(username: username, password: password) else {
            throw BearWareWebLoginError.invalidResponse
        }

        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            throw BearWareWebLoginError.network(error)
        }

        guard let bearware = Self.bearwareElement(from: data) else {
            throw BearWareWebLoginError.invalidResponse
        }

        let resolvedUsername = bearware.childText(named: "username")
        let nickname = bearware.childText(named: "nickname")
        let token = bearware.childText(named: "token")

        guard resolvedUsername.isEmpty == false, token.isEmpty == false else {
            throw BearWareWebLoginError.rejected
        }

        return BearWareCredential(username: resolvedUsername, nickname: nickname, token: token)
    }

    /// Phase B — confirm a server access token against the stored bearware token.
    /// Synchronous: it is invoked from the TeamTalk serial queue between
    /// `CLIENTEVENT_CON_SUCCESS` and `TT_DoLoginEx`. Returns the username to log
    /// in with (empty string when bearware does not override it).
    func clientAuth(username: String, token: String, accessToken: String) throws -> String {
        guard let url = BearWareWebLogin.clientAuthURL(username: username, token: token, accessToken: accessToken) else {
            throw BearWareWebLoginError.invalidResponse
        }

        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var transportError: Error?

        let task = session.dataTask(with: url) { data, _, error in
            resultData = data
            transportError = error
            semaphore.signal()
        }
        task.resume()
        // The session's request timeout (8s) guarantees the completion fires,
        // but bound the wait anyway so the serial SDK queue can never park
        // indefinitely if URLSession misbehaves.
        if semaphore.wait(timeout: .now() + 12) == .timedOut {
            task.cancel()
            throw BearWareWebLoginError.network(URLError(.timedOut))
        }

        if let transportError {
            throw BearWareWebLoginError.network(transportError)
        }
        // Phase B is best-effort (mirrors the Qt client): a missing or
        // non-conforming <teamtalk><bearware> body must NOT surface as a fatal
        // error — it only means bearware did not override the username. Return an
        // empty string so the caller falls back to the record username. The strict
        // `.invalidResponse` throw is reserved for `authenticate` (Phase A), the
        // interactive Preferences setup where the user must see a real error.
        guard let resultData, let bearware = Self.bearwareElement(from: resultData) else {
            return ""
        }

        return bearware.childText(named: "username")
    }

    // MARK: - XML helpers

    /// Returns the `<bearware>` element from a `<teamtalk><bearware>…</bearware></teamtalk>` payload.
    private static func bearwareElement(from data: Data) -> XMLElement? {
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
              let root = document.rootElement(), root.name == "teamtalk",
              let bearware = root.elements(forName: "bearware").first else {
            return nil
        }
        return bearware
    }
}
