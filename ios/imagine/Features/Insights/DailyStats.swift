// DailyStat.swift

import Foundation
import FirebaseFirestore

struct DailyStat: Identifiable {
    var id: String // Document ID (date string)
    var date: Date
    var totalDuration: Double

    // New initializer
    init(id: String, date: Date, totalDuration: Double) {
        self.id = id
        self.date = date
        self.totalDuration = totalDuration
    }

    init?(dictionary: [String: Any], id: String) {
        guard let timestamp = dictionary["date"] as? Timestamp,
              let totalDuration = dictionary["totalDuration"] as? Double else { return nil }
        self.id = id
        self.date = timestamp.dateValue()
        self.totalDuration = totalDuration
    }
}
