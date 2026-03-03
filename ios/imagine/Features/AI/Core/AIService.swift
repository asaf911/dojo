import Foundation
import FirebaseFunctions

// MARK: - OpenAI Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int
    let temperature: Double
    
    struct OpenAIMessage: Codable {
        let role: String
        let content: String
    }
}

struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
}

// MARK: - Service Response Types

enum AIMeditationResult {
    case meditation(AITimerResponse)
    case conversationalResponse(String)
}

struct AITimerResponse: Equatable, Codable {
    let meditationConfiguration: MeditationConfiguration
    let deepLink: URL
    let description: String
    
    static func == (lhs: AITimerResponse, rhs: AITimerResponse) -> Bool {
        lhs.meditationConfiguration.id == rhs.meditationConfiguration.id &&
        lhs.deepLink.absoluteString == rhs.deepLink.absoluteString &&
        lhs.description == rhs.description
    }
}

struct AIGeneratedTimer: Codable {
    var duration: Int
    var backgroundSoundId: String
    var binauralBeatId: String?
    var cues: [AICue]
    var segments: [AISegment]?
    let title: String
    var description: String?
    
    struct AICue: Codable {
        var id: String
        var trigger: String // "start", "end", or minute number as string
    }

    struct AISegment: Codable {
        var type: String
        var id: String
        var length: Int?
        var cueAudio: Int?
        var quietSpan: Int?
    }
}

// MARK: - Simplified AI Meditation Service

class SimplifiedAIService {
    
    // MARK: - Meditation Generation (Prescriptive Approach)
    
    func generateMeditation(prompt: String, conversationHistory: [ChatMessage] = [], maxDuration: Int? = nil) async throws -> AIMeditationResult {
        logger.aiChat("🧠 AI_DEBUG GEN start prompt_len=\(prompt.count) history=\(conversationHistory.count) maxDuration=\(maxDuration?.description ?? "nil")")
        
        // Load catalogs
        await loadLatestResources()
        
        // Build system prompt from guidelines
        let systemPrompt = buildSystemPrompt()
        logger.aiChat("🧠 AI_DEBUG PROMPT system_len=\(systemPrompt.count)")
        
        // Inject duration constraint if provided
        var effectivePrompt = prompt
        if let maxDur = maxDuration {
            effectivePrompt = "DURATION CONSTRAINT: This meditation MUST be exactly \(maxDur) minutes.\n\n\(prompt)"
            logger.aiChat("🧠 AI_DEBUG GEN duration_constraint=\(maxDur)")
        }
        
        // Call OpenAI
        let aiResponse = try await callOpenAI(
            userPrompt: effectivePrompt,
            systemPrompt: systemPrompt, 
            conversationHistory: conversationHistory
        )
        logger.aiChat("🧠 AI_DEBUG GEN response_len=\(aiResponse.count)")
        
        // Parse response
        var meditation: AIGeneratedTimer
        do {
            meditation = try parseAIResponse(aiResponse)
            logger.aiChat("🧠 AI_DEBUG PARSE success dur=\(meditation.duration) cues=\(meditation.cues.map { "\($0.id)@\($0.trigger)" }.joined(separator: ","))")
        } catch {
            logger.aiChat("🧠 AI_DEBUG PARSE failed error=\(error.localizedDescription) - using fallback")
            meditation = Self.buildFallback(duration: maxDuration ?? 10, prompt: prompt)
        }
        
        // Validate
        if let validationError = validate(meditation, prompt: prompt) {
            logger.aiChat("🧠 AI_DEBUG VALIDATE failed reason=\(validationError) - using fallback")
            meditation = Self.buildFallback(duration: meditation.duration, prompt: prompt)
        } else {
            logger.aiChat("🧠 AI_DEBUG VALIDATE passed")
        }
        
        // Apply seconds policy if needed
        applySecondsDurationPolicyIfNeeded(prompt: prompt, meditation: &meditation)
        
        // Convert to result
        let result = try convertToTimerResponse(meditation)
        logger.aiChat("🧠 AI_DEBUG GEN complete dur=\(result.meditationConfiguration.duration) bg=\(result.meditationConfiguration.backgroundSound.id)")
        
        return .meditation(result)
    }
    
    // MARK: - System Prompt (Built from CueManager + Guidelines)
    
    private func buildSystemPrompt() -> String {
        // Load guidelines for rules only (not module definitions)
        let guidelines = CompositionGuidelinesLoader.shared.loadGuidelines()
        
        // Build module durations from CueManager (single source of truth)
        var finiteModules: [String] = []
        
        // Get durations from CueManager (loaded from Firebase)
        let durations = CatalogsManager.shared.bodyScanDurations
        let triggerCueIds = guidelines?.moduleTypeClassifications.triggerCue.modules ?? ["OH", "VC", "RT"]
        
        // SI is always 1 min
        finiteModules.append("- SI: 1 min (settling in)")
        
        // Build finite exercise list from CueManager
        let sortedDurations = durations.sorted { $0.key < $1.key }
        for (id, dur) in sortedDurations {
            if triggerCueIds.contains(id) { continue }
            if id == "SI" || id == "GB" { continue }
            finiteModules.append("- \(id): \(dur) min")
        }
        
        // Get trigger cue durations dynamically from CueManager
        let triggerDuration = triggerCueIds.compactMap { durations[$0] }.first ?? 1
        let triggerCueList = triggerCueIds.joined(separator: ", ")
        
        // Get available sounds from BackgroundSoundManager (single source of truth)
        let sounds = CatalogsManager.shared.sounds
        let soundsList = sounds.isEmpty 
            ? "LI, SP, OC, DH, BD" 
            : sounds.filter { $0.id != "None" }.map { $0.id }.joined(separator: ", ")
        
        // Get available binaural beats from BinauralBeatManager (single source of truth)
        let beats = CatalogsManager.shared.beats
        let beatsList = beats.isEmpty
            ? "BB2, BB4, BB6, BB10, BB14, BB40"
            : beats.map { $0.id }.joined(separator: ", ")
        
        // Build session templates from guidelines
        var templatesSection = ""
        if let templates = guidelines?.sessionTemplates.templates {
            let sortedTemplates = templates.sorted { first, second in
                let firstNum = Int(first.key.dropLast(3)) ?? 0
                let secondNum = Int(second.key.dropLast(3)) ?? 0
                return firstNum < secondNum
            }
            for (key, template) in sortedTemplates {
                let cueStrings = template.cues.map { "\($0.id)@\($0.trigger)" }.joined(separator: ", ")
                templatesSection += "  \(key): \(cueStrings)\n"
            }
        }
        
        logger.aiChat("🧠 AI_DEBUG PROMPT built from CueManager: \(finiteModules.count) finite, \(triggerCueIds.count) trigger, \(sounds.count) sounds, \(beats.count) beats")
        
        return """
        You are a meditation composer. Use the appropriate structure based on duration:

        ## SHORT SESSIONS (1-6 min)

        1 min: SI only + GB
        - Cues: SI@start, GB@end
        
        2-3 min: SI + ONE relaxation (PB or BS) + GB
        - 2m: SI@start, PB1@1 or BS1@1, GB@end
        - 3m: SI@start, PB2@1 or BS2@1, GB@end
        
        4 min: SI + PB + BS + GB (no focus module)
        - SI@start, PB1@1, BS2@2, GB@end  OR  SI@start, PB2@1, BS1@3, GB@end
        
        5-6 min: SI + PB + BS + focus (IM2 or NF2) + GB
        - 5m: SI@start, PB1@1, BS1@2, IM2@3, GB@end  OR  NF2@3
        - 6m: SI@start, PB1@1, BS2@2, IM2@4, GB@end  OR  NF2@4
        - Focus module: IM2 or NF2 (random default), or VC/RT as viz trigger for specific session types

        ## PRIORITY EXERCISE (CRITICAL - check first!)
        
        If user explicitly requests a specific exercise, give it 50% of TOTAL session.
        
        FINITE EXERCISE PRIORITY (BS, PB, IM, NF):
        - "body scan"/"bodyscan" → BS gets 50% of total duration (e.g., 15m → BS7)
        - "breath"/"breathing" → PB gets 50% of total duration (capped at PB5)
        - "mantra"/"i am" → IM gets 50% of total duration (capped at IM10)
        - "nostril"/"nostril focus" → NF gets 50% of total duration (capped at NF10)
        - Other modules get minimum (1m)
        
        Example 15m "body scan": SI@start, PB1@1, BS7@2, NF2@9, VC@11, GB@end
        
        TRIGGER CUE PRIORITY (VC, RT):
        - "visualization"/"vision" → VC gets ~50% as quiet practice time
        - "retrospection"/"reflection" → RT gets ~50% as quiet practice time
        
        Example 15m "mantra": SI@start, PB1@1, BS1@2, IM7@3, VC@10, GB@end
        Example 15m "nostril focus": SI@start, PB1@1, BS1@2, NF7@3, VC@10, GB@end

        ## LONG SESSIONS (> 6 min) - 4-PHASE STRUCTURE
        
        PHASE 1 - SETTLE IN (0-10%): SI at minute 0
        PHASE 2 - RELAXATION (10-50%): PB + BS (adjust if priority detected)
        PHASE 3 - FOCUS (50-75%): IM or NF (finite guided focus, 1-10m)
        PHASE 4 - VISUALIZATION (75-100%): VC or RT ONLY (NOT OH)
        CLOSING: GB at "end"

        ## VISUALIZATION PHASE - use ONLY:
        - EVENING sessions: RT (Retrospection)
        - ALL OTHER sessions: VC (Vision Clarity)
        
        OH is NOT a visualization cue. NEVER repeat same trigger cue. GB skipped ONLY for sleep.

        ## AVAILABLE MODULES

        FINITE: SI=1m, PB1-5=1-5m, BS1-10=1-10m, IM2-10=2-10m (I AM Mantra), NF1-10=1-10m (Nostril Focus)
        TRIGGER (\(triggerDuration)m audio): \(triggerCueList)
        INSTANT: GB (always at end, except sleep)

        ## TEMPLATES
        \(templatesSection)
        ## SOUNDS: \(soundsList) (REQUIRED)
        ## BEATS: \(beatsList) (REQUIRED - BB10=relaxation, BB14=focus, BB2=sleep, BB6=morning)

        ## STRICT RULES
        - Fill 100% of session time
        - GB at end for ALL sessions EXCEPT sleep
        - NEVER repeat a trigger cue
        - ALWAYS include backgroundSoundId and binauralBeatId
        - Return ONLY valid JSON

        ## JSON FORMAT
        
        TRIGGER VALUES: "start", "end", or minute number STRING ("1", "3", "7")
        
        FIELD GUIDELINES:
        - title: Short contextual meditation name (2-4 words) reflecting the user's intent
        - description: Natural, conversational summary of the meditation elements. Do NOT include duration or timing. Describe what the practice contains using friendly terms like "breathwork", "body awareness", "I AM mantra", "nostril focus", "visualization", "reflection". End with the background sound. Keep it one flowing sentence.

        Examples:
        3min: {"duration":3,"backgroundSoundId":"SP","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB2","trigger":"1"},{"id":"GB","trigger":"end"}],"title":"Breath Reset","description":"Gentle breathwork to help you find calm, with spa ambience."}
        
        5min: {"duration":5,"backgroundSoundId":"SP","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB1","trigger":"1"},{"id":"BS1","trigger":"2"},{"id":"IM2","trigger":"3"},{"id":"GB","trigger":"end"}],"title":"Quick Focus","description":"Light breathwork, body awareness, and I AM mantra with spa background."}
        
        7min pre-meeting: {"duration":7,"backgroundSoundId":"LI","binauralBeatId":"BB14","cues":[{"id":"SI","trigger":"start"},{"id":"PB2","trigger":"1"},{"id":"BS2","trigger":"3"},{"id":"NF2","trigger":"5"},{"id":"GB","trigger":"end"}],"title":"Pre-Meeting Calm","description":"Breathwork and body scan to ground you, followed by nostril focus, with light rain background."}
        
        15min evening: {"duration":15,"backgroundSoundId":"SP","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB3","trigger":"1"},{"id":"BS4","trigger":"4"},{"id":"IM4","trigger":"7"},{"id":"RT","trigger":"11"},{"id":"GB","trigger":"end"}],"title":"Evening Unwind","description":"Deep breathing, extended body scan, I AM mantra, and gratitude reflection with spa soundscape."}
        
        10min relaxation: {"duration":10,"backgroundSoundId":"OC","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB2","trigger":"1"},{"id":"BS2","trigger":"3"},{"id":"NF3","trigger":"5"},{"id":"VC","trigger":"8"},{"id":"GB","trigger":"end"}],"title":"Calm Focus","description":"Breathwork, body awareness, nostril focus, and visualization with ocean background."}
        """
    }
    
