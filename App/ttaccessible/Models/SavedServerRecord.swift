//
//  SavedServerRecord.swift
//  ttaccessible
//
//  Created by Mathieu Martin on 17/03/2026.
//

import Foundation

struct SavedServerRecord: Codable, Identifiable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case tcpPort
        case udpPort
        case encrypted
        case nickname
        case username
        case initialChannelPath
        case initialChannelPassword
    }

    let id: UUID
    var name: String
    var host: String
    var tcpPort: Int
    var udpPort: Int
    var encrypted: Bool
    var nickname: String
    var username: String
    var initialChannelPath: String
    var initialChannelPassword: String

    init(
        id: UUID,
        name: String,
        host: String,
        tcpPort: Int,
        udpPort: Int,
        encrypted: Bool,
        nickname: String,
        username: String,
        initialChannelPath: String = "",
        initialChannelPassword: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.encrypted = encrypted
        self.nickname = nickname
        self.username = username
        self.initialChannelPath = initialChannelPath
        self.initialChannelPassword = initialChannelPassword
    }

    func generateLink(password: String? = nil, channelPath: String? = nil, channelPassword: String? = nil) -> String {
        var url = "tt://\(host)?tcpport=\(tcpPort)&udpport=\(udpPort)&encrypted=\(encrypted)"
        if !username.isEmpty {
            url += "&username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)"
        }
        if let pass = password, !pass.isEmpty {
            url += "&password=\(pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass)"
        }
        if let channel = channelPath, !channel.isEmpty {
            url += "&channel=\(channel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channel)"
        }
        if let chanPass = channelPassword, !chanPass.isEmpty {
            url += "&chanpasswd=\(chanPass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? chanPass)"
        }
        return url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        tcpPort = try container.decode(Int.self, forKey: .tcpPort)
        udpPort = try container.decode(Int.self, forKey: .udpPort)
        encrypted = try container.decode(Bool.self, forKey: .encrypted)
        nickname = try container.decode(String.self, forKey: .nickname)
        username = try container.decode(String.self, forKey: .username)
        initialChannelPath = try container.decodeIfPresent(String.self, forKey: .initialChannelPath) ?? ""
        initialChannelPassword = try container.decodeIfPresent(String.self, forKey: .initialChannelPassword) ?? ""
    }
}
