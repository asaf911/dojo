import Foundation

// Duration struct
struct Duration: Identifiable, Codable, Hashable {
    var id: UUID = UUID() // Provide a default UUID
    var length: Int
    var fileName: String

    // Define CodingKeys excluding 'id' if it's not in the JSON
    enum CodingKeys: String, CodingKey {
        case length
        case fileName
    }
}

// AudioFile struct
struct AudioFile: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var category: AudioCategory
    var description: String
    var imageFile: String?
    var durations: [Duration]
    var premium: Bool
    var tags: [String]  // Add this line to include tags

    enum CodingKeys: String, CodingKey {
        case id, title, category, description, imageFile, durations, premium, tags
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func ==(lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.id == rhs.id
    }
}