    /// Fallback system prompt if guidelines fail to load
    private func buildFallbackSystemPrompt() -> String {
        let sounds = CatalogsManager.shared.sounds
        let soundsList = sounds.isEmpty ? "LI, SP, OC" : sounds.filter { $0.id != "None" }.map { $0.id }.joined(separator: ", ")
        
        let beats = CatalogsManager.shared.beats
        let beatsList = beats.isEmpty ? "BB10" : beats.map { $0.id }.joined(separator: ", ")
        
        // Get trigger cue duration dynamically from CueManager
        let durations = CatalogsManager.shared.bodyScanDurations
        let triggerDuration = durations["VC"] ?? durations["RT"] ?? 1
        
        return """
        You are a meditation composer.

        SHORT (1-6 min):
        1m: SI + GB
        2-3m: SI + PB or BS + GB
        4m: SI + PB + BS + GB
        5-6m: SI + PB + BS + focus (IM2 or NF2) + GB

        LONG (>6 min) - 4-PHASE:
        SI@start, PB@1, BS@(after PB), focus@50% (IM or NF, finite), VizCue@75%, GB@end
        VizCue: morning=VC, evening=RT, default=VC

        GB at end for ALL sessions EXCEPT sleep.
        NEVER repeat trigger cues. TRIGGERS: "start", "end", or minute STRING.

        MODULES: SI=1m, PB1-5, BS1-10, IM2-10 (I AM mantra), NF1-10 (nostril focus), VC/RT/OH=\(triggerDuration)m (trigger)
        SOUNDS: \(soundsList) | BEATS: \(beatsList)
        
        DESCRIPTION: Natural summary of elements (NO duration). Use friendly terms like "breathwork", "body awareness", "I AM mantra", "nostril focus". End with background sound.

        5m: {"duration":5,"backgroundSoundId":"SP","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB1","trigger":"1"},{"id":"BS1","trigger":"2"},{"id":"IM2","trigger":"3"},{"id":"GB","trigger":"end"}],"title":"Quick Focus","description":"Light breathwork, body awareness, and I AM mantra with spa background."}

        15m evening: {"duration":15,"backgroundSoundId":"SP","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB3","trigger":"1"},{"id":"BS4","trigger":"4"},{"id":"IM4","trigger":"7"},{"id":"RT","trigger":"11"},{"id":"GB","trigger":"end"}],"title":"Evening Unwind","description":"Deep breathing, body scan, I AM mantra, and gratitude reflection with spa soundscape."}
        """
    }
    
    // MARK: - Validation
    
    private func validate(_ timer: AIGeneratedTimer, prompt: String) -> String? {
        let validIds = Set(CatalogsManager.shared.cues.map { $0.id })
        
        // Check all cue IDs exist
        for cue in timer.cues {
            if !validIds.contains(cue.id) && !["SI", "GB"].contains(cue.id) {
                // SI and GB are always valid even if not in catalog
                if !cue.id.hasPrefix("PB") && !cue.id.hasPrefix("BS") && !cue.id.hasPrefix("IM") && !cue.id.hasPrefix("NF") && !["OH", "VC", "RT"].contains(cue.id) {
                    return "Unknown cue: \(cue.id)"
                }
            }
        }
        
        // Check for duplicate trigger cues (OH, VC, RT should each appear at most once)
        let triggerCueIds = Set(["OH", "VC", "RT"])
        var usedTriggerCues: Set<String> = []
        for cue in timer.cues {
            if triggerCueIds.contains(cue.id) {
                if usedTriggerCues.contains(cue.id) {
                    return "Duplicate trigger cue: \(cue.id) - each can only be used once"
                }
                usedTriggerCues.insert(cue.id)
            }
        }
        
        // CRITICAL: Validate trigger values are correct format
        var validCueCount = 0
        for cue in timer.cues {
            let trigger = cue.trigger.lowercased()
            
            // Valid triggers: "start", "end", or a number as string
            if trigger == "start" || trigger == "end" {
                validCueCount += 1
                continue
            }
            
            // Must be a valid minute number
            if let minuteNum = Int(cue.trigger) {
                if minuteNum >= 0 && minuteNum < timer.duration {
                    validCueCount += 1
                    continue
                } else {
                    return "Trigger \(minuteNum) out of range for duration \(timer.duration)"
                }
            }
            
            // Invalid trigger (e.g., "Retrospection", "focus", etc.)
            return "Invalid trigger '\(cue.trigger)' for cue \(cue.id) - must be 'start', 'end', or minute number"
        }
        
        // For sessions > 6 min, require at least 4 valid cues (SI, PB/BS, focus, GB)
        if timer.duration > 6 && validCueCount < 4 {
            return "Session > 6 min requires at least 4 cues, got \(validCueCount)"
        }
        
        // Sessions > 6 min must have IM (finite focus) or a trigger cue (OH/VC/RT) for focus/viz phases
        if timer.duration > 6 {
            let hasTriggerCue = timer.cues.contains { ["OH", "VC", "RT"].contains($0.id) }
            let hasFiniteFocus = timer.cues.contains { $0.id.hasPrefix("IM") || $0.id.hasPrefix("NF") }
            if !hasTriggerCue && !hasFiniteFocus {
                return "Session > 6 min requires IM or trigger cue (OH/VC/RT) but found none"
            }
        }
        
        // Check modules fit within duration, don't overlap, and fill 100% of session time
        var timeline: [Int: String] = [:]
        for cue in timer.cues {
            guard let start = Int(cue.trigger) else { continue }
            // Trigger cues (VC, RT, OH) fill from their start to end of session — user practices silently
            let isTriggerCue = ["VC", "RT", "OH"].contains(cue.id)
            let dur = isTriggerCue ? (timer.duration - start) : cueDuration(cue.id)
            
            if start + dur > timer.duration {
                return "Module \(cue.id) at \(start) exceeds duration \(timer.duration)"
            }
            
            for m in start..<(start + dur) {
                if let existing = timeline[m] {
                    return "Overlap at minute \(m): \(cue.id) conflicts with \(existing)"
                }
                timeline[m] = cue.id
            }
        }
        
        // Check for gaps — modules must fill 100% of session time
        // SI at "start" occupies minute 0 (skipped by the loop above since trigger="start")
        // GB at "end" is instant (0 duration) and doesn't occupy timeline space
        let hasSI = timer.cues.contains { $0.id == "SI" && $0.trigger.lowercased() == "start" }
        let coveredMinutes = timeline.count + (hasSI ? 1 : 0)  // +1 for SI at minute 0
        if coveredMinutes < timer.duration {
            let uncovered = (0..<timer.duration).filter { m in m == 0 ? !hasSI : timeline[m] == nil }
            logger.aiChat("🧠 AI_DEBUG [TIMELINE_GAP] \(coveredMinutes)m covered out of \(timer.duration)m, uncovered minutes: \(uncovered)")
            return "Timeline gap: only \(coveredMinutes)m covered out of \(timer.duration)m"
        }
        
        // Check required fields
        if timer.duration < 1 { return "Duration must be >= 1" }
        if timer.backgroundSoundId.isEmpty { return "Background sound required" }
        
        // PRIORITY CHECK: If user requested body scan, BS should get ~50% of duration
        if timer.duration > 6 {
            let lowerPrompt = prompt.lowercased()
            let bsPriority = lowerPrompt.contains("body scan") || lowerPrompt.contains("bodyscan")
            let pbPriority = lowerPrompt.contains("breath") || lowerPrompt.contains("breathing")
            
            if bsPriority {
                // Calculate BS duration from cues
                var bsTotal = 0
                for cue in timer.cues where cue.id.hasPrefix("BS") {
                    if let num = Int(cue.id.dropFirst(2)) {
                        bsTotal += num
                    }
                }
                let minBsDuration = timer.duration * 40 / 100  // At least 40% for priority
                if bsTotal < minBsDuration {
                    return "BS priority requested but only got \(bsTotal)m (need at least \(minBsDuration)m for \(timer.duration)m session)"
                }
            }
            
            if pbPriority {
                // Calculate PB duration from cues
                var pbTotal = 0
                for cue in timer.cues where cue.id.hasPrefix("PB") {
                    if let num = Int(cue.id.dropFirst(2)) {
                        pbTotal += num
                    }
                }
                let minPbDuration = min(5, timer.duration * 40 / 100)  // At least 40% but capped at PB5
                if pbTotal < minPbDuration {
                    return "PB priority requested but only got \(pbTotal)m (need at least \(minPbDuration)m)"
                }
            }
        }
        
                return nil
            }
            
