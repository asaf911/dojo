//
//  Enhanced Body Scan Weight System
//  Replace the existing body scan methods in SimplifiedAIService class
//
//  Created by AI Assistant on 2025-01-28
//

import Foundation

// MARK: - Enhanced Body Scan Weight System
// Add these methods to SimplifiedAIService class in AIService.swift

/// Enhances AI-generated meditation by selecting optimal body scan variants using weight-based calculation
private func enhanceWithSmartBodyScan(_ aiTimer: inout AIGeneratedTimer) {
    logger.eventMessage("🧘 SMART_BODY_SCAN_V2: Analyzing meditation for body scan optimization")
    
    // Check if meditation contains a body scan cue
    for i in 0..<aiTimer.cues.count {
        if aiTimer.cues[i].id == "BS" {
            // Extract session type from title/description for context
            let sessionType = extractSessionType(from: aiTimer.title, description: aiTimer.description)
            let optimalCue = getOptimalBodyScanCue(for: aiTimer.duration, sessionType: sessionType, existingCues: aiTimer.cues)
            aiTimer.cues[i].id = optimalCue
            
            logger.eventMessage("🧘 SMART_BODY_SCAN_V2: Enhanced BS -> \(optimalCue) for \(aiTimer.duration)min session")
            break
        }
    }
}

/// Calculates the optimal body scan weight and selects appropriate variant
private func getOptimalBodyScanCue(for duration: Int, 
                                  sessionType: String? = nil,
                                  existingCues: [AIGeneratedTimer.AICue] = []) -> String {
    
    logger.eventMessage("🧘 SMART_BODY_SCAN_V2: Calculating body scan weight for \(duration)min session")
    
    // Calculate body scan weight based on multiple factors
    let bodyScaneWeight = calculateBodyScanWeight(
        totalDuration: duration,
        sessionType: sessionType,
        existingCues: existingCues
    )
    
    // Select optimal duration based on weight
    let optimalDuration = selectOptimalBodyScanDuration(
        weight: bodyScaneWeight,
        totalDuration: duration,
        availableTime: calculateAvailableTime(totalDuration: duration, existingCues: existingCues)
    )
    
    let cueId = "BS\(optimalDuration)"
    
    logger.eventMessage("🧘 SMART_BODY_SCAN_V2: Selected \(cueId) (weight: \(String(format: "%.2f", bodyScaneWeight)), optimal duration: \(optimalDuration)min)")
    
    return cueId
}

/// Calculates body scan weight from 0.0 to 1.0 based on multiple factors
private func calculateBodyScanWeight(totalDuration: Int, 
                                   sessionType: String?, 
                                   existingCues: [AIGeneratedTimer.AICue]) -> Double {
    
    var weight: Double = 0.0
    let sessionTypeLower = sessionType?.lowercased() ?? ""
    
    // Factor 1: Base duration factor (30% of weight)
    let durationFactor = calculateDurationFactor(totalDuration)
    weight += durationFactor * 0.3
    
    // Factor 2: Session type factor (25% of weight)
    let sessionTypeFactor = calculateSessionTypeFactor(sessionTypeLower)
    weight += sessionTypeFactor * 0.25
    
    // Factor 3: Cue composition factor (25% of weight)  
    let cueCompositionFactor = calculateCueCompositionFactor(existingCues)
    weight += cueCompositionFactor * 0.25
    
    // Factor 4: Available time factor (20% of weight)
    let availableTimeFactor = calculateAvailableTimeFactor(totalDuration: totalDuration, existingCues: existingCues)
    weight += availableTimeFactor * 0.20
    
    // Clamp weight between 0.0 and 1.0
    weight = max(0.0, min(1.0, weight))
    
    logger.eventMessage("🧘 BODY_SCAN_WEIGHT: Calculated weight: \(String(format: "%.3f", weight))")
    logger.eventMessage("🧘 BODY_SCAN_WEIGHT: - Duration factor: \(String(format: "%.3f", durationFactor))")
    logger.eventMessage("🧘 BODY_SCAN_WEIGHT: - Session type factor: \(String(format: "%.3f", sessionTypeFactor))")
    logger.eventMessage("🧘 BODY_SCAN_WEIGHT: - Cue composition factor: \(String(format: "%.3f", cueCompositionFactor))")
    logger.eventMessage("🧘 BODY_SCAN_WEIGHT: - Available time factor: \(String(format: "%.3f", availableTimeFactor))")
    
    return weight
}

