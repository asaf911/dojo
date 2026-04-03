//
//  ExploreRecommendationManager.swift
//  imagine
//
//  Created by Cursor on 1/13/26.
//
//  Phase-specific handler for the Daily Routines phase of the user's product journey.
//  This manager handles time-based pre-recorded session recommendations (morning/noon/evening/night).
//
//  Architecture:
//  - ProductJourneyManager: Orchestrates phase transitions and recommendation routing
//  - PathProgressManager: Handles Path-specific logic for JourneyPhase.path
//  - ExploreRecommendationManager (this file): Handles Daily Routines for JourneyPhase.dailyRoutines
//
//  Leverages AppFunctions for audio file loading (dynamic from server).
//

import Foundation
import Combine

/// Phase-specific handler for the Daily Routines phase of the product journey.
/// Manages time-based pre-recorded session recommendations (morning/noon/evening/night).
/// Leverages AppFunctions for audio file loading (dynamic from server).
@MainActor
class ExploreRecommendationManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ExploreRecommendationManager()
    
    // MARK: - Published State
    
    @Published private(set) var allAudioFiles: [AudioFile] = []
    @Published private(set) var timeOrientedSessions: [AudioFile] = []
    @Published var refreshTrigger: UUID = UUID()
    
    // MARK: - Tag Configuration (case-insensitive matching)
    
    /// Tags that indicate time-of-day sessions
    /// These are matched case-insensitively against AudioFile.tags
    private let timeBasedTags: Set<String> = ["morning", "noon", "evening", "sleep"]
    
    /// Categories to include for recommendations (routines has daily sessions)
    private let recommendableCategories: Set<AudioCategory> = [.routines]
    
    // MARK: - Time-to-Tag Mapping
    
    enum TimeOfDay: String {
        case morning    // 5:00 - 11:59
        case noon       // 12:00 - 16:59
        case evening    // 17:00 - 20:59
        case night      // 21:00 - 4:59
        
        static func current() -> TimeOfDay {
            let devModeEnabled = SharedUserStorage.retrieve(forKey: .devModeEnabled, as: Bool.self) ?? false
            if devModeEnabled,
               let overrideRawValue = SharedUserStorage.retrieve(forKey: .devTimelySlotOverride, as: String.self),
               let override = TimeOfDay(rawValue: overrideRawValue) {
                logger.aiChat("🧠 AI_DEBUG [JOURNEY] TimeOfDay override active: \(override.slotName)")
                return override
            }

            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12: return .morning
            case 12..<17: return .noon
            case 17..<21: return .evening
            default: return .night // 21-23, 0-4
            }
        }
        
        /// Tags that match this time of day
        var matchingTags: [String] {
            switch self {
            case .morning: return ["morning"]
            case .noon: return ["noon"]
            case .evening: return ["evening", "sleep"] // Evening can include wind-down sessions
            case .night: return ["sleep"]
            }
        }
        
        /// Friendly name for messages
        var displayName: String {
            switch self {
            case .morning: return "morning"
            case .noon: return "midday"
            case .evening: return "evening"
            case .night: return "night"
            }
        }
        
        /// Slot name for storage key (e.g., "morning", "noon", "evening", "night")
        var slotName: String {
            return rawValue
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] ExploreRecommendationManager initialized")
        // Initial load - will use cache if available
        loadAudioFiles()
    }
    
    // MARK: - Loading State
    
    /// Tracks whether initial load is complete
    @Published private(set) var isLoaded: Bool = false
    
    // MARK: - Public Methods
    
    /// Loads audio files using AppFunctions (leverages existing caching/refresh)
    func loadAudioFiles(forceFetch: Bool = false) {
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_LOAD] loading audio files forceFetch=\(forceFetch) isLoaded=\(isLoaded)")
        
        AppFunctions.loadAudioFiles(forceFetch: forceFetch) { [weak self] files in
            Task { @MainActor in
                guard let self = self else { return }
                self.allAudioFiles = files
                self.updateTimeOrientedSessions()
                self.isLoaded = true
                self.refreshTrigger = UUID()
                logger.aiChat("🧠 AI_DEBUG [EXPLORE_LOAD] ✅ loaded \(files.count) audio files, \(self.timeOrientedSessions.count) time-oriented, isLoaded=true")
            }
        }
    }
    
    /// Loads audio files with a completion callback - use this when you need to wait for loading
    func loadAudioFilesWithCompletion(forceFetch: Bool = false, completion: @escaping () -> Void) {
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_LOAD] loading audio files WITH COMPLETION forceFetch=\(forceFetch)")
        
        // If already loaded and not forcing refresh, call completion immediately
        if isLoaded && !forceFetch && !timeOrientedSessions.isEmpty {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_LOAD] ✅ already loaded - calling completion immediately")
            completion()
            return
        }
        
        AppFunctions.loadAudioFiles(forceFetch: forceFetch) { [weak self] files in
            Task { @MainActor in
                guard let self = self else {
                    completion()
                    return
                }
                self.allAudioFiles = files
                self.updateTimeOrientedSessions()
                self.isLoaded = true
                self.refreshTrigger = UUID()
                logger.aiChat("🧠 AI_DEBUG [EXPLORE_LOAD] ✅ loaded \(files.count) audio files, \(self.timeOrientedSessions.count) time-oriented - calling completion")
                completion()
            }
        }
    }
    
    /// Check if explore recommendation should be shown
    /// Returns true when time-oriented sessions exist and the user is eligible:
    /// - dont_know_start users: must have completed all Path steps first
    /// - All other users: skip directly to explore (no path prerequisite)
    func shouldRecommendExplore() -> Bool {
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] shouldRecommendExplore() checking conditions...")
        
        // dont_know_start users must complete the Path before accessing Explore.
        // All other users bypass this gate — they were routed here directly from onboarding.
        let isPathUser = UserPreferencesManager.shared.hurdle == "dont_know_start"
        if isPathUser && !PathProgressManager.shared.allStepsCompleted {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE] shouldRecommend=false (path user, path not complete, completed=\(PathProgressManager.shared.completedStepCount)/\(PathProgressManager.shared.totalStepCount))")
            return false
        }
        
        // Must have onboarding complete
        guard SenseiOnboardingState.shared.isComplete else {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE] shouldRecommend=false (onboarding incomplete)")
            return false
        }
        
        // Must have time-oriented sessions available
        guard !timeOrientedSessions.isEmpty else {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE] shouldRecommend=false (no time sessions available)")
            return false
        }
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE] shouldRecommend=true (path complete, \(timeOrientedSessions.count) sessions available)")
        return true
    }
    
    /// Get the best session based on current time of day, optionally biased toward the user's hurdle.
    ///
    /// Selection order:
    /// 1. Sessions matching both the current time-of-day tags AND the hurdle's audio tags (most targeted)
    /// 2. Fallback: Sessions matching time-of-day only — suppressed when requireHurdleMatch is true
    /// 3. Final fallback: Any time-oriented session (last resort) — also suppressed when requireHurdleMatch is true
    ///
    /// - Parameters:
    ///   - excludedIds: Content IDs to exclude from selection (avoids consecutive repeats)
    ///   - hurdleContext: Optional hurdle context from HurdleRecommendationContext for tag-biased selection
    ///   - requireHurdleMatch: When true, returns nil if no hurdle+time intersection exists.
    ///     Used by buildPersonalizedRecommendation to detect "no hurdle match" and route to Custom as primary.
    func getTimeAppropriateSession(
        excluding excludedIds: Set<String> = [],
        hurdleContext: HurdleRecommendationContext? = nil,
        requireHurdleMatch: Bool = false
    ) -> AudioFile? {
        let timeOfDay = TimeOfDay.current()
        let matchingTags = timeOfDay.matchingTags
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] time=\(timeOfDay.displayName) matchingTags=\(matchingTags) hurdle=\(hurdleContext?.hurdleId ?? "nil") requireHurdle=\(requireHurdleMatch) excluding=\(excludedIds.count) ids")
        
        // Filter sessions that have any matching time tag
        let timeMatchingSessions = timeOrientedSessions.filter { session in
            let sessionTagsLower = session.tags.map { $0.lowercased() }
            return matchingTags.contains { tag in sessionTagsLower.contains(tag) }
        }
        
        // Step 1: If hurdle context has audio tags, try to find sessions matching
        // both time-of-day AND hurdle tags (most personalized)
        if let hurdleContext = hurdleContext, !hurdleContext.audioTags.isEmpty {
            let hurdleTags = hurdleContext.audioTags.map { $0.lowercased() }
            let hurdleMatches = timeMatchingSessions.filter { session in
                let sessionTagsLower = session.tags.map { $0.lowercased() }
                return hurdleTags.contains { tag in sessionTagsLower.contains(tag) }
            }
            let hurdleEligible = hurdleMatches.filter { !excludedIds.contains($0.id) }
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] hurdle=\(hurdleContext.hurdleId) hurdleCandidates=\(hurdleMatches.count) timeCandidates=\(timeMatchingSessions.count) hurdleEligible=\(hurdleEligible.count)")
            
            if let session = hurdleEligible.randomElement() {
                logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] ✅ hurdle-targeted selection: session=\(session.id) title=\(session.title)")
                return session
            }
            
            // No hurdle match found. When requireHurdleMatch is true, return nil immediately
            // so the caller knows to route to Custom as primary instead of a generic session.
            if requireHurdleMatch {
                logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] requireHurdleMatch=true and no hurdle match — returning nil for Custom routing")
                return nil
            }
            
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] No hurdle-matched sessions found, falling back to time-only selection")
        } else if requireHurdleMatch {
            // requireHurdleMatch requested but no hurdle context available — return nil
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] requireHurdleMatch=true but no hurdleContext — returning nil for Custom routing")
            return nil
        }
        
        // Step 2: Time-only selection (standard behavior, not reached when requireHurdleMatch=true)
        let eligible = timeMatchingSessions.filter { !excludedIds.contains($0.id) }
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] time-only: found \(timeMatchingSessions.count) matching, \(eligible.count) eligible after exclusions")
        
        if let session = eligible.randomElement() {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] ✅ time-only selection: session=\(session.id) title=\(session.title) premium=\(session.premium)")
            return session
        }
        
        // All matching sessions were excluded — return nil so caller can fall back to custom
        if !timeMatchingSessions.isEmpty {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] all \(timeMatchingSessions.count) matching sessions excluded — caller should fall back to custom")
            return nil
        }
        
        // Step 3: Final fallback — any time-oriented session not excluded
        let fallbackEligible = timeOrientedSessions.filter { !excludedIds.contains($0.id) }
        if let fallbackSession = fallbackEligible.randomElement() {
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] fallback to any session=\(fallbackSession.id) title=\(fallbackSession.title)")
            return fallbackSession
        }
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_SELECT] no session found")
        return nil
    }
    
    /// Get all sessions matching current time of day (for variety)
    func getAllTimeAppropriateSessions() -> [AudioFile] {
        let timeOfDay = TimeOfDay.current()
        let matchingTags = timeOfDay.matchingTags
        
        return timeOrientedSessions.filter { session in
            let sessionTagsLower = session.tags.map { $0.lowercased() }
            return matchingTags.contains { tag in
                sessionTagsLower.contains(tag)
            }
        }
    }
    
    /// Get recommendation message for the session (primary recommendation)
    /// - Note: This is a synchronous fallback. For AI-polished messages, use RecommendationMessageService.generateExplorePrimary()
    func getRecommendationMessage(for session: AudioFile) -> String {
        let timeOfDay = TimeOfDay.current()
        let tagsLower = session.tags.map { $0.lowercased() }
        
        if tagsLower.contains("morning") {
            return "Here's a great way to start your \(timeOfDay.displayName):"
        } else if tagsLower.contains("noon") {
            return "This is a great \(timeOfDay.displayName) reset:"
        } else if tagsLower.contains("evening") {
            return "Here's a nice way to wind down your day:"
        } else if tagsLower.contains("sleep") {
            return "This will help you relax and prepare for rest:"
        } else {
            return "Here's a session for you:"
        }
    }
    
    /// Get secondary recommendation message for the session
    /// These are designed to work with "Or" prefix and form grammatically correct sentences
    /// - Note: This is a synchronous fallback. For AI-polished messages, use RecommendationMessageService.generateExploreSecondary()
    @available(*, deprecated, message: "Use RecommendationMessageService.generateExploreSecondary for AI-polished messages")
    func getSecondaryRecommendationMessage(for session: AudioFile) -> String {
        let timeOfDay = TimeOfDay.current()
        let tagsLower = session.tags.map { $0.lowercased() }
        
        if tagsLower.contains("morning") {
            return "Or you can start your \(timeOfDay.displayName) with this:"
        } else if tagsLower.contains("noon") {
            return "Or try this \(timeOfDay.displayName) reset:"
        } else if tagsLower.contains("evening") {
            return "Or wind down your day with this:"
        } else if tagsLower.contains("sleep") {
            return "Or try this to help you relax:"
        } else {
            return "Or try this session:"
        }
    }
    
    /// Get the current time of day display name
    func getCurrentTimeOfDayName() -> String {
        return TimeOfDay.current().displayName
    }
    
    // MARK: - Slot-Based Auto-Suggestion (One per time slot per day)
    
    /// Get current slot key for storage (e.g., "2026-01-14_morning")
    func getCurrentSlotKey() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let slotName = TimeOfDay.current().slotName
        return "\(dateString)_\(slotName)"
    }
    
    /// Check if the current slot was already used for a timely launch suggestion.
    /// Falls back to the legacy key for one release window.
    func hasTimelySlotSuggestedForCurrentSlot() -> Bool {
        hasSuggestedForCurrentSlot(
            key: .lastTimelyLaunchSuggestedSlot,
            fallbackToLegacyKey: true
        )
    }

    /// Check if the current slot was already used for non-timely auto suggestions.
    /// Falls back to the legacy key for one release window.
    func hasNonTimelySlotSuggestedForCurrentSlot() -> Bool {
        hasSuggestedForCurrentSlot(
            key: .lastNonTimelyAutoSuggestedSlot,
            fallbackToLegacyKey: true
        )
    }

    /// Check if the current slot has already received a timely launch suggestion.
    func shouldAutoSuggestTimelyNow() -> Bool {
        if hasTimelySlotSuggestedForCurrentSlot() {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Timely auto-suggest: NO (already suggested for \(TimeOfDay.current().slotName) today)")
            return false
        }

        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Timely auto-suggest: YES (first \(TimeOfDay.current().slotName) timely suggestion today)")
        return true
    }

    /// Check if the current slot has already received a non-timely auto suggestion.
    func shouldAutoSuggestNonTimelyNow() -> Bool {
        if hasNonTimelySlotSuggestedForCurrentSlot() {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Non-timely auto-suggest: NO (already suggested for \(TimeOfDay.current().slotName) today)")
            return false
        }

        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Non-timely auto-suggest: YES (first \(TimeOfDay.current().slotName) non-timely suggestion today)")
        return true
    }

    /// Mark the current slot as consumed by a timely launch suggestion.
    func markTimelySlotAsSuggested() {
        let slotKey = getCurrentSlotKey()
        SharedUserStorage.save(value: slotKey, forKey: .lastTimelyLaunchSuggestedSlot)
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Timely slot marked as suggested: \(slotKey)")
    }

    /// Mark the current slot as consumed by a non-timely auto suggestion.
    func markNonTimelySlotAsSuggested() {
        let slotKey = getCurrentSlotKey()
        SharedUserStorage.save(value: slotKey, forKey: .lastNonTimelyAutoSuggestedSlot)
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Non-timely slot marked as suggested: \(slotKey)")
    }
    
    /// Main check: Should we auto-suggest a routine right now?
    /// Returns true only if:
    /// 1. Path is complete (shouldRecommendExplore conditions)
    /// 2. Haven't auto-suggested for this time slot today
    func shouldAutoSuggestNow() -> Bool {
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] shouldAutoSuggestNow() checking...")
        
        // First check basic explore conditions
        guard shouldRecommendExplore() else {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Auto-suggest: NO (explore conditions not met)")
            return false
        }
        
        // Check if already suggested for this time slot by a non-timely flow.
        if hasNonTimelySlotSuggestedForCurrentSlot() {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Auto-suggest: NO (non-timely slot already suggested for \(TimeOfDay.current().slotName) today)")
            return false
        }
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Auto-suggest: YES (first \(TimeOfDay.current().slotName) suggestion today)")
        return true
    }
    
    /// Reset slot suggestion state (for dev mode testing)
    func resetSlotSuggestion() {
        SharedUserStorage.delete(forKey: .lastTimelyLaunchSuggestedSlot)
        SharedUserStorage.delete(forKey: .lastNonTimelyAutoSuggestedSlot)
        SharedUserStorage.delete(forKey: .lastAutoSuggestedSlot)
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Slot suggestion state reset (timely + non-timely + legacy)")
    }
    
    /// Get the last non-timely suggested slot key (for debugging/dev mode)
    func getLastSuggestedSlot() -> String? {
        return SharedUserStorage.retrieve(forKey: .lastNonTimelyAutoSuggestedSlot, as: String.self)
    }
    
    // MARK: - Customization Phase (Auto-Generated Meditations)
    
    /// Check if we should auto-generate a custom meditation for this slot
    /// Simpler check than shouldAutoSuggestNow() - only checks slot, not explore conditions.
    /// This is a legacy non-timely path and intentionally uses the non-timely slot key.
    func shouldAutoSuggestCustomNow() -> Bool {
        shouldAutoSuggestNonTimelyNow()
    }
    
    /// Get the auto-prompt for custom meditation based on time of day
    func getTimeBasedCustomPrompt() -> String {
        let timeOfDay = TimeOfDay.current()
        
        let prompt: String
        switch timeOfDay {
        case .morning:
            prompt = "Create a 10-minute morning meditation to start my day with clarity and positive energy"
        case .noon:
            prompt = "Create a 10-minute midday meditation to reset my focus and release tension"
        case .evening:
            prompt = "Create a 10-minute evening meditation to unwind and reflect on my day"
        case .night:
            prompt = "Create a 10-minute sleep meditation to quiet my mind for restful sleep"
        }
        
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Custom prompt for \(timeOfDay.displayName): \(prompt)")
        return prompt
    }
    
    // MARK: - Private Methods
    
    /// Filters all audio files to find time-oriented sessions
    private func updateTimeOrientedSessions() {
        let previousCount = timeOrientedSessions.count
        
        timeOrientedSessions = allAudioFiles.filter { audioFile in
            // Must be in recommendable category (routines)
            guard recommendableCategories.contains(audioFile.category) else {
                return false
            }
            
            // Must have at least one time-based tag
            let tagsLower = audioFile.tags.map { $0.lowercased() }
            return tagsLower.contains { tag in
                timeBasedTags.contains(tag)
            }
        }
        
        logger.aiChat("🧠 AI_DEBUG [EXPLORE_FILTER] filtered \(timeOrientedSessions.count) time-oriented from \(allAudioFiles.count) total (was \(previousCount))")
        
        // Log the filtered sessions for debugging
        for session in timeOrientedSessions {
            let tags = session.tags.joined(separator: ", ")
            logger.aiChat("🧠 AI_DEBUG [EXPLORE_FILTER] session=\(session.id) title=\(session.title) tags=[\(tags)] premium=\(session.premium)")
        }
    }

    // MARK: - Legacy Compatibility Wrappers

    /// Legacy wrapper retained for call-site compatibility.
    /// Uses non-timely slot tracking.
    func hasAutoSuggestedForCurrentSlot() -> Bool {
        hasNonTimelySlotSuggestedForCurrentSlot()
    }

    /// Legacy wrapper retained for call-site compatibility.
    /// Uses non-timely slot tracking.
    func markCurrentSlotAsSuggested() {
        markNonTimelySlotAsSuggested()
    }

    // MARK: - Private Helpers

    private func hasSuggestedForCurrentSlot(
        key: UserStorageKey,
        fallbackToLegacyKey: Bool
    ) -> Bool {
        let currentSlotKey = getCurrentSlotKey()

        if let lastSlot = SharedUserStorage.retrieve(forKey: key, as: String.self) {
            let hasAlreadySuggested = lastSlot == currentSlotKey
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Slot check key=\(key.rawValue) current=\(currentSlotKey) last=\(lastSlot) alreadySuggested=\(hasAlreadySuggested)")
            return hasAlreadySuggested
        }

        guard fallbackToLegacyKey,
              let legacySlot = SharedUserStorage.retrieve(forKey: .lastAutoSuggestedSlot, as: String.self) else {
            logger.aiChat("🧠 AI_DEBUG [JOURNEY] Slot check key=\(key.rawValue) current=\(currentSlotKey) last=none alreadySuggested=false")
            return false
        }

        let hasAlreadySuggested = legacySlot == currentSlotKey
        logger.aiChat("🧠 AI_DEBUG [JOURNEY] Slot check legacy fallback key=\(key.rawValue) current=\(currentSlotKey) legacy=\(legacySlot) alreadySuggested=\(hasAlreadySuggested)")
        return hasAlreadySuggested
    }
}