    // MARK: - Priority Detection
    
    /// Detect ALL priority exercises from user prompt (can be multiple).
    /// Only scans the user's actual request text, ignoring profile context that may contain
    /// generic keywords like "focus" from onboarding goals.
    /// Negation-aware: "no visualization" will NOT trigger VC priority.
    private static func detectPriorityExercises(from prompt: String) -> [String] {
        // Extract just the user request if present (ignore profile context like "Improve focus")
        let textToCheck: String
        if let range = prompt.range(of: "User request:", options: .caseInsensitive) {
            textToCheck = String(prompt[range.upperBound...]).lowercased()
        } else {
            textToCheck = prompt.lowercased()
        }
        
        // Negation-aware keyword check: returns true only if keyword is present WITHOUT a negation prefix
        let negationPrefixes = ["no ", "without ", "skip ", "not ", "don't ", "dont "]
        func containsPositive(_ keyword: String) -> Bool {
            guard textToCheck.contains(keyword) else { return false }
            return !negationPrefixes.contains(where: { textToCheck.contains("\($0)\(keyword)") })
        }
        
        var priorities: [String] = []
        
        // Check for finite exercises
        if containsPositive("body scan") || containsPositive("bodyscan") || containsPositive("body awareness") {
            priorities.append("BS")
        }
        if containsPositive("breath") || containsPositive("breathing") || containsPositive("breathwork") {
            priorities.append("PB")
        }
        
        // Check for I AM mantra (finite focus exercise) — only explicit mantra language
        if containsPositive("mantra") || containsPositive("chant") || containsPositive("i am") || containsPositive("affirmation") {
            priorities.append("IM")
        }
        // Check for Nostril Focus (finite focus exercise)
        if containsPositive("nostril") || containsPositive("nadi shodhana") || containsPositive("alternate nostril") {
            priorities.append("NF")
        }
        if containsPositive("visualization") || containsPositive("vision") || containsPositive("intention") {
            priorities.append("VC")
        }
        if containsPositive("retrospection") || containsPositive("reflection") || containsPositive("gratitude") {
            priorities.append("RT")
        }
        
        return priorities
    }
    
    // MARK: - Fallback Builder
    
    /// Get cue duration from CueManager (single source of truth from Firebase)
    private static func getCueDuration(_ id: String) -> Int {
        return CatalogsManager.shared.bodyScanDurations[id] ?? 1
    }
    
