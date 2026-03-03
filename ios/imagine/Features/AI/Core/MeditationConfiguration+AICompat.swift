import Foundation

extension MeditationConfiguration {
    /// Safe access to binaural beat name for targets where the stored property may not be visible.
    /// Falls back to "None" when unavailable.
    var ai_bbName: String {
        let mirror = Mirror(reflecting: self)
        if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
            let beatMirror = Mirror(reflecting: beatChild.value)
            if let name = beatMirror.children.first(where: { $0.label == "name" })?.value as? String {
                return name
            }
        }
        return "None"
    }

    /// Safe access to binaural beat id; returns "None" if unavailable.
    var ai_binauralId: String {
        let mirror = Mirror(reflecting: self)
        if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
            let beatMirror = Mirror(reflecting: beatChild.value)
            if let id = beatMirror.children.first(where: { $0.label == "id" })?.value as? String {
                return id
            }
        }
        return "None"
    }

    /// Safe access to binaural beat url; returns empty string if unavailable.
    var ai_bbURL: String {
        let mirror = Mirror(reflecting: self)
        if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
            let beatMirror = Mirror(reflecting: beatChild.value)
            if let url = beatMirror.children.first(where: { $0.label == "url" })?.value as? String {
                return url
            }
        }
        return ""
    }
}


