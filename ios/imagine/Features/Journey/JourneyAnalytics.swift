//
//  JourneyAnalytics.swift
//  imagine
//
//  Created by Cursor on 1/14/26.
//
//  Analytics event definitions for the product journey.
//  Handles event routing to appropriate analytics partners:
//  - Mixpanel: journey_phase_entered and journey_phase_completed events
//  - AppsFlyer: af_level_achieved for marketing attribution (completions only)
//  - OneSignal: Tags for push notification segmentation
//

// =============================================================================
// JOURNEY ANALYTICS - EXPANSION GUIDE
// =============================================================================
//
// This file handles analytics for journey phase transitions.
// When adding new phases, NO CHANGES are needed here.
//
// The system automatically:
// - Gets phase_name from JourneyPhase.rawValue (stable identifier)
// - Gets phase_order from JourneyPhase.fullOrder (computed from allPhasesInOrder)
// - Sends to Mixpanel (both events), AppsFlyer (completions only), and OneSignal
//
// EVENTS:
// - journey_phase_entered: Fires when user enters a phase (for funnel analysis)
// - journey_phase_completed: Fires when user completes a phase (also triggers entry)
//
// TRIGGERS for phase_entered:
// - "new_user": First app launch
// - "phase_completion": Just completed previous phase
// - "journey_reset": Journey was reset
// - "dev_mode": Dev mode jump
// - "app_upgrade": Existing user after analytics upgrade
//
// To add a new phase, see instructions in JourneyPhase.swift
// =============================================================================

import Foundation

// MARK: - Debug Logging

private let ANALYTICS_TAG = "📊 JOURNEY:"

/// Log journey analytics messages (only in DEBUG builds)
private func journeyLog(_ message: String) {
    #if DEBUG
    print("\(ANALYTICS_TAG) \(message)")
    #endif
}

// MARK: - Journey Analytics

/// Handles analytics events related to the user's product journey.
/// Sends phase completion events to Mixpanel, AppsFlyer, and OneSignal.
struct JourneyAnalytics {
    
    // MARK: - Phase Entry Tracking
    
    /// Check if entry event has been logged for a phase.
    /// Used to prevent duplicate entry events when user returns to a phase.
    static func hasLoggedEntry(for phase: JourneyPhase) -> Bool {
        let loggedPhases = SharedUserStorage.retrieve(forKey: .loggedPhaseEntries, as: [String].self) ?? []
        return loggedPhases.contains(phase.rawValue)
    }
    
    /// Mark entry event as logged for a phase.
    /// Called after successfully logging an entry event.
    private static func markEntryLogged(for phase: JourneyPhase) {
        var loggedPhases = SharedUserStorage.retrieve(forKey: .loggedPhaseEntries, as: [String].self) ?? []
        if !loggedPhases.contains(phase.rawValue) {
            loggedPhases.append(phase.rawValue)
            SharedUserStorage.save(value: loggedPhases, forKey: .loggedPhaseEntries)
            journeyLog("   ✅ Marked entry logged for \(phase.displayName)")
        }
    }
    
    /// Reset entry tracking when journey is reset.
    /// - Parameter includePreAppPhases: If true, clears all phases. If false, keeps pre-app phases.
    static func resetEntryTracking(includePreAppPhases: Bool) {
        if includePreAppPhases {
            SharedUserStorage.delete(forKey: .loggedPhaseEntries)
            journeyLog("🔄 Reset ALL phase entry tracking")
        } else {
            // Keep pre-app phases, clear in-app phases only
            var loggedPhases = SharedUserStorage.retrieve(forKey: .loggedPhaseEntries, as: [String].self) ?? []
            loggedPhases = loggedPhases.filter { phaseName in
                guard let phase = JourneyPhase(rawValue: phaseName) else { return false }
                return phase.isPreAppPhase
            }
            SharedUserStorage.save(value: loggedPhases, forKey: .loggedPhaseEntries)
            journeyLog("🔄 Reset in-app phase entry tracking (kept pre-app phases)")
        }
    }
    