    private static func buildFallback(duration: Int, prompt: String) -> AIGeneratedTimer {
        let loader = CompositionGuidelinesLoader.shared
        let isSleep = loader.shouldSkipGentleBell(prompt: prompt)
        let sessionType = loader.detectSessionType(from: prompt) ?? "relaxation"
        let priorities = detectPriorityExercises(from: prompt)
        
        logger.aiChat("🧠 AI_DEBUG FALLBACK dur=\(duration) type=\(sessionType) sleep=\(isSleep) priorities=\(priorities.isEmpty ? "none" : priorities.joined(separator: ","))")
        
        var cues: [AIGeneratedTimer.AICue] = []
        
        // Always start with SI
        cues.append(.init(id: "SI", trigger: "start"))
        
        if duration == 1 {
            // 1 min: SI only + GB
            // (SI already added)
        } else if duration <= 3 {
            // 2-3 min: SI + ONE relaxation (PB or BS) + GB
            let relaxDuration = duration - 1  // 1 or 2 minutes
            // Use priority if detected, otherwise random
            if priorities.contains("BS") {
                cues.append(.init(id: "BS\(relaxDuration)", trigger: "1"))
            } else if priorities.contains("PB") {
                cues.append(.init(id: "PB\(relaxDuration)", trigger: "1"))
            } else {
                let usePB = prompt.hashValue % 2 == 0
                if usePB {
                    cues.append(.init(id: "PB\(relaxDuration)", trigger: "1"))
                } else {
                    cues.append(.init(id: "BS\(relaxDuration)", trigger: "1"))
                }
            }
        } else if duration == 4 {
            // 4 min: SI + PB + BS + GB (no trigger cue)
            // With priority: give priority exercise 2m, other 1m
            if priorities.contains("BS") {
                cues.append(.init(id: "PB1", trigger: "1"))
                cues.append(.init(id: "BS2", trigger: "2"))
            } else if priorities.contains("PB") {
                cues.append(.init(id: "PB2", trigger: "1"))
                cues.append(.init(id: "BS1", trigger: "3"))
            } else {
                cues.append(.init(id: "PB1", trigger: "1"))
                cues.append(.init(id: "BS2", trigger: "2"))
            }
        } else if duration <= 6 {
            // 5-6 min: SI + PB + BS + ONE trigger cue + GB
            // With priority: priority gets more time
            let availableForRelax = duration - 1 - 2  // SI=1, trigger=2 (approx)
            
            var pbDur: Int
            var bsDur: Int
            
            if priorities.contains("BS") {
                pbDur = 1
                bsDur = max(1, min(availableForRelax - 1, 10))
            } else if priorities.contains("PB") {
                pbDur = max(1, min(availableForRelax - 1, 5))
                bsDur = 1
            } else {
                pbDur = 1
                bsDur = max(1, min(2, availableForRelax - 1))
            }
            
            let triggerStart = 1 + pbDur + bsDur
            
            cues.append(.init(id: "PB\(pbDur)", trigger: "1"))
            cues.append(.init(id: "BS\(bsDur)", trigger: "\(1 + pbDur)"))
            
            // Pick focus module based on priority or session type
            let focusModule: String
            if priorities.contains("NF") {
                focusModule = "NF2"
            } else if priorities.contains("IM") {
                focusModule = "IM2"
            } else if priorities.contains("VC") {
                focusModule = "VC"
            } else if priorities.contains("RT") {
                focusModule = "RT"
            } else {
                switch sessionType {
                case "morning": focusModule = "VC"
                case "evening": focusModule = "RT"
                default:
                    let options = ["IM2", "NF2", "VC", "RT"]
                    focusModule = options[Int.random(in: 0..<options.count)]
                }
            }
            cues.append(.init(id: focusModule, trigger: "\(triggerStart)"))
            logger.aiChat("🧠 AI_DEBUG [FOCUS_SELECT] short session picked \(focusModule) at \(triggerStart)")
        } else {
            // > 6 min: Full 4-phase structure with MULTI-PRIORITY support
            // Priority section = 50-60% of total session, split equally among all priorities
            // Non-priority section (relaxation) = 40-50% of total session
            
            // Categorize priorities: IM and NF are finite focus exercises
            let finitePriorities = priorities.filter { ["BS", "PB", "IM", "NF"].contains($0) }
            let triggerPriorities = priorities.filter { ["VC", "RT"].contains($0) }
            
            // Calculate phase allocations:
            // - Relaxation phase: ~40% of session (SI + PB + BS)
            // - Priority/Focus phase: ~60% of session (trigger cues with quiet time)
            let relaxationBudget = Int(Double(duration) * 0.4)  // ~40% for SI + PB + BS
            let priorityBudget = duration - relaxationBudget - 1  // ~60% for priorities (-1 for GB)
            
            logger.aiChat("🧠 AI_DEBUG PHASE relaxation=\(relaxationBudget)m (~40%), priority=\(priorityBudget)m (~60%)")
            
            // Calculate relaxation phase
            var pbDuration: Int
            var bsDuration: Int
            
            // When a finite exercise (BS/PB) is prioritized, give it 50% of TOTAL session
            let fiftyPercentOfSession = duration / 2
            
            if finitePriorities.contains("BS") && finitePriorities.contains("PB") {
                // Both BS and PB prioritized - split 50% between them
                pbDuration = max(1, min(5, fiftyPercentOfSession / 2))
                bsDuration = max(1, min(10, fiftyPercentOfSession - pbDuration))
                logger.aiChat("🧠 AI_DEBUG PRIORITY BS+PB: PB=\(pbDuration)m, BS=\(bsDuration)m (50% of \(duration)m)")
            } else if finitePriorities.contains("BS") {
                // BS prioritized - give it 50% of total session
                pbDuration = 1
                bsDuration = max(1, min(10, fiftyPercentOfSession))
                logger.aiChat("🧠 AI_DEBUG PRIORITY BS gets \(bsDuration)m (50% of \(duration)m)")
            } else if finitePriorities.contains("PB") {
                // PB prioritized - give it 50% of total session (capped at PB5)
                pbDuration = max(1, min(5, fiftyPercentOfSession))
                bsDuration = 1
                logger.aiChat("🧠 AI_DEBUG PRIORITY PB gets \(pbDuration)m (50% of \(duration)m)")
            } else {
                // No finite priorities: use relaxation budget for standard split
                let pbBsTime = relaxationBudget - 1  // Subtract SI
                pbDuration = max(1, min(5, Int(round(Double(pbBsTime) * 0.4))))
                bsDuration = max(1, min(10, pbBsTime - pbDuration))
            }
            
            cues.append(.init(id: "PB\(pbDuration)", trigger: "1"))
            cues.append(.init(id: "BS\(bsDuration)", trigger: "\(1 + pbDuration)"))
            
            let relaxEnd = 1 + pbDuration + bsDuration
            var currentMinute = relaxEnd
            
            // Priority/Focus phase: place finite focus module (IM/NF) first if requested, then trigger cues
            let focusPriority = priorities.first(where: { ["IM", "NF"].contains($0) })
            if let focus = focusPriority {
                // User explicitly requested a finite focus module — place it before any trigger cues
                let remainingTime = duration - currentMinute - 1  // -1 for GB
                let focusDuration: Int
                if triggerPriorities.isEmpty {
                    // No trigger cues — focus gets all remaining time
                    focusDuration = max(focus == "NF" ? 1 : 2, min(10, remainingTime))
                } else {
                    // Trigger cues follow — give focus ~half, leave room for triggers
                    let minVizTime = 2
                    focusDuration = max(focus == "NF" ? 1 : 2, min(10, max(1, remainingTime - minVizTime)))
                }
                cues.append(.init(id: "\(focus)\(focusDuration)", trigger: "\(currentMinute)"))
                logger.aiChat("🧠 AI_DEBUG [FOCUS_SELECT] priority \(focus)\(focusDuration) at \(currentMinute)")
                currentMinute += focusDuration
            }
            
            if !triggerPriorities.isEmpty {
                // User requested specific trigger cues - split remaining time among them
                let remainingForTriggers = duration - currentMinute - 1  // -1 for GB
                let triggerCount = triggerPriorities.count
                let timePerTrigger = max(1, remainingForTriggers / max(1, triggerCount))
                
                logger.aiChat("🧠 AI_DEBUG PRIORITY trigger cues: \(triggerPriorities.joined(separator: ",")) each gets ~\(timePerTrigger)m (~\(timePerTrigger * 100 / duration)%)")
                
                for (index, cue) in triggerPriorities.enumerated() {
                    let cueDuration = getCueDuration(cue)
                    cues.append(.init(id: cue, trigger: "\(currentMinute)"))
                    
                    let quietTime: Int
                    if index < triggerCount - 1 {
                        quietTime = timePerTrigger - cueDuration
                        currentMinute += timePerTrigger
                    } else {
                        quietTime = duration - currentMinute - cueDuration - 1
                    }
                    logger.aiChat("🧠 AI_DEBUG PRIORITY \(cue): \(cueDuration)m audio + \(max(0, quietTime))m quiet")
                }
            } else if focusPriority == nil {
                // No trigger priorities AND no explicit focus priority - standard focus (IM or NF) + visualization (VC/RT)
                // Randomly pick between IM and NF for variety (true random, not hash-based)
                let focusPrefix = Bool.random() ? "IM" : "NF"
                let minDuration = focusPrefix == "NF" ? 1 : 2
                
                // Calculate remaining time: need room for focus + viz (min 2m for viz trigger practice) + GB
                let remainingTime = duration - currentMinute - 1  // -1 for GB
                let minVizTime = 2  // Minimum time for a trigger cue to be useful
                
                if remainingTime >= minDuration + minVizTime {
                    // Enough room for both focus + viz
                    // Give focus roughly half, but ensure viz gets at least minVizTime
                    let maxFocusDuration = remainingTime - minVizTime
                    let focusDuration = max(minDuration, min(10, min(maxFocusDuration, priorityBudget / 2)))
                    cues.append(.init(id: "\(focusPrefix)\(focusDuration)", trigger: "\(currentMinute)"))
                    
                    let vizStart = currentMinute + focusDuration
                    let vizCue = sessionType == "evening" ? "RT" : "VC"
                    cues.append(.init(id: vizCue, trigger: "\(vizStart)"))
                    
                    logger.aiChat("🧠 AI_DEBUG [FOCUS_SELECT] picked \(focusPrefix)\(focusDuration) at \(currentMinute), \(vizCue) at \(vizStart) (vizTime=\(duration - vizStart - 1)m)")
                } else {
                    // Not enough room for both — extend focus to fill remaining time, skip viz
                    let focusDuration = max(minDuration, min(10, remainingTime))
                    cues.append(.init(id: "\(focusPrefix)\(focusDuration)", trigger: "\(currentMinute)"))
                    
                    logger.aiChat("🧠 AI_DEBUG [FOCUS_SELECT] picked \(focusPrefix)\(focusDuration) at \(currentMinute), no viz (only \(remainingTime)m remaining)")
                }
            }
        }
        
        // GB at end for ALL sessions except sleep
        if !isSleep {
            cues.append(.init(id: "GB", trigger: "end"))
        }
        
        // Pick background sound based on session type
        let bg: String
        switch sessionType {
        case "sleep":
            bg = "OC"
        case "focus", "morning", "energy", "creativity":
            bg = "LI"
        case "anxiety", "stress", "relaxation", "evening", "gratitude":
            bg = "SP"
        default:
            bg = "SP"
        }
        
        // Pick binaural beat based on session type
        let bb: String?
        let beats = CatalogsManager.shared.beats
        if beats.isEmpty {
            bb = nil
        } else {
            switch sessionType {
            case "sleep":
                bb = "BB2"
            case "focus", "creativity":
                bb = "BB14"
            case "morning", "energy":
                bb = "BB6"
            case "anxiety", "stress", "relaxation", "evening", "gratitude":
                bb = "BB10"
            default:
                bb = "BB10"
            }
        }
        
        // Title - use contextual analysis for more diverse naming
        let title = Self.generateContextualTitle(from: prompt, duration: duration, sessionType: sessionType, priorities: priorities)
        
        // Generate element-focused description (NO duration)
        let description = Self.buildElementDescription(from: cues, backgroundSoundId: bg)
        
        logger.aiChat("🧠 AI_DEBUG FALLBACK result: cues=\(cues.map { "\($0.id)@\($0.trigger)" }.joined(separator: ",")) bg=\(bg) bb=\(bb ?? "nil")")
        
        return AIGeneratedTimer(
            duration: duration,
            backgroundSoundId: bg,
            binauralBeatId: bb,
            cues: cues,
            segments: nil,
            title: title,
            description: description
        )
    }
    
    // MARK: - Contextual Title Generation
    