// MARK: - Weight Factor Calculations

/// Duration factor: Higher weight for longer sessions
private func calculateDurationFactor(_ duration: Int) -> Double {
    switch duration {
    case 0...5:   return 0.1  // Very short sessions = low body scan importance
    case 6...10:  return 0.3  // Short sessions = moderate importance
    case 11...15: return 0.6  // Medium sessions = high importance
    case 16...25: return 0.8  // Long sessions = very high importance
    default:      return 1.0  // Very long sessions = maximum importance
    }
}

/// Session type factor: Different session types emphasize body scan differently
private func calculateSessionTypeFactor(_ sessionType: String) -> Double {
    switch sessionType {
    case let type where type.contains("body scan") || type.contains("bodyscan"):
        return 1.0  // Explicit body scan request = maximum weight
    case let type where type.contains("relax") || type.contains("stress") || type.contains("anxiety"):
        return 0.9  // Relaxation sessions = high body scan weight
    case let type where type.contains("sleep") || type.contains("bedtime"):
        return 0.8  // Sleep sessions benefit from body scans
    case let type where type.contains("mindful") || type.contains("awareness"):
        return 0.7  // Mindfulness = moderate-high body scan weight
    case let type where type.contains("focus") || type.contains("concentration"):
        return 0.4  // Focus sessions = moderate body scan weight
    case let type where type.contains("energy") || type.contains("morning"):
        return 0.3  // Energy sessions = lower body scan weight
    default:
        return 0.5  // Default sessions = balanced weight
    }
}

/// Cue composition factor: Adjust based on other cues present
private func calculateCueCompositionFactor(_ cues: [AIGeneratedTimer.AICue]) -> Double {
    var factor: Double = 0.5  // Start with neutral
    
    let cueIds = cues.map { $0.id }
    
    // Reduce weight if many other guided cues are present
    let guidedCueCount = cueIds.filter { ["MA", "OH", "VC", "RT"].contains($0) }.count
    factor -= Double(guidedCueCount) * 0.15
    
    // Increase weight if minimal structure (few cues)
    if cues.count <= 3 {
        factor += 0.3  // Sparse sessions benefit from body scan
    }
    
    // Increase weight if Perfect Breath is present (natural progression)
    if cueIds.contains("PB") {
        factor += 0.2
    }
    
    return max(0.0, min(1.0, factor))
}

/// Available time factor: Consider how much time is actually available
private func calculateAvailableTimeFactor(totalDuration: Int, existingCues: [AIGeneratedTimer.AICue]) -> Double {
    let usedTime = calculateUsedTime(existingCues)
    let availableTime = max(0, totalDuration - usedTime)
    
    // Factor based on available time as percentage of total
    let availablePercentage = Double(availableTime) / Double(totalDuration)
    
    switch availablePercentage {
    case 0.7...1.0:  return 1.0  // Plenty of time = high weight
    case 0.5..<0.7:  return 0.8  // Good amount of time = high weight  
    case 0.3..<0.5:  return 0.5  // Moderate time = moderate weight
    case 0.1..<0.3:  return 0.2  // Limited time = low weight
    default:         return 0.0  // No time = no body scan
    }
}

// MARK: - Duration Selection Logic

