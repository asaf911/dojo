// MARK: - Cue Overlap Prevention Functions
// Add these to SimplifiedAIService class in AIService.swift

/// Prevents cue overlaps by adjusting timing based on cue durations
private func preventCueOverlaps(_ aiTimer: inout AIGeneratedTimer) {
    logger.eventMessage("🔧 OVERLAP_PREVENTION: Starting overlap analysis for \(aiTimer.cues.count) cues")
    
    // Sort cues by trigger time to process chronologically
    var cuesWithTiming: [(cue: AIGeneratedCue, minute: Int)] = []
    
    for aiCue in aiTimer.cues {
        if let minute = getMinuteFromTrigger(aiCue.trigger) {
            cuesWithTiming.append((cue: aiCue, minute: minute))
        }
    }
    
    // Sort by minute
    cuesWithTiming.sort { $0.minute < $1.minute }
    
    // Track end times and adjust overlaps
    var adjustedCues: [AIGeneratedCue] = []
    var lastEndTime = 0
    
    for cueWithTiming in cuesWithTiming {
        var cue = cueWithTiming.cue
        var proposedStart = cueWithTiming.minute
        let cueDuration = getCueDuration(cue.id)
        
        // Check for overlap with previous cue
        if proposedStart < lastEndTime {
            let originalStart = proposedStart
            proposedStart = lastEndTime + 1 // Start 1 minute after previous cue ends
            
            logger.eventMessage("🔧 OVERLAP_PREVENTION: Cue \(cue.id) moved from minute \(originalStart) to minute \(proposedStart) to avoid overlap")
            
            // Update the trigger
            cue.trigger = "\(proposedStart)"
        }
        
        // Update last end time
        lastEndTime = proposedStart + cueDuration
        
        // Make sure we don't exceed meditation duration
        if lastEndTime > aiTimer.duration {
            logger.eventMessage("🔧 OVERLAP_PREVENTION: Cue \(cue.id) would extend beyond meditation duration, adjusting...")
            
            // Try to place it earlier if possible
            let maxStartTime = aiTimer.duration - cueDuration
            if maxStartTime >= 0 {
                proposedStart = min(proposedStart, maxStartTime)
                cue.trigger = "\(proposedStart)"
                lastEndTime = proposedStart + cueDuration
                logger.eventMessage("🔧 OVERLAP_PREVENTION: Cue \(cue.id) adjusted to start at minute \(proposedStart)")
            } else {
                // Skip this cue if it can't fit
                logger.eventMessage("🔧 OVERLAP_PREVENTION: Cue \(cue.id) removed - cannot fit in meditation duration")
                continue
            }
        }
        
        adjustedCues.append(cue)
    }
    
    // Add back any non-timed cues (start/end)
    for aiCue in aiTimer.cues {
        if getMinuteFromTrigger(aiCue.trigger) == nil {
            adjustedCues.append(aiCue)
        }
    }
    
    aiTimer.cues = adjustedCues
    logger.eventMessage("🔧 OVERLAP_PREVENTION: Overlap prevention completed. Final cue count: \(adjustedCues.count)")
}

/// Extracts minute value from trigger string, returns nil for "start"/"end"
private func getMinuteFromTrigger(_ trigger: String) -> Int? {
    if trigger.lowercased() == "start" || trigger.lowercased() == "end" {
        return nil
    }
    return Int(trigger)
}

/// Returns the duration in minutes for different cue types
private func getCueDuration(_ cueId: String) -> Int {
    // Prefer dynamic durations from catalogs/rules when available
    if let d = CatalogsManager.shared.bodyScanDurations[cueId] { return max(1, d) }
    // Fallbacks for legacy ids
    switch cueId {
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
        return 3
    case "MA", "OH", "VC", "RT":
        return 3
    case "INT_GEN_1", "GB":
        return 1
    default:
        return 2
    }
}