    /// Generates a contextual, diverse title based on prompt analysis.
    /// Scopes keyword matching to the user's actual request text, ignoring profile context.
    private static func generateContextualTitle(from prompt: String, duration: Int, sessionType: String, priorities: [String]) -> String {
        // Extract just the user request if present (ignore profile context like "Improve focus")
        let lower: String
        if let range = prompt.range(of: "User request:", options: .caseInsensitive) {
            lower = String(prompt[range.upperBound...]).lowercased()
        } else {
            lower = prompt.lowercased()
        }
        
        // 1. Check for specific contextual keywords first (most specific)
        let contextualTitles: [(keywords: [String], title: String)] = [
            // Situational contexts
            (["meeting", "presentation", "interview", "call"], "Pre-Meeting Calm"),
            (["before bed", "bedtime", "sleep", "night", "insomnia"], "Sleep Meditation"),
            (["wake up", "morning", "sunrise", "start the day", "start my day"], "Morning Clarity"),
            (["lunch", "midday", "afternoon break"], "Midday Reset"),
            (["after work", "end of day", "evening", "wind down"], "Evening Unwind"),
            
            // Emotional states
            (["anxiety", "anxious", "worried", "nervous", "panic"], "Anxiety Relief"),
            (["stress", "stressed", "overwhelmed", "tense", "pressure"], "Stress Relief"),
            (["sad", "sadness", "down", "depressed", "low"], "Mood Lift"),
            (["angry", "anger", "frustrated", "irritated"], "Inner Calm"),
            (["tired", "exhausted", "fatigue", "drained"], "Energy Restore"),
            
            // Goals/intentions
            (["focus", "concentrate", "productivity", "work", "study"], "Focus Session"),
            (["creative", "creativity", "inspiration", "ideas"], "Creative Flow"),
            (["confidence", "confident", "self-esteem"], "Confidence Boost"),
            (["gratitude", "grateful", "thankful"], "Gratitude Practice"),
            (["clarity", "clear mind", "mental clarity"], "Mental Clarity"),
            
            // Physical
            (["headache", "head", "tension"], "Tension Release"),
            (["pain", "ache", "sore"], "Body Ease"),
            (["energy", "energize", "boost", "vitality"], "Energy Boost"),
            
            // Quick/short sessions
            (["quick", "short", "fast", "brief", "minute break"], "Quick Reset"),
        ]
        
        for (keywords, title) in contextualTitles {
            if keywords.contains(where: { lower.contains($0) }) {
                // For very short durations, prefix with "Quick" if not already quick-themed
                if duration <= 3 && !title.lowercased().contains("quick") {
                    return "Quick \(title)"
                }
                return title
            }
        }
        
        // 2. Check for priority exercises and generate title based on them
        if !priorities.isEmpty {
            let titleOptions: [String]
            if priorities.contains("BS") && priorities.contains("PB") {
                titleOptions = ["Body & Breath", "Full Body Reset", "Ground & Breathe", "Body Harmony"]
            } else if priorities.contains("BS") {
                titleOptions = ["Body Awareness", "Body Scan", "Full Body Check-In", "Grounding Practice"]
            } else if priorities.contains("PB") {
                titleOptions = ["Breathwork Session", "Breath Focus", "Deep Breathing", "Breath & Calm"]
            } else if priorities.contains("NF") {
                titleOptions = ["Nostril Focus", "Breath Awareness", "Focused Breathing", "Nostril Meditation", "Breath Clarity"]
            } else if priorities.contains("IM") {
                titleOptions = ["I AM Mantra", "Mantra Practice", "Guided Mantra", "Inner Affirmation", "Mantra Meditation"]
            } else if priorities.contains("VC") {
                titleOptions = ["Vision & Intention", "Clarity Practice", "Future Vision", "Intention Setting"]
            } else if priorities.contains("RT") {
                titleOptions = ["Reflection Practice", "Gratitude Moment", "Day Reflection", "Mindful Review"]
            } else {
                titleOptions = []
            }
            
            if !titleOptions.isEmpty {
                let index = abs(prompt.hashValue ^ duration) % titleOptions.count
                let baseTitle = titleOptions[index]
                if duration <= 3 {
                    return "Quick \(baseTitle)"
                }
                return baseTitle
            }
        }
        
        // 3. Generate based on session type with variety
        let sessionTypeTitles: [String: [String]] = [
            "sleep": ["Sleep Meditation", "Restful Night", "Deep Sleep", "Peaceful Slumber"],
            "focus": ["Focus Session", "Clear Mind", "Deep Focus", "Concentration"],
            "morning": ["Morning Clarity", "Sunrise Session", "Day Starter", "Morning Energy"],
            "evening": ["Evening Unwind", "Day's End", "Evening Reflection", "Sunset Calm"],
            "relaxation": ["Deep Calm", "Inner Peace", "Peaceful Mind", "Gentle Ease", "Calm Session", "Tranquil Moment"],
            "anxiety": ["Anxiety Relief", "Calm Nerves", "Peace of Mind", "Worry Free"],
            "stress": ["Stress Relief", "Tension Release", "Decompress", "Let Go"]
        ]
        
        // Short session variants
        let shortSessionTypeTitles: [String: [String]] = [
            "sleep": ["Quick Wind Down", "Brief Rest", "Short Calm"],
            "focus": ["Quick Focus", "Brief Clarity", "Short Reset"],
            "morning": ["Quick Start", "Brief Energize", "Morning Minute"],
            "evening": ["Quick Unwind", "Brief Settle", "Evening Pause"],
            "relaxation": ["Quick Calm", "Brief Peace", "Short Break", "Moment of Calm"],
            "anxiety": ["Quick Relief", "Brief Calm", "Instant Ease"],
            "stress": ["Quick Release", "Brief Reset", "Stress Break"]
        ]
        
        if duration <= 3 {
            if let titles = shortSessionTypeTitles[sessionType], !titles.isEmpty {
                let index = abs(prompt.hashValue) % titles.count
                return titles[index]
            }
        } else if duration <= 6 {
            // Medium-short sessions - use base titles but can add "Short" prefix
            if let titles = sessionTypeTitles[sessionType], !titles.isEmpty {
                let index = abs(prompt.hashValue) % titles.count
                return titles[index]
            }
        } else {
            if let titles = sessionTypeTitles[sessionType], !titles.isEmpty {
                let index = abs(prompt.hashValue) % titles.count
                return titles[index]
            }
        }
        
        // 4. Final fallback - diverse generic titles based on duration
        let shortGenericTitles = [
            "Quick Reset",
            "Brief Pause",
            "Moment of Calm",
            "Quick Breathe",
            "Short Break"
        ]
        
        let genericTitles = [
            "Mindful Moment",
            "Inner Peace",
            "Calm Session",
            "Peaceful Practice",
            "Gentle Reset",
            "Quiet Mind",
            "Serene Space",
            "Mindful Pause",
            "Centered Calm",
            "Still Point"
        ]
        
        let titles = duration <= 3 ? shortGenericTitles : genericTitles
        let index = abs(prompt.hashValue) % titles.count
        return titles[index]
    }
    
    // MARK: - Element Description Builder
    
    /// Builds an element-focused description from cues (no duration mentioned)
    private static func buildElementDescription(from cues: [AIGeneratedTimer.AICue], backgroundSoundId: String) -> String {
        // Map cue IDs to friendly names
        var elements: [String] = []
        
        for cue in cues {
            let id = cue.id
            // Skip SI and GB - they're structural, not content elements
            if id == "SI" || id == "GB" { continue }
            
            let friendlyName: String
            if id.hasPrefix("PB") {
                friendlyName = "breathwork"
            } else if id.hasPrefix("BS") {
                friendlyName = "body awareness"
            } else if id.hasPrefix("IM") {
                friendlyName = "I AM mantra"
            } else if id.hasPrefix("NF") {
                friendlyName = "nostril focus"
            } else {
                switch id {
                case "VC": friendlyName = "visualization"
                case "RT": friendlyName = "reflection"
                case "OH": friendlyName = "open heart practice"
                default: friendlyName = id.lowercased()
                }
            }
            
            // Avoid duplicates
            if !elements.contains(friendlyName) {
                elements.append(friendlyName)
            }
        }
        
        // Get background sound name
        let soundName = CatalogsManager.shared.sounds
            .first(where: { $0.id == backgroundSoundId })?.name ?? "ambient"
        
        // Build description
        if elements.isEmpty {
            return "A gentle meditation with \(soundName.lowercased()) background."
        } else if elements.count == 1 {
            return "\(elements[0].capitalized) with \(soundName.lowercased()) background."
        } else {
            let lastElement = elements.removeLast()
            let elementList = elements.joined(separator: ", ")
            return "\(elementList.capitalized), and \(lastElement) with \(soundName.lowercased()) background."
        }
    }
    
    // MARK: - Cue Duration Helper
    
    private func cueDuration(_ cueId: String) -> Int {
        // CueManager is the single source of truth (loaded from Firebase)
        if let d = CatalogsManager.shared.bodyScanDurations[cueId] { 
            return max(1, d) 
        }
        
        // Minimal fallback for special cues only
        switch cueId {
        case "GB": return 0
        case "SI": return 1
        case "OH", "VC", "RT": return 5 // trigger cues with quiet span
        default:
            // Extract number from ID (BS3 -> 3, PB2 -> 2, IM5 -> 5)
            if let num = Int(cueId.dropFirst(2)) {
                return num
            }
            return 1
        }
    }

    // MARK: - Intent Classification
    
    func classifyIntent(prompt: String, conversationHistory: [ChatMessage] = []) async throws -> String {
        let systemPrompt = """
        You are an intent classifier for a meditation app. Classify the user's latest message intent as exactly one of:
        - meditation: user wants to create or MODIFY a meditation (e.g., change body scan to 7 minutes, 10 minute sleep meditation)
        - history: user asks about THEIR personal meditation data (their heart rate, their sessions, their progress, their statistics, their averages, their history)
        - explain: user asks a GENERAL question about meditation concepts (definition, benefits, how to meditate, why meditate) - NOT about their personal data
        - app_help: app/account/billing/support questions (cancel subscription, pricing, restore purchase, notifications)
        - out_of_scope: non-app, non-meditation requests (weather, call/text/email someone, jokes, web queries)
        - path_guidance: user asks what to do next, where to begin, what's their next step, guidance on their meditation journey, what to practice
        - explore_guidance: user asks for a pre-recorded session, specifically mentions "pre-recorded", "prerecorded", "guided session", or "from library"
        - conversation: greetings/small talk or generic chat that isn't clearly any of the above
        
        IMPORTANT: 
        - If user asks about "my heart rate", "my sessions", "my average", "my progress", "my history", "how many sessions", "when did I" - classify as "history".
        - If user asks "what should I do", "what's next", "where do I begin", "what do I do next", "next step", "guide me", "what to practice", "help me start" - classify as "path_guidance".
        - If user mentions "pre-recorded", "prerecorded", "guided session", "from library", "ready-made" - classify as "explore_guidance".
        
        Respond ONLY with compact JSON on one line: {"intent":"meditation|history|explain|app_help|out_of_scope|path_guidance|explore_guidance|conversation"}
        Do not include any extra text.
        """
        let content = try await callOpenAI(userPrompt: prompt, systemPrompt: systemPrompt, conversationHistory: conversationHistory)
        
        // Parse response
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.firstIndex(of: "{"), let last = s.lastIndex(of: "}") { s = String(s[first...last]) }
        
        struct SimpleIntent: Decodable { let intent: String }
        if let data = s.data(using: .utf8), let parsed = try? JSONDecoder().decode(SimpleIntent.self, from: data) {
            let v = parsed.intent.lowercased()
            if ["meditation","history","explain","conversation","app_help","out_of_scope","path_guidance","explore_guidance"].contains(v) { 
                logger.aiChat("🧠 AI_DEBUG INTENT classified=\(v)")
                return v 
            }
        }
        
        // Fallback to local heuristic
        let lower = prompt.lowercased()
        
        // Path guidance: user asking what to do next
        let pathGuidanceSignals = ["what should i do", "what's next", "whats next", "what do i do",
                                   "where do i begin", "where do i start", "where should i start",
                                   "next step", "what's the next step", "whats the next step",
                                   "guide me", "help me start", "what now", "what to practice",
                                   "what to do next", "continue my journey", "what's next in my path"]
        if pathGuidanceSignals.contains(where: { lower.contains($0) }) { return "path_guidance" }
        
        // Explore guidance: user asking for pre-recorded session
        let exploreGuidanceSignals = ["pre-recorded", "prerecorded", "pre recorded", "guided session", "from library", "ready-made", "ready made"]
        if exploreGuidanceSignals.contains(where: { lower.contains($0) }) {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE] heuristic fallback triggered for: \(prompt)")
            return "explore_guidance"
        }
        
        // History: user asking about their personal data
        let historySignals = ["my heart rate", "my hr", "my bpm", "my session", "my meditation", "my average", "my avg",
                              "my history", "my progress", "my stats", "my statistics", "my trend",
                              "how many session", "how many meditation", "how long have i",
                              "when did i", "which session", "lowest heart", "highest heart", "best session"]
        if historySignals.contains(where: { lower.contains($0) }) { return "history" }
        