    // MARK: - Phase Completion Event
    
    /// Log when user completes a journey phase and moves to the next one.
    /// This is the primary journey analytics event.
    ///
    /// Sends to:
    /// - Mixpanel: `journey_phase_completed` with full properties including `journey_track`
    /// - AppsFlyer: `af_level_achieved` for marketing attribution
    /// - OneSignal: Updates `journey_phase` and `journey_phase_order` tags
    ///
    /// - Parameters:
    ///   - phase: The phase that was just completed
    ///   - nextPhase: The phase the user is entering
    static func logPhaseCompleted(phase: JourneyPhase, nextPhase: JourneyPhase) {
        // journey_track distinguishes the two product tracks for Mixpanel cohort analysis.
        // "learning" = dont_know_start users who went through the structured course.
        // "personalized" = all other users who went directly to hurdle-targeted meditations.
        let journeyTrack = UserPreferencesManager.shared.hurdle == "dont_know_start" ? "learning" : "personalized"
        
        journeyLog("════════════════════════════════════════════════════════════")
        journeyLog("🎉 PHASE COMPLETED: \(phase.displayName) (order=\(phase.fullOrder))")
        journeyLog("   → ENTERING: \(nextPhase.displayName) (order=\(nextPhase.fullOrder))")
        journeyLog("   journey_track: \(journeyTrack)")
        journeyLog("────────────────────────────────────────────────────────────")
        
        // Build parameters for Mixpanel (full properties)
        let params: [String: Any] = [
            "phase_name": phase.analyticsName,
            "phase_order": phase.fullOrder,
            "next_phase_name": nextPhase.analyticsName,
            "next_phase_order": nextPhase.fullOrder,
            "journey_track": journeyTrack,
            "timestamp": Date()
        ]
        
        // 1. MIXPANEL - Full event with stable identifiers
        journeyLog("📤 MIXPANEL: journey_phase_completed")
        journeyLog("   phase_name: \(phase.analyticsName)")
        journeyLog("   phase_order: \(phase.fullOrder)")
        journeyLog("   next_phase_name: \(nextPhase.analyticsName)")
        journeyLog("   next_phase_order: \(nextPhase.fullOrder)")
        journeyLog("   journey_track: \(journeyTrack)")
        AnalyticsManager.shared.logEvent("journey_phase_completed", parameters: params)
        
        // 2. APPSFLYER - Standard af_level_achieved event
        journeyLog("📤 APPSFLYER: af_level_achieved")
        journeyLog("   af_level: \(phase.fullOrder)")
        journeyLog("   af_content_id: \(phase.analyticsName)")
        journeyLog("   af_description: \(phase.displayName)")
        AppsFlyerManager.shared.logLevelAchieved(
            level: phase.fullOrder,
            contentId: phase.analyticsName,
            description: phase.displayName
        )
        
        // 3. ONESIGNAL - Update tags for push segmentation
        journeyLog("📤 ONESIGNAL: Updating tags")
        journeyLog("   journey_phase: \(nextPhase.rawValue)")
        journeyLog("   journey_phase_order: \(nextPhase.fullOrder)")
        Task { @MainActor in
            pushService.setTag(key: "journey_phase", value: nextPhase.rawValue)
            pushService.setTag(key: "journey_phase_order", value: String(nextPhase.fullOrder))
        }
        
        journeyLog("════════════════════════════════════════════════════════════")
        
        // 4. Log entry to the next phase (for funnel analysis)
        logPhaseEntered(phase: nextPhase, trigger: "phase_completion")
    }
    
    // MARK: - Phase Entry Event
    
