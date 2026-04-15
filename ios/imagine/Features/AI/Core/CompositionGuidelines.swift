//
//  CompositionGuidelines.swift
//  imagine
//
//  Created on 2025-01-12
//  Composition rules only - module catalog comes from CueManager (Firebase)
//  Bundled JSON (v4.3+) documents theme-driven INT_FRAC greetings and MV_* / EV_* focus modules for AI.
//

import Foundation

// MARK: - Main Guidelines Structure

struct CompositionGuidelines: Codable {
    let version: String
    let lastUpdated: String
    let description: String
    let moduleTypeClassifications: ModuleTypeClassifications
    let specialModules: SpecialModules
    let compositionAlgorithm: CompositionAlgorithm
    let sessionTemplates: SessionTemplatesContainer
    let triggerCueSelection: TriggerCueSelection?
    let sessionTypeRules: [String: SessionTypeRule]
    let strictRules: [StrictRule]
    let backgroundSoundGuidelines: BackgroundSoundGuidelines
    let jsonOutputFormat: JSONOutputFormat
    
    enum CodingKeys: String, CodingKey {
        case version
        case lastUpdated = "last_updated"
        case description
        case moduleTypeClassifications = "module_type_classifications"
        case specialModules = "special_modules"
        case compositionAlgorithm = "composition_algorithm"
        case sessionTemplates = "session_templates"
        case triggerCueSelection = "trigger_cue_selection"
        case sessionTypeRules = "session_type_rules"
        case strictRules = "strict_rules"
        case backgroundSoundGuidelines = "background_sound_guidelines"
        case jsonOutputFormat = "json_output_format"
    }
}

// MARK: - Module Type Classifications

struct ModuleTypeClassifications: Codable {
    let finiteExercise: ModuleTypeInfo
    let triggerCue: TriggerCueTypeInfo
    let instantCue: ModuleTypeInfo
    
    enum CodingKeys: String, CodingKey {
        case finiteExercise = "finite_exercise"
        case triggerCue = "trigger_cue"
        case instantCue = "instant_cue"
    }
}

struct ModuleTypeInfo: Codable {
    let description: String
    let timeAllocation: String
    let behavior: String
    let modules: [String]
    
    enum CodingKeys: String, CodingKey {
        case description
        case timeAllocation = "time_allocation"
        case behavior
        case modules
    }
}

struct TriggerCueTypeInfo: Codable {
    let description: String
    let timeAllocation: String
    let behavior: String
    let audioDurationNote: String?  // Duration loaded from cues_models.json via CueManager
    let modules: [String]
    
    enum CodingKeys: String, CodingKey {
        case description
        case timeAllocation = "time_allocation"
        case behavior
        case audioDurationNote = "audio_duration_note"
        case modules
    }
}

// MARK: - Special Modules (SI, GB positioning rules)

struct SpecialModules: Codable {
    let SI: SpecialModuleSI
    let GB: SpecialModuleGB
}

struct SpecialModuleSI: Codable {
    let position: String
    let required: Bool
    let duration: Int?
    let skipKeywords: [String]
    
    enum CodingKeys: String, CodingKey {
        case position, required, duration
        case skipKeywords = "skip_keywords"
    }
}

struct SpecialModuleGB: Codable {
    let position: String
    let skipFor: [String]
    
    enum CodingKeys: String, CodingKey {
        case position
        case skipFor = "skip_for"
    }
}

// MARK: - Composition Algorithm

struct CompositionAlgorithm: Codable {
    let description: String
    let targetFillPercentage: Int
    let phases: CompositionPhases?
    let steps: [AlgorithmStep]
    
    enum CodingKeys: String, CodingKey {
        case description
        case targetFillPercentage = "target_fill_percentage"
        case phases
        case steps
    }
}

struct CompositionPhases: Codable {
    let settleIn: PhaseInfo?
    let relaxation: RelaxationPhaseInfo?
    let focus: PhaseInfo?
    let visualization: VisualizationPhaseInfo?
    let closing: ClosingPhaseInfo?
    
    enum CodingKeys: String, CodingKey {
        case settleIn = "settle_in"
        case relaxation
        case focus
        case visualization
        case closing
    }
}