        let isQuestion = lower.hasSuffix("?")
        let explainStarts = ["what is","how do","how does","why","explain","tell me about","what's","whats"]
        if isQuestion && (explainStarts.contains { lower.hasPrefix($0) }) && !historySignals.contains(where: { lower.contains($0) }) { 
            return "explain" 
        }
        
        let appHelp = ["subscription","cancel","billing","price","pricing","restore","purchase","account","login","log in","sign in","password","notification","terms","privacy","support","contact"]
        if appHelp.contains(where: { lower.contains($0) }) { return "app_help" }
        
        let oos = ["weather","forecast","temperature","call","text","email","message","facetime","maps","route","restaurant","deliver","order","uber","lyft","news","stock","price of","btc","ethereum","joke","poem","code this","calculate","math"]
        if oos.contains(where: { lower.contains($0) }) { return "out_of_scope" }
        
        let modifyHints = ["change","set","make","switch","update","replace","remove","add","extend","shorten","longer","shorter","increase","decrease","edit","adjust","tweak","body scan","bs"]
        if modifyHints.contains(where: { lower.contains($0) }) { return "meditation" }
        
        return "conversation"
    }
    
    // MARK: - Explanation Generation (unchanged)
    
    func generateExplanation(prompt: String, conversationHistory: [ChatMessage] = []) async throws -> String {
        let systemPrompt = """
        You are a helpful meditation guide. Answer the user's question clearly and concisely in 2-4 sentences.
        Avoid lists or bullet points. Do not include code blocks.
        Keep it practical and friendly.
        """
        let text = try await callOpenAI(userPrompt: prompt, systemPrompt: systemPrompt, conversationHistory: conversationHistory)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        if words.count <= 120 { return trimmed }
        let limited = words.prefix(120).joined(separator: " ")
        return String(limited)
    }
    
    // MARK: - Conversation Generation (unchanged)
    
    func generateConversation(prompt: String, intent: String = "conversation", conversationHistory: [ChatMessage] = []) async throws -> String {
        var persona = "You are a friendly meditation guide called Sensei. Keep responses to 1-3 sentences. Kindly steer the user back to creating a meditation when appropriate."
        switch intent {
        case "app_help":
            persona += "\nIf the user asks for app/account/billing help, explain briefly what they can do in-app (e.g., Settings -> Subscription) and suggest contacting support via the app if needed."
        case "out_of_scope":
            persona += "\nIf the request is outside meditation or app help (e.g., weather, calling friends), politely say it's out of scope and suggest crafting a meditation instead."
        default: break
        }
        let text = try await callOpenAI(userPrompt: prompt, systemPrompt: persona, conversationHistory: conversationHistory)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Path Guidance Message Generation
    
    /// Generates a simple sentence to introduce the next path step
    func generatePathGuidanceMessage(
        userPrompt: String,
        nextStepTitle: String,
        completedCount: Int,
        totalCount: Int
    ) async throws -> String {
        let progressContext: String
        if completedCount == 0 {
            progressContext = "This is their first step."
        } else {
            progressContext = "They've done \(completedCount) of \(totalCount) steps."
        }
        
        let systemPrompt = """
        Write ONE simple sentence to introduce the next meditation lesson.
        
        RULES:
        - Maximum 10 words
        - Simple everyday language, like talking to a friend
        - NO spiritual or poetic language
        - NO words like: journey, essence, path, explore, discover, embrace
        - Just be helpful and normal
        
        CONTEXT:
        - User asked: "\(userPrompt)"
        - Next lesson: "\(nextStepTitle)"
        - \(progressContext)
        
        GOOD examples: "Here's a good one for you." / "Try this next." / "This one's worth checking out."
        BAD examples: "Begin your journey..." / "Explore the essence..." / "Embrace this step..."
        
        Output ONLY the sentence.
        """
        
        let text = try await callOpenAI(userPrompt: "Generate the sentence.", systemPrompt: systemPrompt, conversationHistory: [])
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure we have a valid response
        guard !trimmed.isEmpty && trimmed.count >= 5 else {
            return "Try this one."
        }
        
        return trimmed
    }
    
    // MARK: - Explore Guidance Message Generation
    
    /// Generates a simple sentence to introduce a pre-recorded explore session
    func generateExploreGuidanceMessage(
        userPrompt: String,
        sessionTitle: String,
        timeOfDay: String
    ) async throws -> String {
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] generateExploreGuidanceMessage session=\(sessionTitle) time=\(timeOfDay)")
        
        let systemPrompt = """
        Write ONE simple sentence to introduce a pre-recorded meditation session.
        
        RULES:
        - Maximum 12 words
        - Simple everyday language, like talking to a friend
        - NO spiritual or poetic language
        - NO words like: journey, essence, explore, discover, embrace
        - Just be helpful and normal
        - Reference the time of day naturally if relevant
        
        CONTEXT:
        - User asked: "\(userPrompt)"
        - Session title: "\(sessionTitle)"
        - Time of day: \(timeOfDay)
        
        GOOD examples: "Here's a great \(timeOfDay) session for you." / "Try this one." / "This should be perfect right now."
        BAD examples: "Embark on a journey..." / "Discover the essence..." / "Embrace this moment..."
        
        Output ONLY the sentence.
        """
        
        let text = try await callOpenAI(userPrompt: "Generate the sentence.", systemPrompt: systemPrompt, conversationHistory: [])
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure we have a valid response
        guard !trimmed.isEmpty && trimmed.count >= 5 else {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE] generateExploreGuidanceMessage fallback used")
            return "Here's a session for you."
        }
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] generateExploreGuidanceMessage result=\(trimmed)")
        return trimmed
    }

    // MARK: - Meditation Acknowledgment Generation
    
    /// Generates a natural, conversational acknowledgment of the user's request
    /// This is displayed as text above the meditation card
    func generateMeditationPrefix(
        userPrompt: String,
        conversationHistory: [ChatMessage] = [],
        response: AITimerResponse
    ) async throws -> String {
        let m = response.meditationConfiguration
        let cueNames = m.cueSettings.map { $0.cue.name }.joined(separator: ", ")
        let backgroundName = m.backgroundSound.name

        let systemPrompt = """
        You are Dojo's Sensei. Write a SHORT, natural acknowledgment that you've created a meditation for the user.
        
        CRITICAL RULES:
        - 1 sentence only, maximum 18 words, maximum 120 characters.
        - Do NOT mention the duration, timing, or minutes.
        - Do NOT list the meditation elements or techniques.
        - Do NOT give instructions or steps.
        - MUST be grammatically complete. Never end with prepositions.
        - Vary your phrasing. Never start with "Ok", "Okay", "Sure", or "Great".
        
        CONTENT:
        - Acknowledge you've created/designed/crafted a meditation for them.
        - Briefly connect it to their stated need or goal (e.g., "to help you relax before your meeting", "to ease your anxiety", "to start your day with focus").
        - Sound warm, natural, and conversational - like a helpful guide.
        
        GOOD EXAMPLES:
        - "I've designed a meditation to help you feel grounded before your meeting."
        - "Here's a practice to help ease your mind and find some calm."
        - "I've crafted something to help you unwind after a long day."
        - "This meditation will help you start the day with clarity and energy."
        
        BAD EXAMPLES (avoid):
        - "Ok, I've made a 7-minute meditation for you." (has duration, starts with Ok)
        - "Here's a meditation with breathwork and body scan." (lists elements)
        - "I've created a session that includes settling in, breath exercises..." (lists elements)
        
        Output ONLY the acknowledgment text, nothing else.
        """

        let user = """
        USER_REQUEST: \(userPrompt)
        MEDITATION_ELEMENTS: \(cueNames) with \(backgroundName) background
        """

        logger.aiChat("🧠 AI_DEBUG PREFIX start")
        let text = try await callOpenAI(userPrompt: user, systemPrompt: systemPrompt, conversationHistory: conversationHistory)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = clipPrefix(trimmed, maxSentences: 1, maxWords: 20, maxChars: 130)
        logger.aiChat("🧠 AI_DEBUG PREFIX done len=\(clipped.count)")
        
        // Ensure we have a valid acknowledgment
        var final = clipped
        if final.isEmpty || final.count < 10 {
            final = shortAcknowledgmentLine(from: userPrompt)
        }
        return final
    }

    /// Generates a contextual fallback acknowledgment based on the user's request
    private func shortAcknowledgmentLine(from prompt: String) -> String {
        let lower = prompt.lowercased()
        
        if lower.contains("meeting") || lower.contains("presentation") || lower.contains("interview") {
            return "I've designed a meditation to help you feel grounded and focused."
        } else if lower.contains("sleep") || lower.contains("bedtime") || lower.contains("night") {
            return "Here's a calming practice to help you drift off peacefully."
        } else if lower.contains("morning") || lower.contains("wake") || lower.contains("start") {
            return "I've crafted a meditation to energize your morning."
        } else if lower.contains("stress") || lower.contains("anxious") || lower.contains("anxiety") || lower.contains("overwhelm") {
            return "Here's a practice to help ease your mind and find some calm."
        } else if lower.contains("focus") || lower.contains("concentrate") || lower.contains("productive") {
            return "I've prepared a meditation to sharpen your focus."
        } else if lower.contains("relax") || lower.contains("calm") || lower.contains("unwind") {
            return "Here's a meditation to help you relax and unwind."
        } else if lower.contains("evening") || lower.contains("day") || lower.contains("tired") {
            return "I've crafted something to help you decompress."
        } else {
            let options = [
                "I've put together a meditation tailored for you.",
                "Here's a practice designed with your needs in mind.",
                "I've crafted a meditation just for you."
            ]
            return options.randomElement() ?? "I've put together a meditation tailored for you."
        }
    }

    private func clipPrefix(_ raw: String, maxSentences: Int, maxWords: Int, maxChars: Int) -> String {
        var s = raw.replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading Ok/Okay
        if let re = try? NSRegularExpression(pattern: "^\\s*(ok|okay)[!.,:;\\-\\s]*", options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Split into complete sentences
        var sentences: [String] = []
        var current = ""
        for ch in s {
            current.append(ch)
            if ".!?".contains(ch) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { sentences.append(piece) }
                current = ""
            }
        }
        
        guard !sentences.isEmpty else {
            var fallback = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.hasSuffix(".") && !fallback.hasSuffix("!") && !fallback.hasSuffix("?") {
                fallback += "."
            }
            return fallback
        }

        var assembled: [String] = []
        var totalWords = 0
        var totalChars = 0
        
        for sent in sentences.prefix(maxSentences) {
            let sentTrim = sent.trimmingCharacters(in: .whitespacesAndNewlines)
            let wc = sentTrim.split(separator: " ").count
            let sc = sentTrim.count
            let spacer = assembled.isEmpty ? 0 : 1
            
            if assembled.isEmpty {
                assembled.append(sentTrim)
                totalWords = wc
                totalChars = sc
            } else if totalWords + wc <= maxWords && totalChars + spacer + sc <= maxChars {
                assembled.append(sentTrim)
                totalWords += wc
                totalChars += spacer + sc
            } else {
                break
            }
        }

        return assembled.joined(separator: " ")
    }
    
    // MARK: - Private Helpers
    
    private func loadLatestResources() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CatalogsManager.shared.fetchCatalogs { _ in
                continuation.resume()
            }
        }
    }
    
    private func callOpenAI(userPrompt: String, systemPrompt: String, conversationHistory: [ChatMessage] = []) async throws -> String {
        // Proactive offline check - provides instant feedback instead of waiting for network timeout
        guard NetworkMonitor.shared.isConnected else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                userInfo: [NSLocalizedDescriptionKey: "No internet connection"]
            )
        }
        
        var messages: [OpenAIRequest.OpenAIMessage] = [
            OpenAIRequest.OpenAIMessage(role: "system", content: systemPrompt)
        ]
        
        for chatMessage in conversationHistory {
            if chatMessage.isUser {
                messages.append(OpenAIRequest.OpenAIMessage(role: "user", content: chatMessage.content))
            } else {
                let content = chatMessage.meditation?.description ?? chatMessage.content
                if !content.isEmpty {
                    messages.append(OpenAIRequest.OpenAIMessage(role: "assistant", content: content))
                }
            }
        }
        
        messages.append(OpenAIRequest.OpenAIMessage(role: "user", content: userPrompt))
        
        let request = OpenAIRequest(
            model: "gpt-4o-mini",
            messages: messages,
            max_tokens: 300,
            temperature: 0.7
        )
        
        let callable = Functions.functions().httpsCallable("proxyOpenAIChat")
        let payload = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            ?? [:]
        
        let result = try await callable.call(dict)
        
        guard let responseData = try? JSONSerialization.data(withJSONObject: result.data) else {
            throw NSError(domain: "SimplifiedAIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw NSError(domain: "SimplifiedAIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No response content"])
        }
        
        return content
    }
    
    private func parseAIResponse(_ aiResponse: String) throws -> AIGeneratedTimer {
        var s = aiResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.firstIndex(of: "{"), let last = s.lastIndex(of: "}") { s = String(s[first...last]) }
        s = s.replacingOccurrences(of: "\u{feff}", with: "")
             .replacingOccurrences(of: "\u{201C}", with: "\"")  // left double quote
             .replacingOccurrences(of: "\u{201D}", with: "\"")  // right double quote
             .replacingOccurrences(of: "\u{2018}", with: "\"")  // left single quote
             .replacingOccurrences(of: "\u{2019}", with: "\"")  // right single quote
             .replacingOccurrences(of: "`", with: "")
        if let regex = try? NSRegularExpression(pattern: ",\\s*}", options: []) {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "}")
        }
        if let regex2 = try? NSRegularExpression(pattern: ",\\s*]", options: []) {
            let range2 = NSRange(location: 0, length: (s as NSString).length)
            s = regex2.stringByReplacingMatches(in: s, options: [], range: range2, withTemplate: "]")
        }
        guard let data = s.data(using: .utf8) else {
            throw NSError(domain: "SimplifiedAIService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }
        return try JSONDecoder().decode(AIGeneratedTimer.self, from: data)
    }
    
    private func convertToTimerResponse(_ aiTimer: AIGeneratedTimer) throws -> AITimerResponse {
        let backgroundSound = MeditationConfiguration.backgroundSound(forID: aiTimer.backgroundSoundId)
        
        // Look up binaural beat from BinauralBeatManager
        let binauralBeat: BinauralBeat?
        if let beatId = aiTimer.binauralBeatId, !beatId.isEmpty, beatId.lowercased() != "none" {
            binauralBeat = CatalogsManager.shared.beats.first(where: { $0.id == beatId })
            logger.aiChat("🧠 AI_DEBUG CONVERT binaural beat=\(binauralBeat?.id ?? "not found") from id=\(beatId)")
        } else {
            binauralBeat = nil
        }
        
        let cueSettings: [CueSetting] = aiTimer.cues.compactMap { aiCue in
            guard let cue = CatalogsManager.shared.cues.first(where: { $0.id == aiCue.id }) else { return nil }
            
            let triggerType: CueTriggerType
            let minute: Int?
            
            switch aiCue.trigger.lowercased() {
            case "start": triggerType = .start; minute = nil
            case "end": triggerType = .end; minute = nil
            default:
                if let minuteValue = Int(aiCue.trigger) {
                    triggerType = .minute; minute = minuteValue
                } else { return nil }
            }
            
            return CueSetting(triggerType: triggerType, minute: minute, cue: cue)
        }
        
        let meditationConfiguration = MeditationConfiguration(
            duration: aiTimer.duration,
            backgroundSound: backgroundSound,
            cueSettings: cueSettings,
            title: aiTimer.title,
            binauralBeat: binauralBeat
        )
        
        let deepLink = generateDeepLink(from: meditationConfiguration)
        
        return AITimerResponse(
            meditationConfiguration: meditationConfiguration,
            deepLink: deepLink,
            description: aiTimer.description ?? aiTimer.title
        )
    }

    private func applySecondsDurationPolicyIfNeeded(prompt: String, meditation: inout AIGeneratedTimer) {
        let lower = prompt.lowercased()
        if let match = try? NSRegularExpression(pattern: "\\b(\\d{1,3})\\s*(sec|secs|second|seconds|s)\\b", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: (lower as NSString).length)
            if let m = match.firstMatch(in: lower, options: [], range: range), m.numberOfRanges >= 2 {
                let numRange = m.range(at: 1)
                if let swiftRange = Range(numRange, in: lower) {
                    let numStr = String(lower[swiftRange])
                    if let seconds = Int(numStr), seconds > 0 {
                        let minutes = max(1, Int(round(Double(seconds) / 60.0)))
                        if meditation.duration != minutes {
                            meditation.duration = minutes
                            let note = "Note: timers use whole minutes. Requested \(seconds)s set to \(minutes)m."
                            if let existing = meditation.description, !existing.isEmpty {
                                meditation.description = existing + " " + note
                            } else {
                                meditation.description = note
                            }
                            logger.aiChat("🧠 AI_DEBUG SECONDS_POLICY \(seconds)s -> \(minutes)m")
                        }
                    }
                }
            }
        }
    }
    
    private func generateDeepLink(from configuration: MeditationConfiguration) -> URL {
        let baseURL = Config.oneLinkBaseURL
        var components = URLComponents(string: baseURL)
        
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":,"))
        let durValue = "\(configuration.duration)".addingPercentEncoding(withAllowedCharacters: allowed)
        let bsEncoded = configuration.backgroundSound.id.addingPercentEncoding(withAllowedCharacters: allowed)
        
        let cuRawValue = configuration.cueSettings.compactMap { cueSetting -> String? in
            let id = cueSetting.cue.id
            let trigger: String
            switch cueSetting.triggerType {
            case .start: trigger = "S"
            case .end: trigger = "E"
            case .minute: trigger = "\(cueSetting.minute ?? 0)"
            }
            return "\(id):\(trigger)"
        }.joined(separator: ",")
        
        let cuEncoded = cuRawValue.addingPercentEncoding(withAllowedCharacters: allowed)
        
        let bbId: String = {
            let mirror = Mirror(reflecting: configuration)
            if let beatChild = mirror.children.first(where: { $0.label == "binauralBeat" }) {
                let beatMirror = Mirror(reflecting: beatChild.value)
                if let id = beatMirror.children.first(where: { $0.label == "id" })?.value as? String {
                    return id
                }
            }
            return "None"
        }()
        let bbEncoded = bbId.addingPercentEncoding(withAllowedCharacters: allowed)
        
        // Use meditation title if available, otherwise generic name
        let meditationName = configuration.title ?? "AI Meditation"
        
        components?.queryItems = [
            URLQueryItem(name: "dur", value: durValue),
            URLQueryItem(name: "bs", value: bsEncoded),
            URLQueryItem(name: "bb", value: bbEncoded),
            URLQueryItem(name: "cu", value: cuEncoded),
            URLQueryItem(name: "c", value: "ai"),
            URLQueryItem(name: "af_sub1", value: meditationName)
        ]
        
        return components?.url ?? URL(string: baseURL)!
    }
}

