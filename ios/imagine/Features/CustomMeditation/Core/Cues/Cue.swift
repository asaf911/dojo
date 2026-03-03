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
}
