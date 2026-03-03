//
//  BackgroundSound.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-27
//

import Foundation

struct BackgroundSound: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
}