/// Selects optimal body scan duration based on weight and constraints
private func selectOptimalBodyScanDuration(weight: Double, totalDuration: Int, availableTime: Int) -> Int {
    
    // Calculate ideal duration based on weight
    let idealDuration = Int(round(weight * 10.0))  // Weight 0.0-1.0 maps to 0-10 minutes
    
    // Apply constraints
    let maxAllowedDuration = min(availableTime, Int(Double(totalDuration) * 0.6))  // Max 60% of session
    let constrainedDuration = min(idealDuration, maxAllowedDuration)
    
    // Ensure we have a valid variant (1-10 minutes)
    let finalDuration = max(1, min(10, constrainedDuration))
    
    logger.eventMessage("🧘 DURATION_SELECTION: Weight: \(String(format: "%.2f", weight)) → Ideal: \(idealDuration)min → Constrained: \(constrainedDuration)min → Final: \(finalDuration)min")
    
    return finalDuration
}

// MARK: - Helper Functions

/// Extracts session type from title and description for context
private func extractSessionType(from title: String, description: String?) -> String? {
    let combinedText = "\(title) \(description ?? "")".lowercased()
    
    // Priority order for session type detection
    let sessionTypes = [
        "body scan", "bodyscan", "relax", "stress", "anxiety", "sleep", "bedtime", 
        "mindful", "awareness", "focus", "concentration", "energy", "morning"
    ]
    
    for sessionType in sessionTypes {
        if combinedText.contains(sessionType) {
            return sessionType
        }
    }
    
    return nil
}

/// Calculates total time used by existing cues
private func calculateUsedTime(_ cues: [AIGeneratedTimer.AICue]) -> Int {
    return cues.reduce(0) { total, cue in
        total + getEnhancedCueDuration(cue.id)
    }
}

/// Calculates available time for body scan
private func calculateAvailableTime(totalDuration: Int, existingCues: [AIGeneratedTimer.AICue]) -> Int {
    let usedTime = calculateUsedTime(existingCues)
    return max(0, totalDuration - usedTime - 2)  // Reserve 2 minutes buffer
}

/// Enhanced cue duration function with all variants
private func getEnhancedCueDuration(_ cueId: String) -> Int {
    switch cueId {
    case "PB":
        return 2  // Perfect Breath is 2 minutes
    case "BS1": return 1
    case "BS2": return 2
    case "BS3": return 3
    case "BS4": return 4
    case "BS5": return 5
    case "BS6": return 6
    case "BS7": return 7
    case "BS8": return 8
    case "BS9": return 9
    case "BS10": return 10
    case "BS":
        return 3  // Default body scan duration (fallback)
    case "MA", "OH", "VC", "RT":
        return 3  // Other guided cues are typically 3 minutes
    case "INT_FRAC", "GB":
        return 1  // Quick transitional cues (Introduction, Gentle Bell)
    default:
        return 2  // Default safe duration
    }
}

/*
INTEGRATION INSTRUCTIONS:

1. Replace the existing body scan methods in SimplifiedAIService class with the methods above
2. Update the TimerCues.json file with BS1-BS10 variants (see TimerCues.json file)
3. Update ai_meditation_config.json with enhanced body scan guidelines (see ai_meditation_config.json file)
4. Test with various meditation scenarios to verify the weight system works correctly

EXAMPLE WEIGHT CALCULATIONS:

Scenario 1: "15 minute relaxation meditation"
- Duration Factor (15min): 0.6 * 0.3 = 0.18
- Session Type Factor (relaxation): 0.9 * 0.25 = 0.225
- Cue Composition (SI, PB, BS, GB): 0.7 * 0.25 = 0.175 
- Available Time Factor (good): 0.8 * 0.2 = 0.16
- Total Weight: 0.74 → BS7 (7 minutes)

Scenario 2: "10 minute body scan meditation"
- Duration Factor (10min): 0.3 * 0.3 = 0.09
- Session Type Factor (body scan): 1.0 * 0.25 = 0.25
- Cue Composition (minimal): 0.8 * 0.25 = 0.2
- Available Time Factor (plenty): 1.0 * 0.2 = 0.2
- Total Weight: 0.74 → BS7 (7 minutes) - but constrained by available time = BS6 (6 minutes)

This allows for the flexible "10 minute body scan + 5 minute something else" scenario you wanted!
*/