// MARK: - Post-Practice Message Generation

extension SimplifiedAIService {
    func generatePolishedPostPracticeMessage(
        firstName: String?,
        durationMinutes: Int?,
        streak: Int,
        longestStreak: Int,
        isNewRecord: Bool,
        hrStartBPM: Int?,
        hrEndBPM: Int?,
        hrChangePercent: Double?,
        sessionContext: PostPracticePolishContext.SessionContext? = nil
    ) async throws -> String {
        let name = (firstName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }

        // Build streak message (~40-50 chars, include "streak" word)
        func buildStreakMessage(_ streak: Int, _ longest: Int, _ newRecord: Bool) -> String {
            if streak == 1 { return "Day 1 of your streak — keep going!" }
            if newRecord { return "New record! \(streak) day streak." }
            if streak == longest { return "\(streak) day streak — matches your best!" }
            let toRecord = max(0, longest - streak)
            if toRecord == 1 { return "\(streak) day streak — 1 more beats your record!" }
            return "\(streak) day streak — \(toRecord) more to beat your record."
        }
        
        // Build heart rate message (~40-50 chars, more human)
        func buildHRMessage(_ start: Int, _ end: Int, _ pct: Double) -> String? {
            guard start > 0 && end > 0 else { return "HR data unavailable." }
            let absPct = abs(pct)
            if absPct < 3.0 { return "HR stayed steady around \(start) BPM." }
            if pct < 0 && absPct >= 10.0 { return "HR dropped from \(start) to \(end). Nice!" }
            if pct < 0 { return "HR eased from \(start) to \(end) BPM." }
            return "HR rose from \(start) to \(end) BPM."
        }

        let streakText = buildStreakMessage(streak, longestStreak, isNewRecord)

        var hrLine: String? = nil
        if let s = hrStartBPM, let e = hrEndBPM, let pct = hrChangePercent {
            hrLine = buildHRMessage(s, e, pct)
        }

        // Build streak section
        let streakSection = "🔥 \(streakText)"
        
        // Build heart rate section if available
        let hrSection: String? = hrLine.map { "❤️ \($0)" }
        
        // Build session context description for the prompt
        let sessionContextText = buildSessionContextText(sessionContext)
        
        // Build praise instructions based on session type
        let praiseInstructions = buildPraiseInstructions(sessionContext: sessionContext)
        
        let systemPrompt = """
        You are Dojo's Sensei. Write a SHORT, HUMAN post-practice message with 2-3 sections separated by blank lines.
        
        SECTION 1 - PRAISE (required, MAX 50 CHARS):
        \(praiseInstructions)
        - ONE short sentence, ~40-50 chars max
        - If name provided, use it once
        - No emojis. Warm and natural.
        
        SECTION 2 - STREAK (required):
        - Rephrase STREAK_SECTION to sound natural, not robotic
        - MUST include the word "streak" 
        - Keep same info: days count, record info
        - ~40-50 chars, keep the 🔥 emoji at start
        
        SECTION 3 - HEART RATE (only if HR_SECTION provided):
        - Rephrase HR_SECTION to sound human and warm
        - Keep same numbers but vary wording
        - ~40-50 chars, keep the ❤️ emoji at start
        
        CRITICAL: Sound like a friendly coach, not a robot. Vary wording. Separate sections with ONE blank line.
        """

        var facts: [String] = []
        if let sessionText = sessionContextText { facts.append(sessionText) }
        if let n = name { facts.append("NAME: \(n)") }
        facts.append("STREAK_SECTION: \(streakSection)")
        if let hr = hrSection { facts.append("HR_SECTION: \(hr)") }
        let user = facts.joined(separator: "\n")

        do {
            let text = try await callOpenAI(userPrompt: user, systemPrompt: systemPrompt, conversationHistory: [])
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validate we got at least 2 sections (praise + streak)
            let sections = trimmed.components(separatedBy: "\n\n").filter { !$0.isEmpty }
            if sections.count >= 2 && trimmed.count <= 600 {
                return trimmed
            }
            logger.aiChat("📋 [POST_PRACTICE] POLISH_AI_INVALID sections=\(sections.count) len=\(trimmed.count)")
        } catch {
            logger.aiChat("📋 [POST_PRACTICE] POLISH_AI_ERROR \(error.localizedDescription)")
        }
        
        // Local fallback - build properly formatted sections with session context
        let praisePart = buildFallbackPraise(name: name, sessionContext: sessionContext)

        // Build sections array
        var sections: [String] = [praisePart, streakSection]
        if let hr = hrSection {
            sections.append(hr)
        }
        
        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Session Context Helpers
    
    private func buildSessionContextText(_ context: PostPracticePolishContext.SessionContext?) -> String? {
        guard let context = context else { return nil }
        
        switch context {
        case .path(let stepTitle, let stepOrder, let isPathComplete):
            if isPathComplete {
                return "SESSION_TYPE: PATH_COMPLETE (User just finished the entire Path learning journey!)"
            } else if let title = stepTitle, let order = stepOrder {
                return "SESSION_TYPE: PATH_STEP (Step \(order): \"\(title)\")"
            } else if let title = stepTitle {
                return "SESSION_TYPE: PATH_STEP (\"\(title)\")"
            } else {
                return "SESSION_TYPE: PATH_STEP"
            }
        case .explore(let meditationTitle):
            if let title = meditationTitle {
                return "SESSION_TYPE: EXPLORE_MEDITATION (\"\(title)\")"
            }
            return "SESSION_TYPE: EXPLORE_MEDITATION"
        case .custom(let title):
            if let title = title {
                return "SESSION_TYPE: CUSTOM_MEDITATION (\"\(title)\")"
            }
            return "SESSION_TYPE: CUSTOM_MEDITATION"
        }
    }
    
    private func buildPraiseInstructions(sessionContext: PostPracticePolishContext.SessionContext?) -> String {
        guard let context = sessionContext else {
            return "- Brief praise for completing practice"
        }
        
        switch context {
        case .path(let stepTitle, let stepOrder, let isPathComplete):
            if isPathComplete {
                return "- Celebrate completing the Path (still keep it short!)"
            } else if let title = stepTitle, let order = stepOrder {
                return "- Praise Step \(order): \"\(title)\" completion"
            } else if let title = stepTitle {
                return "- Praise \"\(title)\" completion"
            } else {
                return "- Praise Path step completion"
            }
        case .explore(let meditationTitle):
            if let title = meditationTitle {
                return "- Praise \"\(title)\" completion"
            }
            return "- Brief praise for meditation"
        case .custom(let title):
            if let title = title {
                return "- Praise \"\(title)\" completion"
            }
            return "- Brief praise for custom meditation"
        }
    }
    
    private func buildFallbackPraise(name: String?, sessionContext: PostPracticePolishContext.SessionContext?) -> String {
        // Handle session-specific fallback messages (keep SHORT ~40 chars)
        if let context = sessionContext {
            switch context {
            case .path(let stepTitle, let stepOrder, let isPathComplete):
                if isPathComplete {
                    if let n = name { return "\(n), Path complete!" }
                    return "Path complete!"
                }
                if let title = stepTitle, let order = stepOrder {
                    if let n = name { return "\(n), Step \(order) done." }
                    return "Step \(order): \(title) done."
                }
                if let title = stepTitle {
                    if let n = name { return "\(n), \"\(title)\" done." }
                    return "\"\(title)\" done."
                }
                if let n = name { return "\(n), step complete." }
                return "Step complete."
                
            case .explore(let meditationTitle):
                if let title = meditationTitle {
                    if let n = name { return "\(n), \"\(title)\" done." }
                    return "\"\(title)\" done."
                }
                // Fall through to generic
                
            case .custom(let title):
                if let title = title {
                    if let n = name { return "\(n), \"\(title)\" done." }
                    return "\"\(title)\" done."
                }
                // Fall through to generic
            }
        }
        
        // Generic fallback (keep SHORT)
        if let n = name { 
            return "\(n), nice practice."
        } else { 
            return "Nice practice."
        }
    }
}

// MARK: - Recommendation Intro Message Generation

extension SimplifiedAIService {
    
