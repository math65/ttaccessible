//
//  TeamTalkConnectionController+TransmitControl.swift
//  ttaccessible
//
//  The Qt client's "Transmit Control" menu: allow or forbid one user — or, in a
//  classroom, everyone — to send a given stream in a channel. It edits the
//  channel's `transmitUsers` list and sends the whole channel back with
//  `TT_DoUpdateChannel`, which the server accepts from a channel operator or an
//  account holding USERRIGHT_MODIFY_CHANNELS.
//

import Foundation

extension TeamTalkConnectionController {
    /// Allows or forbids `stream` for `userID` (or `TransmitUsersList.everyoneUserID`)
    /// in `channelID`.
    ///
    /// Read-modify-write on the queue, from the channel as the SDK holds it at
    /// that moment, so a concurrent edit by another operator is kept rather than
    /// overwritten by a stale snapshot. Only the list changes: every other field
    /// goes back exactly as the server sent it — the codec in particular, since
    /// the server refuses any codec change in an occupied channel.
    func setTransmission(
        _ stream: TransmitStream,
        allowed: Bool,
        userID: Int32,
        channelID: Int32,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self,
                  let instance = self.instance,
                  let record = self.connectedRecord else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            var chan = Channel()
            guard TT_GetChannel(instance, channelID, &chan) != 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            let current = TransmitUsersList(channel: &chan)
            guard let updated = current.setting(stream, allowed: allowed, userID: userID) else {
                let message = L10n.format("transmitControl.error.listFull", TransmitUsersList.capacity)
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.internalError(message))) }
                return
            }
            guard updated != current else {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            updated.write(into: &chan)

            let commandID = withUnsafeMutablePointer(to: &chan) { TT_DoUpdateChannel(instance, $0) }
            guard commandID > 0 else {
                DispatchQueue.main.async { completion(.failure(TeamTalkConnectionError.connectionFailed)) }
                return
            }

            do {
                try self.waitForCommandCompletionLocked(instance: instance, commandID: commandID)
                self.publishSessionLocked(instance: instance, record: record)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
