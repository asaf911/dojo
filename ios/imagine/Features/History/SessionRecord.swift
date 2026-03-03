//
//  SessionRecord.swift
//  Dojo
//
//  Created for History feature MVP
//

import Foundation

/// Represents a completed meditation session (either Practice or Custom)
struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let sessionType: SessionType
    let title: String
    let description: String?
    let practiceId: String?
    let durationSeconds: Int
    let completedAt: Date
    
    // Heart rate data (optional)
    let startBPM: Int?
    let endBPM: Int?
    
    enum SessionType: String, Codable {
        case practice
        case custom
    }
    
    var hasHeartRateData: Bool {
        startBPM != nil && endBPM != nil && startBPM! > 0 && endBPM! > 0
    }
    
    init(
        id: UUID = UUID(),
        sessionType: SessionType,
        title: String,
        description: String? = nil,
        practiceId: String? = nil,
        durationSeconds: Int,
        completedAt: Date = Date(),
        startBPM: Int? = nil,
        endBPM: Int? = nil
    ) {
        self.id = id
        self.sessionType = sessionType
        self.title = title
        self.description = description
        self.practiceId = practiceId
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
        self.startBPM = startBPM
        self.endBPM = endBPM
    }
}

