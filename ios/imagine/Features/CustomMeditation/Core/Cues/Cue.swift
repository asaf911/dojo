//
//  Cue.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import Foundation

struct Cue: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    let urlsByVoice: [String: String]?

    init(id: String, name: String, url: String, urlsByVoice: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.urlsByVoice = urlsByVoice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        urlsByVoice = try container.decodeIfPresent([String: String].self, forKey: .urlsByVoice)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(urlsByVoice, forKey: .urlsByVoice)
    }

    func url(forVoice voiceId: String) -> String {
        urlsByVoice?[voiceId] ?? url
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, urlsByVoice
    }
}
