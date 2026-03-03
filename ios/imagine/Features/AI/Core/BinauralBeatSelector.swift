import Foundation

enum BinauralBeatSelector {
    private static let lastKey = "imagine.lastBinauralBeatId"

    struct Context {
        let prompt: String
        let userEdit: String?
        let historyTail: String?
    }

    static func select(available beats: [BinauralBeat], context: Context) -> BinauralBeat {
        let text = effectiveText(context).lowercased()
        print("AI_[BB] SELECTOR start. text='\(String(text.prefix(160)))...' beats=\(beats.count)")

        if containsAny(text, ["no binaural", "no beats", "no bb", "no background", "silence only"]) {
            print("AI_[BB] SELECTOR suppress due to 'no binaural' intent")
            return noneBeat()
        }

        if let explicit = mapExplicitFrequencyOrWave(text, beats: beats) {
            persist(explicit.id)
            print("AI_[BB] SELECTOR explicit \(explicit.id) \(explicit.name)")
            return explicit
        }

        let scored = beats.map { beat -> (BinauralBeat, Int) in
            let hay = (beat.name + " " + (beat.description ?? "")).lowercased()
            let score = scoreFor(text: text, hay: hay)
            return (beat, score)
        }.sorted { $0.1 > $1.1 }

        let threshold = 2
        if let (best, bestScore) = scored.first, bestScore >= threshold, best.id != "None" {
            let last = UserDefaults.standard.string(forKey: lastKey)
            if let last = last, best.id == last {
                let epsilon = 1
                if let alt = scored.dropFirst().first(where: { $0.0.id != "None" && ($0.1 >= bestScore - epsilon) && $0.0.id != last })?.0 {
                    persist(alt.id)
                    print("AI_[BB] SELECTOR avoiding last '\(last)'; picked alt \(alt.id) \(alt.name)")
                    return alt
                }
            }
            persist(best.id)
            print("AI_[BB] SELECTOR picked \(best.id) \(best.name) score=\(bestScore)")
            return best
        }

        // No strong match - choose a sensible default based on intent keywords; avoid repeating last
        let preferredOrder: [String] = {
            // Sleep
            if containsAny(text, ["sleep", "bed", "bedtime", "insomnia", "night"]) { return ["BB2","BB10","BB4","BB6","BB14","BB40"] }
            // Gratitude/compassion/heart
            if containsAny(text, ["gratitude", "heart", "compassion", "loving", "kindness"]) { return ["BB40","BB10","BB4","BB6","BB14","BB2"] }
            // Focus/productivity
            if containsAny(text, ["focus", "concentr", "productiv", "work", "study", "clarity", "alert"]) { return ["BB14","BB10","BB6","BB4","BB40","BB2"] }
            // Imagination/visualization
            if containsAny(text, ["visualiz", "imagin", "creative", "creativity", "visioning"]) { return ["BB4","BB6","BB10","BB40","BB14","BB2"] }
            // Future/transform/intention
            if containsAny(text, ["future", "intention", "transform", "transformation", "manifest"]) { return ["BB6","BB10","BB4","BB14","BB40","BB2"] }
            // Relaxation/stress default
            if containsAny(text, ["relax", "calm", "stress", "anxiety", "soothe", "unwind", "peace"]) { return ["BB10","BB4","BB6","BB14","BB40","BB2"] }
            // Hard default when no intent found
            return ["BB10","BB14","BB4","BB6","BB40","BB2"]
        }()
        let last = UserDefaults.standard.string(forKey: lastKey)
        if let pickId = preferredOrder.first(where: { id in id != last && beats.contains(where: { $0.id == id }) }) ?? preferredOrder.first(where: { id in beats.contains(where: { $0.id == id }) }),
           let pick = beats.first(where: { $0.id == pickId }) {
            persist(pick.id)
            print("AI_[BB] SELECTOR fallback picked \(pick.id) \(pick.name)")
            return pick
        }

        // As a final fallback, return the first non-None beat
        if let any = beats.first(where: { $0.id != "None" }) {
            persist(any.id)
            print("AI_[BB] SELECTOR fallback-any picked \(any.id) \(any.name)")
            return any
        }
        print("AI_[BB] SELECTOR no relevant match; returning None")
        return noneBeat()
    }

    private static func effectiveText(_ ctx: Context) -> String {
        if let ue = ctx.userEdit, !ue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ue }
        if let tail = ctx.historyTail, !tail.isEmpty { return tail }
        return ctx.prompt
    }

    private static func containsAny(_ s: String, _ needles: [String]) -> Bool {
        needles.contains { s.contains($0) }
    }

    private static func mapExplicitFrequencyOrWave(_ s: String, beats: [BinauralBeat]) -> BinauralBeat? {
        let freqMap: [(String, String)] = [
            ("\\b2\\s*hz\\b", "BB2"), ("\\b4\\s*hz\\b", "BB4"),
            ("\\b6\\s*hz\\b", "BB6"), ("\\b10\\s*hz\\b", "BB10"),
            ("\\b14\\s*hz\\b", "BB14"), ("\\b40\\s*hz\\b", "BB40")
        ]
        for (pat, id) in freqMap {
            if regexContains(s, pat), let b = beats.first(where: { $0.id.lowercased() == id.lowercased() }) { return b }
        }
        let waveMap: [(String, String)] = [
            ("delta", "BB2"), ("theta", "BB4"), ("alpha", "BB10"), ("beta", "BB14"), ("gamma", "BB40")
        ]
        for (key, id) in waveMap {
            if s.contains(key), let b = beats.first(where: { $0.id.lowercased() == id.lowercased() }) { return b }
        }
        return nil
    }

    private static func regexContains(_ s: String, _ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
            .firstMatch(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count)) != nil
    }

    private static func scoreFor(text: String, hay: String) -> Int {
        var score = 0
        if containsAny(text, ["sleep", "bed", "bedtime", "dream", "insomnia", "night", "rest", "recover"]) {
            if containsAny(hay, ["sleep", "delta", "2 hz", "2hz", "rest", "recovery", "night"]) { score += 3 }
        }
        if containsAny(text, ["visualiz", "imagin", "creative", "creativity", "inspiration", "visioning"]) {
            if containsAny(hay, ["theta", "4 hz", "4hz", "imagination", "visualization", "creativity"]) { score += 3 }
        }
        if containsAny(text, ["future", "intention", "transform", "transformation", "manifest"]) {
            if containsAny(hay, ["theta", "6 hz", "6hz", "intention", "transformation"]) { score += 3 }
        }
        if containsAny(text, ["relax", "calm", "stress", "anxiety", "soothe", "unwind", "peace"]) {
            if containsAny(hay, ["alpha", "10 hz", "10hz", "relaxation", "calm", "stress"]) { score += 3 }
        }
        if containsAny(text, ["focus", "concentr", "productiv", "work", "study", "morning", "wake", "plan", "clarity", "alert"]) {
            if containsAny(hay, ["beta", "14 hz", "14hz", "focus", "concentration", "alert"]) { score += 3 }
        }
        if containsAny(text, ["gratitude", "heart", "compassion", "loving", "kindness", "love"]) {
            if containsAny(hay, ["gamma", "40 hz", "40hz", "gratitude", "compassion", "heart"]) { score += 3 }
        }
        return score
    }

    private static func noneBeat() -> BinauralBeat {
        BinauralBeat(id: "None", name: "None", url: "", description: nil)
    }

    private static func persist(_ id: String) {
        UserDefaults.standard.setValue(id, forKey: lastKey)
    }
}