    /// Log when user enters a journey phase.
    /// Used for funnel analysis - tracks the start of each phase.
    ///
    /// Automatically prevents duplicate entry events using per-phase tracking.
    /// Duplicates are allowed for special triggers: journey_reset and dev_mode.
    ///
    /// Sends to:
    /// - Mixpanel: `journey_phase_entered` with phase info, trigger, and `journey_track`
    /// - AppsFlyer: NOT sent (entry is not a conversion event)
    /// - OneSignal: NOT sent (tags updated separately)
    ///
    /// - Parameters:
    ///   - phase: The phase being entered
    ///   - trigger: What caused the phase entry (new_user, phase_completion, journey_reset, dev_mode)
    static func logPhaseEntered(phase: JourneyPhase, trigger: String) {
        // journey_track distinguishes the two product tracks for cohort analysis.
        let journeyTrack = UserPreferencesManager.shared.hurdle == "dont_know_start" ? "learning" : "personalized"
        
        journeyLog("────────────────────────────────────────────────────────────")
        journeyLog("🚪 PHASE ENTERED: \(phase.displayName) (order=\(phase.fullOrder))")
        journeyLog("   trigger: \(trigger)")
        journeyLog("   journey_track: \(journeyTrack)")
        
        // Check if already logged (prevent duplicates)
        // Allow duplicates for journey_reset and dev_mode triggers
        let allowDuplicate = trigger == "journey_reset" || trigger == "dev_mode"
        if hasLoggedEntry(for: phase) && !allowDuplicate {
            journeyLog("   ⏭️ Skipping duplicate entry event for \(phase.displayName)")
            journeyLog("────────────────────────────────────────────────────────────")
            return
        }
        
        let params: [String: Any] = [
            "phase_name": phase.analyticsName,
            "phase_order": phase.fullOrder,
            "trigger": trigger,
            "journey_track": journeyTrack,
            "timestamp": Date()
        ]
        
        // Mixpanel only - entry is for funnel analysis, not marketing attribution
        journeyLog("📤 MIXPANEL: journey_phase_entered")
        journeyLog("   phase_name: \(phase.analyticsName)")
        journeyLog("   phase_order: \(phase.fullOrder)")
        journeyLog("   trigger: \(trigger)")
        journeyLog("   journey_track: \(journeyTrack)")
        AnalyticsManager.shared.logEvent("journey_phase_entered", parameters: params)
        
        // Mark this phase's entry as logged
        // Skip for dev_mode/journey_reset to avoid polluting real user tracking
        if trigger != "dev_mode" && trigger != "journey_reset" {
            markEntryLogged(for: phase)
        } else {
            journeyLog("   ℹ️ Skipping markEntryLogged (trigger=\(trigger))")
        }
        
        journeyLog("────────────────────────────────────────────────────────────")
    }
    
    // MARK: - Session Milestone Funnel
    
    /// Log a session completion milestone (session 1, 2, or 3).
    ///
    /// Fires once per milestone, guarded by SharedUserStorage to prevent duplicates.
    ///
    /// Sends to:
    /// - Mixpanel: `journey_session_milestone` with session_number
    /// - AppsFlyer: `af_level_achieved` for marketing attribution
    /// - OneSignal: `sessions_completed` tag for push segmentation
    ///
    /// - Parameter sessionNumber: The total session count (only 1, 2, 3 trigger milestones)
    static func logSessionMilestone(_ sessionNumber: Int) {
        // Only fire for milestones 1-3
        guard sessionNumber >= 1 && sessionNumber <= 3 else { return }
        
        // Prevent duplicate fires (same pattern as phase entry tracking)
        var loggedMilestones = SharedUserStorage.retrieve(forKey: .loggedSessionMilestones, as: [Int].self) ?? []
        guard !loggedMilestones.contains(sessionNumber) else {
            journeyLog("[SESSION_MILESTONE] ⏭️ Skipping duplicate milestone for session_number=\(sessionNumber)")
            return
        }
        
        // journey_track is included so session milestones can be broken down by track
        // in Mixpanel funnels, matching the pattern on journey_phase_entered/completed.
        let journeyTrack = UserPreferencesManager.shared.hurdle == "dont_know_start" ? "learning" : "personalized"
        
        journeyLog("[SESSION_MILESTONE] ════════════════════════════════")
        journeyLog("[SESSION_MILESTONE] 🎯 session_number=\(sessionNumber) journey_track=\(journeyTrack)")
        
        let params: [String: Any] = [
            "session_number": sessionNumber,
            "journey_track": journeyTrack,
            "timestamp": Date()
        ]
        
        // 1. MIXPANEL
        journeyLog("[SESSION_MILESTONE] → Mixpanel: journey_session_milestone session_number=\(sessionNumber) journey_track=\(journeyTrack)")
        AnalyticsManager.shared.logEvent("journey_session_milestone", parameters: params)
        
        // 2. APPSFLYER
        journeyLog("[SESSION_MILESTONE] → AppsFlyer: af_level_achieved level=\(sessionNumber)")
        AppsFlyerManager.shared.logLevelAchieved(
            level: sessionNumber,
            contentId: "session_\(sessionNumber)",
            description: "Session \(sessionNumber) completed"
        )
        
        // 3. ONESIGNAL tag (for push segmentation by activation depth)
        journeyLog("[SESSION_MILESTONE] → OneSignal tag: sessions_completed=\(sessionNumber)")
        Task { @MainActor in
            pushService.setTag(key: "sessions_completed", value: String(sessionNumber))
        }
        
        journeyLog("[SESSION_MILESTONE] ════════════════════════════════")
        
        // Mark as logged so it never fires again for this milestone
        loggedMilestones.append(sessionNumber)
        SharedUserStorage.save(value: loggedMilestones, forKey: .loggedSessionMilestones)
    }
    
