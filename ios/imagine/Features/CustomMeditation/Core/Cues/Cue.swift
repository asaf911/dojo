//
//  Cue.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import Foundation

/// Optional breath SFX (or second layer) played in parallel with the primary cue at the same session time.
struct ParallelSfxCue: Codable, Equatable, Hashable {
    let id: String
    let name: String
    let url: String
}

struct Cue: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    let urlsByVoice: [String: String]?
    let parallelSfx: ParallelSfxCue?

    init(
        id: String,
        name: String,
        url: String,
        urlsByVoice: [String: String]? = nil,
        parallelSfx: ParallelSfxCue? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.urlsByVoice = urlsByVoice
        self.parallelSfx = parallelSfx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        urlsByVoice = try container.decodeIfPresent([String: String].self, forKey: .urlsByVoice)
        parallelSfx = try container.decodeIfPresent(ParallelSfxCue.self, forKey: .parallelSfx)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(urlsByVoice, forKey: .urlsByVoice)
        try container.encodeIfPresent(parallelSfx, forKey: .parallelSfx)
    }

    func url(forVoice voiceId: String) -> String {
        urlsByVoice?[voiceId] ?? url
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, urlsByVoice, parallelSfx
    }
}
