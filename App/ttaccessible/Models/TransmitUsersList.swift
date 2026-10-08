//
//  TransmitUsersList.swift
//  ttaccessible
//
//  A channel's `transmitUsers` array — the list behind the Qt client's
//  "Transmit Control" menu — as a value the menus can read and edit.
//
//  The same list means opposite things either side of CHANNEL_CLASSROOM, which
//  is the server's rule (`Channel::CanTransmit`), not a quirk of this type:
//  in a classroom a listed stream is ALLOWED, everywhere else a listed stream is
//  BLOCKED. Callers only ever ask "allowed or not?"; the inversion lives here.
//

import Foundation

/// One line of the "Transmit Control" menu, in the Qt client's order.
nonisolated enum TransmitStream: Int, CaseIterable {
    case channelMessages
    case voice
    case video
    case desktop
    case mediaFile

    /// The `StreamType` bits this line stands for. A media file is audio and
    /// video together, as in the Qt client.
    var streamTypeMask: UInt32 {
        switch self {
        case .channelMessages: return UInt32(STREAMTYPE_CHANNELMSG.rawValue)
        case .voice: return UInt32(STREAMTYPE_VOICE.rawValue)
        case .video: return UInt32(STREAMTYPE_VIDEOCAPTURE.rawValue)
        case .desktop: return UInt32(STREAMTYPE_DESKTOP.rawValue)
        case .mediaFile: return UInt32(STREAMTYPE_MEDIAFILE.rawValue)
        }
    }
}

nonisolated struct TransmitUsersList: Equatable {
    struct Entry: Equatable {
        let userID: Int32
        var streamTypes: UInt32
    }

    /// The pseudo user ID standing for "everyone in the channel". The server only
    /// reads it in a classroom.
    static let everyoneUserID = Int32(TT_TRANSMITUSERS_FREEFORALL)

    /// Slots in the C array; the server refuses nothing beyond, the SDK simply
    /// has nowhere to put it.
    static let capacity = Int(TT_TRANSMITUSERS_MAX)

    let isClassroom: Bool
    private(set) var entries: [Entry]

    init(isClassroom: Bool, entries: [Entry] = []) {
        self.isClassroom = isClassroom
        self.entries = entries
    }

    /// Whether the server lets `userID` send `stream` in this channel, judged on
    /// that user's own entry — not on "everyone", which is a separate line of
    /// the menu, as in the Qt client.
    func isAllowed(_ stream: TransmitStream, userID: Int32) -> Bool {
        let listed = entries.first { $0.userID == userID }
            .map { ($0.streamTypes & stream.streamTypeMask) != 0 } ?? false
        return isClassroom ? listed : !listed
    }

    /// Whether "everyone" may send `stream`. Only meaningful in a classroom.
    func isAllowedForEveryone(_ stream: TransmitStream) -> Bool {
        isClassroom && isAllowed(stream, userID: Self.everyoneUserID)
    }

    /// The list with `stream` allowed or forbidden for `userID`, or nil when that
    /// needs a new entry and every slot is taken.
    ///
    /// Only the bits of `stream` are touched: anything else an entry carries —
    /// including bits another client wrote for streams this menu doesn't show —
    /// stays as it was. An entry left with no bits is dropped, freeing its slot.
    func setting(_ stream: TransmitStream, allowed: Bool, userID: Int32) -> TransmitUsersList? {
        let listed = isClassroom ? allowed : !allowed
        var copy = self
        if let index = copy.entries.firstIndex(where: { $0.userID == userID }) {
            if listed {
                copy.entries[index].streamTypes |= stream.streamTypeMask
            } else {
                copy.entries[index].streamTypes &= ~stream.streamTypeMask
                if copy.entries[index].streamTypes == 0 {
                    copy.entries.remove(at: index)
                }
            }
            return copy
        }
        guard listed else { return copy }
        guard copy.entries.count < Self.capacity else { return nil }
        copy.entries.append(Entry(userID: userID, streamTypes: stream.streamTypeMask))
        return copy
    }
}

nonisolated extension TransmitUsersList {
    /// Reads `channel.transmitUsers`, a C `INT32[128][2]` imported as a nested
    /// tuple and terminated by a zero user ID.
    init(channel: inout Channel) {
        let isClassroom = (channel.uChannelType & UInt32(CHANNEL_CLASSROOM.rawValue)) != 0
        let entries: [Entry] = withUnsafeBytes(of: &channel.transmitUsers) { raw in
            let values = raw.bindMemory(to: Int32.self)
            var result: [Entry] = []
            for slot in stride(from: 0, to: values.count - 1, by: 2) {
                let userID = values[slot + Int(TT_TRANSMITUSERS_USERID_INDEX)]
                guard userID != 0 else { break }
                let streamTypes = UInt32(bitPattern: values[slot + Int(TT_TRANSMITUSERS_STREAMTYPE_INDEX)])
                result.append(Entry(userID: userID, streamTypes: streamTypes))
            }
            return result
        }
        self.init(isClassroom: isClassroom, entries: entries)
    }

    /// Writes the list back into `channel.transmitUsers`, zero-terminated when
    /// it leaves free slots.
    func write(into channel: inout Channel) {
        withUnsafeMutableBytes(of: &channel.transmitUsers) { raw in
            let values = raw.bindMemory(to: Int32.self)
            for slot in 0 ..< values.count {
                values[slot] = 0
            }
            for (index, entry) in entries.prefix(Self.capacity).enumerated() {
                values[index * 2 + Int(TT_TRANSMITUSERS_USERID_INDEX)] = entry.userID
                values[index * 2 + Int(TT_TRANSMITUSERS_STREAMTYPE_INDEX)] = Int32(bitPattern: entry.streamTypes)
            }
        }
    }
}