    // MARK: - First Session Started
    
    /// Log when user starts their first meditation session.
    /// Fires once, guarded by SharedUserStorage, to support funnel analysis (start vs complete).
    ///
    /// Sends to Mixpanel: `journey_first_session_started` with journey_phase, journey_track, session_id.
    static func logFirstSessionStarted(sessionId: String?) {
        guard !(SharedUserStorage.retrieve(forKey: .loggedFirstSessionStarted, as: Bool.self) ?? false) else {
            journeyLog("[FIRST_SESSION] ⏭️ Skipping duplicate journey_first_session_started")
            return
        }
        
        let journeyTrack = UserPreferencesManager.shared.hurdle == "dont_know_start" ? "learning" : "personalized"
        let phaseName = SessionContextManager.shared.cachedJourneyPhaseName ?? JourneyPhase.path.analyticsName
        
        var params: [String: Any] = [
            "journey_phase": phaseName,
            "journey_track": journeyTrack,
            "timestamp": Date()
        ]
        if let sessionId = sessionId {
            params["session_id"] = sessionId
        }
        
        journeyLog("[FIRST_SESSION] ════════════════════════════════")
        journeyLog("[FIRST_SESSION] 🚀 journey_first_session_started journey_phase=\(phaseName) journey_track=\(journeyTrack)")
        AnalyticsManager.shared.logEvent("journey_first_session_started", parameters: params)
        journeyLog("[FIRST_SESSION] ════════════════════════════════")
        
        SharedUserStorage.save(value: true, forKey: .loggedFirstSessionStarted)
    }
    
    // MARK: - OneSignal Tag Management
    
    /// Update the journey phase tag in OneSignal.
    /// Called when phase changes for push notification segmentation.
    @MainActor
    static func updateOneSignalPhaseTag(_ phase: JourneyPhase) {
        journeyLog("📤 ONESIGNAL: Tag update -> journey_phase=\(phase.rawValue), order=\(phase.fullOrder)")
        pushService.setTag(key: "journey_phase", value: phase.rawValue)
        pushService.setTag(key: "journey_phase_order", value: String(phase.fullOrder))
    }
    
    /// Initialize journey tags for a new user.
    /// Called during onboarding or first launch.
    @MainActor
    static func initializeTagsForNewUser() {
        let firstPhase = JourneyPhase.firstPhase
        journeyLog("📤 ONESIGNAL: Init new user tags -> journey_phase=\(firstPhase.rawValue), order=\(firstPhase.fullOrder)")
        pushService.setTag(key: "journey_phase", value: firstPhase.rawValue)
        pushService.setTag(key: "journey_phase_order", value: String(firstPhase.fullOrder))
    }
}
