//
//  StreamSourceCatalog.swift
//  ttaccessible
//
//  What the "Stream Audio from This Mac" list offers, and how its search narrows it: all
//  audio from this Mac on a line of its own, then three groups — Recently used, Devices,
//  Applications (VoiceOver first). Pure data, so the filtering and the recent-sources
//  bookkeeping are tested without the sheet.
//

import Foundation

struct StreamSourceCatalog: Equatable {
    enum Group: Equatable, CaseIterable {
        case recent, devices, applications
    }

    struct Section: Equatable {
        let group: Group
        let sources: [DeviceStreamCaptureSpec]
    }

    /// How many recently streamed sources are remembered — a usual rotation, without the
    /// group growing into a second copy of the other two.
    static let recentLimit = 5

    var systemAudio: DeviceStreamCaptureSpec?
    var recent: [DeviceStreamCaptureSpec]
    var devices: [DeviceStreamCaptureSpec]
    var applications: [DeviceStreamCaptureSpec]

    /// What is left once `query` is applied: all system audio when its name matches, and
    /// each group narrowed to its matches, a group with none left out. An empty query keeps
    /// everything; a group that is empty to begin with is left out either way.
    func filtered(by query: String) -> (systemAudio: DeviceStreamCaptureSpec?, sections: [Section]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func keep(_ spec: DeviceStreamCaptureSpec) -> Bool {
            trimmed.isEmpty || Self.name(spec.displayName, matches: trimmed)
        }
        let groups: [(Group, [DeviceStreamCaptureSpec])] = [
            (.recent, recent), (.devices, devices), (.applications, applications),
        ]
        let sections = groups.compactMap { group, sources -> Section? in
            let kept = sources.filter(keep)
            return kept.isEmpty ? nil : Section(group: group, sources: kept)
        }
        return (systemAudio.flatMap { keep($0) ? $0 : nil }, sections)
    }

    /// Case- and accent-insensitive, anywhere in the name: "music" finds Music, "cafe" Café.
    static func name(_ name: String, matches query: String) -> Bool {
        name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The recent sources, newest first, resolved against what is on offer right now. A token
    /// nothing on offer answers to is asked of `resolveMissing` — an application that isn't
    /// running can still be waited for — and anything still unknown, an unplugged device say,
    /// is left out rather than shown as a line that cannot stream.
    static func resolveRecent(tokens: [String],
                              available: [DeviceStreamCaptureSpec],
                              resolveMissing: (String) -> DeviceStreamCaptureSpec?) -> [DeviceStreamCaptureSpec] {
        var result: [DeviceStreamCaptureSpec] = []
        for token in tokens {
            guard let spec = available.first(where: { $0.persistenceToken == token }) ?? resolveMissing(token),
                  result.contains(spec) == false else { continue }
            result.append(spec)
            if result.count == recentLimit { break }
        }
        return result
    }

    /// The recent-source tokens after streaming `token`: what it was made of first (every
    /// application of a cumulated stream, one line each), then the older ones, without
    /// repeats, at most `recentLimit`.
    static func recentTokens(_ old: [String], afterStreaming token: String) -> [String] {
        var result: [String] = []
        for candidate in DeviceStreamCaptureSpec.componentTokens(of: token) + old
        where result.contains(candidate) == false {
            result.append(candidate)
        }
        return Array(result.prefix(recentLimit))
    }

    /// The groups to open so every checked source is on a line the user can reach: a checked
    /// source tucked inside a closed group would stream without anyone knowing it was chosen.
    /// A source already shown by an open Recently used, or on the all-audio line, needs none.
    func groupsRevealing(_ checked: [DeviceStreamCaptureSpec], open: Set<Group>) -> Set<Group> {
        var groups = open
        for spec in checked where spec != systemAudio {
            if groups.contains(.recent), recent.contains(spec) { continue }
            if devices.contains(spec) {
                groups.insert(.devices)
            } else if applications.contains(spec) {
                groups.insert(.applications)
            } else if recent.contains(spec) {
                groups.insert(.recent)
            }
        }
        return groups
    }
}