    /// Generates a short, AI-polished intro message for recommendation cards
    /// - Parameters:
    ///   - essence: The core intent of the message
    ///   - context: Variables for personalization
    /// - Returns: A short, human-feeling intro message (under 10 words)
    func generateIntroMessage(essence: MessageEssence, context: MessageContext) async throws -> String {
        // Build context JSON for the prompt
        var contextParts: [String] = []
        if let name = context.firstName { contextParts.append("name: \(name)") }
        if let step = context.stepNumber { contextParts.append("step: \(step)") }
        if let title = context.stepTitle { contextParts.append("stepTitle: \(title)") }
        if let completed = context.completedSteps { contextParts.append("completedSteps: \(completed)") }
        if let time = context.timeOfDay { contextParts.append("timeOfDay: \(time)") }
        if let session = context.sessionTitle { contextParts.append("sessionTitle: \(session)") }
        if let remaining = context.routinesRemaining { contextParts.append("routinesRemaining: \(remaining)") }
        if let dur = context.duration { contextParts.append("duration: \(dur)min") }
        if let seed = context.hurdlePromptSeed { contextParts.append("userChallenge: \(seed)") }
        
        let contextString = contextParts.isEmpty ? "none" : contextParts.joined(separator: ", ")
        
        let systemPrompt = """
        You write brief, friendly intro text for meditation app cards.
        
        RULES:
        - Keep it under \(essence.maxCharacters) characters (strict limit)
        - Aim for 5-10 words - not too short, not too long
        - Casual, warm tone - like texting a friend
        - NO overused words: journey, embrace, discover, essence, path (unless referring to app feature)
        - End with colon if introducing content
        - Vary phrasing - don't repeat same structure
        - Be helpful and specific, not generic or lazy
        
        TYPE: \(essence.rawValue)
        INTENT: \(essence.description)
        CONTEXT: \(contextString)
        
        Output ONLY the intro text, nothing else.
        """
        
        let userPrompt = "Generate the intro text now."
        
        logger.aiChat("🎯 REC_MSG_AI: Generating for \(essence.rawValue)")
        
        let response = try await callOpenAI(
            userPrompt: userPrompt,
            systemPrompt: systemPrompt,
            conversationHistory: []
        )
        
        // Clean up response
        var result = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove quotes if AI wrapped it
        if result.hasPrefix("\"") && result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        
        logger.aiChat("🎯 REC_MSG_AI: Result '\(result)' (\(result.count) chars)")
        
        return result
    }
}