struct PhaseInfo: Codable {
    let range: String?
    let duration: Int?
    let modules: [String]?
    let required: Bool?
    let purpose: String?
    let preferred: String?
}

struct RelaxationPhaseInfo: Codable {
    let range: String?
    let modules: [String]?
    let split: RelaxationSplit?
    let purpose: String?
}

struct RelaxationSplit: Codable {
    let breathing: Double
    let bodyScan: Double
    
    enum CodingKeys: String, CodingKey {
        case breathing
        case bodyScan = "body_scan"
    }
}

struct VisualizationPhaseInfo: Codable {
    let range: String?
    let modules: [String]?
    let purpose: String?
    let preferredByTime: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case range, modules, purpose
        case preferredByTime = "preferred_by_time"
    }
}

struct ClosingPhaseInfo: Codable {
    let modules: [String]?
    let skipFor: [String]?
    
    enum CodingKeys: String, CodingKey {
        case modules
        case skipFor = "skip_for"
    }
}

struct AlgorithmStep: Codable {
    let step: Int
    let action: String
    let details: String
    let timeUsed: Int?
    let placement: String?
    
    enum CodingKeys: String, CodingKey {
        case step, action, details, placement
        case timeUsed = "time_used"
    }
}

// MARK: - Trigger Cue Selection

struct TriggerCueSelection: Codable {
    let focusPhase: TriggerCuePhaseSelection?
    let visualizationPhase: TriggerCuePhaseSelection?
    
    enum CodingKeys: String, CodingKey {
        case focusPhase = "focus_phase"
        case visualizationPhase = "visualization_phase"
    }
}

struct TriggerCuePhaseSelection: Codable {
    let defaultCue: String?
    let alternatives: [String]?
    let bySessionType: [String: String]?
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case defaultCue = "default"
        case alternatives
        case bySessionType = "by_session_type"
        case description
    }
}

// MARK: - Session Templates

struct SessionTemplatesContainer: Codable {
    let description: String
    let templates: [String: SessionTemplate]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var templates: [String: SessionTemplate] = [:]
        var desc = ""
        
        for key in container.allKeys {
            if key.stringValue == "description" {
                desc = try container.decode(String.self, forKey: key)
            } else {
                templates[key.stringValue] = try container.decode(SessionTemplate.self, forKey: key)
            }
        }
        
        self.description = desc
        self.templates = templates
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        try container.encode(description, forKey: DynamicCodingKeys(stringValue: "description")!)
        for (key, value) in templates {
            try container.encode(value, forKey: DynamicCodingKeys(stringValue: key)!)
        }
    }
    
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}

struct SessionTemplate: Codable {
    let composition: String
    let phases: String?
    let cues: [TemplateCue]
    let timeFilled: Int
    let percentageFilled: Int
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case composition, phases, cues, notes
        case timeFilled = "time_filled"
        case percentageFilled = "percentage_filled"
    }
}

struct TemplateCue: Codable {
    let id: String
    let trigger: String
}

// MARK: - Session Type Rules

struct SessionTypeRule: Codable {
    let keywords: [String]
    let rules: [String]
    let focusCue: String?
    let vizCue: String?
    let preferredSounds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case keywords, rules
        case focusCue = "focus_cue"
        case vizCue = "viz_cue"
        case preferredSounds = "preferred_sounds"
    }
}

// MARK: - Strict Rules

struct StrictRule: Codable {
    let id: String
    let rule: String
    let priority: Int
}

// MARK: - Background Sound Guidelines

struct BackgroundSoundGuidelines: Codable {
    let description: String
    let soundCategories: [String: [String]]
    let defaultBySessionType: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case description
        case soundCategories = "sound_categories"
        case defaultBySessionType = "default_by_session_type"
    }
}

// MARK: - JSON Output Format

struct JSONOutputFormat: Codable {
    let description: String
    let template: OutputTemplate
    let example: OutputExample
}

struct OutputTemplate: Codable {
    let duration: String
    let backgroundSoundId: String
    let binauralBeatId: String?
    let cues: [TemplateCue]
    let title: String
    let description: String
}

struct OutputExample: Codable {
    let duration: Int
    let backgroundSoundId: String
    let binauralBeatId: String?
    let cues: [TemplateCue]
    let title: String
    let description: String
}

// MARK: - Guidelines Loader

