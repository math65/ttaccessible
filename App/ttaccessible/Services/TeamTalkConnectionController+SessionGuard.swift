//
//  TeamTalkConnectionController+SessionGuard.swift
//  ttaccessible
//

import Foundation

extension TeamTalkConnectionController {

    /// True while auto-reconnect is waiting for a new TeamTalk instance.
    var isReconnectingLocked: Bool {
        reconnectTimer != nil
    }

    /// User-facing error when session work is requested without a live SDK instance.
    func sessionUnavailableErrorLocked() -> TeamTalkConnectionError {
        if isReconnectingLocked {
            return .internalError(L10n.text("connectedServer.error.reconnecting"))
        }
        return .connectionFailed
    }

    /// If the UI still shows a connected server but the SDK session is gone, surface disconnect instead of limbo.
    func healStaleSessionIfNeededLocked() {
        guard instance == nil, connectedRecord == nil, !isReconnectingLocked else { return }
        publishDisconnected(message: L10n.text("connectedServer.disconnect.connectionLost"))
    }

    func finishOnMain<Success>(_ result: Result<Success, Error>, completion: @escaping (Result<Success, Error>) -> Void) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
