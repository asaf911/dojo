import Foundation

struct PathStepsResponse: Codable {
    let version: Int
    let steps: [PathStep]
}

struct PathStep: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let audioUrl: String
    let duration: Int
    let imageUrl: String
    let order: Int
    let premium: Bool
    let isLesson: Bool
}

extension PathStep {
    func toAudioFile() -> AudioFile {
        AudioFile(
            id: id,
            title: title,
            category: .learn,
            description: description,
            imageFile: convertToHttpsUrl(imageUrl),
            durations: [Duration(length: duration, fileName: audioUrl)],
            premium: premium,
            tags: ["path", isLesson ? "lesson" : "practice"]
        )
    }
    
    private func convertToHttpsUrl(_ gsUrl: String) -> String {
        // Convert gs:// URL to https:// URL for Firebase Storage
        // Format: gs://bucket-name/path/to/file.jpg
        // Becomes: https://firebasestorage.googleapis.com/v0/b/bucket-name/o/path%2Fto%2Ffile.jpg?alt=media
        
        let gsPrefix = "gs://"
        guard gsUrl.hasPrefix(gsPrefix) else { return gsUrl }
        
        let withoutPrefix = gsUrl.dropFirst(gsPrefix.count)
        let components = withoutPrefix.split(separator: "/", maxSplits: 1)
        
        guard components.count == 2 else { return gsUrl }
        
        let bucket = String(components[0])
        
        // Create a properly encoded path by handling each path component separately
        let pathString = String(components[1])
        let pathComponents = pathString.split(separator: "/")
        
        // Encode each path component individually
        let encodedPathComponents = pathComponents.map { component -> String in
            let str = String(component)
            return str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str
        }
        
        // Join the encoded components with %2F (URL-encoded forward slash)
        let encodedPath = encodedPathComponents.joined(separator: "%2F")
        
        return "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encodedPath)?alt=media"
    }
}