final class CompositionGuidelinesLoader {
    static let shared = CompositionGuidelinesLoader()
    
    private var cachedGuidelines: CompositionGuidelines?
    
    private init() {}
    
    /// Load guidelines from the app bundle
    func loadGuidelines() -> CompositionGuidelines? {
        if let cached = cachedGuidelines {
            return cached
        }
        
        guard let url = Bundle.main.url(forResource: "ai_composition_guidelines", withExtension: "json") else {
            logger.aiChatError("🧠 AI_DEBUG GUIDELINES: Failed to find ai_composition_guidelines.json in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let guidelines = try JSONDecoder().decode(CompositionGuidelines.self, from: data)
            cachedGuidelines = guidelines
            logger.aiChat("🧠 AI_DEBUG GUIDELINES: Loaded v\(guidelines.version)")
            return guidelines
        } catch {
            logger.aiChatError("🧠 AI_DEBUG GUIDELINES: Failed to decode - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Check if a module is a trigger cue (needs quiet span)
    func isTriggerCue(_ id: String) -> Bool {
        guard let guidelines = loadGuidelines() else {
            return false
        }
        return guidelines.moduleTypeClassifications.triggerCue.modules.contains(id)
    }
    
    /// Get session type from prompt keywords (with priority order)
    /// Prioritizes the actual "User request:" over profile context
    func detectSessionType(from prompt: String) -> String? {
        guard let guidelines = loadGuidelines() else { return nil }
        
        // Extract just the user request if present (ignore profile goals)
        let textToCheck: String
        if let range = prompt.range(of: "User request:", options: .caseInsensitive) {
            textToCheck = String(prompt[range.upperBound...]).lowercased()
        } else {
            textToCheck = prompt.lowercased()
        }
        
        // Priority order: specific emotional states first, then time-based, then general
        // This ensures "anxious about my meeting" is detected as "anxiety" not just ignored
        // and "relaxing evening" is detected as "evening" not "relaxation"
        let priorityOrder = [
            "sleep",      // Highest priority - sleep needs special handling (GB omitted unless user asks)
            "anxiety",    // Emotional states - specific needs
            "stress",     // Emotional states
            "gratitude",  // Specific practice type
            "creativity", // Specific practice type
            "energy",     // Goal-oriented
            "evening",    // Time-based
            "morning",    // Time-based
            "focus",      // General intent
            "relaxation"  // Most general (fallback-ish)
        ]
        
        for type in priorityOrder {
            if let rule = guidelines.sessionTypeRules[type] {
                if rule.keywords.contains(where: { textToCheck.contains($0) }) {
                    return type
                }
            }
        }
        return nil
    }
    
    /// Get the focus cue for a session type
    func focusCue(for sessionType: String) -> String? {
        guard let guidelines = loadGuidelines(),
              let rule = guidelines.sessionTypeRules[sessionType] else { return nil }
        return rule.focusCue
    }
    
    /// Get the visualization cue for a session type
    func vizCue(for sessionType: String) -> String? {
        guard let guidelines = loadGuidelines(),
              let rule = guidelines.sessionTypeRules[sessionType] else { return nil }
        return rule.vizCue
    }
    
    /// When true, prefer omitting GB (e.g. sleep keywords). AI sessions omit GB by default regardless; this only reflects guideline `skip_for` keywords.
    /// Prioritizes the actual "User request:" over profile context
    func shouldSkipGentleBell(prompt: String) -> Bool {
        // Extract just the user request if present (ignore profile goals like "Sleep better")
        let textToCheck: String
        if let range = prompt.range(of: "User request:", options: .caseInsensitive) {
            textToCheck = String(prompt[range.upperBound...]).lowercased()
        } else {
            textToCheck = prompt.lowercased()
        }
        
        guard let guidelines = loadGuidelines() else {
            return ["sleep", "bedtime", "night", "fall asleep"].contains(where: { textToCheck.contains($0) })
        }
        
        let skipFor = guidelines.specialModules.GB.skipFor
        return skipFor.contains(where: { textToCheck.contains($0) })
    }
    
    /// Get the template for a specific duration
    func template(for duration: Int) -> SessionTemplate? {
        guard let guidelines = loadGuidelines() else { return nil }
        return guidelines.sessionTemplates.templates["\(duration)min"]
    }
}

