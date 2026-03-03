//
//  PathProgressManager.swift
//  imagine
//
//  Created by Asaf Shamir on 1/7/26.
//
//  Phase-specific handler for the Path phase of the user's product journey.
//  This manager handles Path step data and completion tracking.
//
//  Architecture:
//  - ProductJourneyManager: Orchestrates phase transitions and recommendation routing
//  - PathProgressManager (this file): Handles Path-specific logic for JourneyPhase.path
//  - ExploreRecommendationManager: Handles Daily Routines for JourneyPhase.dailyRoutines
//
//  This is the single source of truth for:
//  - All path steps (fetched from Firestore)
//  - User's completion status (via PracticeManager)
//  - Next recommended step
//  - Overall progress metrics
//

import Foundation
import Combine

// MARK: - Path Step State

/// Represents the current state of a path step for a user
enum PathStepState {
    case next       // Available to play (next in sequence)
    case completed  // Already completed
    case locked     // Not yet unlocked (prerequisites not met)
}

// MARK: - Path Progress Manager

/// Unified manager for path steps and user progress.
/// This is the single source of truth for:
/// - All path steps (fetched from Firestore)
/// - User's completion status (via PracticeManager)
/// - Next recommended step
/// - Overall progress metrics
@MainActor
class PathProgressManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = PathProgressManager()
    
    // MARK: - Published State
    
    /// All path steps (sorted by order)
    @Published private(set) var pathSteps: [PathStep] = []
    
    /// The next step the user should complete
    @Published private(set) var nextStep: PathStep?
    
    /// Whether all steps have been completed
    @Published private(set) var allStepsCompleted: Bool = false
    
    /// Number of completed steps
    @Published private(set) var completedStepCount: Int = 0
    
    /// Whether path steps have been loaded from Firestore
    /// Used by AI chat to re-check recommendations when steps become available
    @Published private(set) var isLoaded: Bool = false
    
    /// Trigger for forcing UI refresh
    @Published var refreshTrigger: UUID = UUID()
    
    // MARK: - Forced Completion State (for Dev Mode Skip)
    
    /// UserDefaults key for forced path completion flag
    private static let forcedCompletionKey = "path_forced_all_steps_completed"
    
    /// Check if path completion has been forced (dev mode skip)
    private var isForcedComplete: Bool {
        let value = UserDefaults.standard.bool(forKey: Self.forcedCompletionKey)
        return value
    }
    
    /// Debug helper to log forced completion state
    private func logForcedState(_ context: String) {
        #if DEBUG
        let forcedValue = UserDefaults.standard.bool(forKey: Self.forcedCompletionKey)
        print("📊 JOURNEY: [DEV_SKIP] \(context) - isForcedComplete=\(forcedValue), allStepsCompleted=\(allStepsCompleted), pathSteps.count=\(pathSteps.count), isLoaded=\(isLoaded)")
        #endif
    }
    
    // MARK: - Computed Properties
    
    /// Total number of path steps (excluding "coming soon" placeholder)
    var totalStepCount: Int {
        pathSteps.filter { !$0.id.hasPrefix("coming_soon_") }.count
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progressPercentage: Double {
        guard totalStepCount > 0 else { return 0 }
        return Double(completedStepCount) / Double(totalStepCount)
    }
    
    /// Whether the user has started the path (completed at least one step)
    var hasStartedPath: Bool {
        completedStepCount > 0
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var hasInitializedOneSignalTags = false
    
    // MARK: - Initialization
    
    private init() {
        // Load path steps on init
        loadPathSteps()
        
        // Listen for practice completion notifications to refresh progress
        NotificationCenter.default.publisher(for: .practiceCompletedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProgress()
            }
            .store(in: &cancellables)
        
        // Listen for path step completion at 95% threshold
        NotificationCenter.default.publisher(for: .pathStepCompletedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProgress()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Load path steps from Firestore
    func loadPathSteps() {
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS loadPathSteps() called")
        FirestoreManager.shared.fetchPathSteps { [weak self] response in
            guard let self = self,
                  let steps = response?.steps else {
                logger.errorMessage("PathProgressManager: Failed to load path steps")
                logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS loadPathSteps() FAILED - no steps returned")
                return
            }
            
            Task { @MainActor in
                self.pathSteps = steps.sorted(by: { $0.order < $1.order })
                self.updateProgress()
                self.initializeOneSignalPathTags()
                self.refreshTrigger = UUID()
                
                // Mark as loaded - triggers AI chat to re-check recommendations
                let wasLoaded = self.isLoaded
                self.isLoaded = true
                
                logger.eventMessage("PathProgressManager: Loaded \(steps.count) path steps")
                logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS loadPathSteps() SUCCESS - \(steps.count) steps loaded, nextStep=\(self.nextStep?.id ?? "nil")")
                
                #if DEBUG
                if !wasLoaded {
                    print("📊 JOURNEY: [PATH_STEPS_READY] Path steps loaded (\(steps.count) steps), nextStep=\(self.nextStep?.id ?? "nil")")
                }
                #endif
            }
        }
    }
    
    /// Refresh progress state (call after a step is completed)
    func refreshProgress() {
        print("🧹 PATH_CLEAR [PathProgressManager]: refreshProgress() called")
        print("🧹 PATH_CLEAR [PathProgressManager]: BEFORE - pathSteps=\(pathSteps.count), completedCount=\(completedStepCount), nextStep=\(nextStep?.id ?? "nil")")
        
        updateProgress()
        refreshTrigger = UUID()
        
        print("🧹 PATH_CLEAR [PathProgressManager]: AFTER - pathSteps=\(pathSteps.count), completedCount=\(completedStepCount), nextStep=\(nextStep?.id ?? "nil")")
        logger.eventMessage("PathProgressManager: Progress refreshed")
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS refreshProgress() - nextStep=\(nextStep?.id ?? "nil") allCompleted=\(allStepsCompleted)")
    }
    
    /// Force mark all path steps as completed (used by dev mode skip)
    /// This sets a persistent flag that ensures allStepsCompleted returns true
    /// even if path steps haven't been loaded from Firestore yet.
    func forceMarkAllStepsCompleted() {
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
        print("📊 JOURNEY: [DEV_SKIP] forceMarkAllStepsCompleted() CALLED")
        print("📊 JOURNEY: [DEV_SKIP] BEFORE:")
        print("📊 JOURNEY: [DEV_SKIP]   - pathSteps.count: \(pathSteps.count)")
        print("📊 JOURNEY: [DEV_SKIP]   - isLoaded: \(isLoaded)")
        print("📊 JOURNEY: [DEV_SKIP]   - allStepsCompleted: \(allStepsCompleted)")
        print("📊 JOURNEY: [DEV_SKIP]   - completedStepCount: \(completedStepCount)")
        print("📊 JOURNEY: [DEV_SKIP]   - isForcedComplete (UserDefaults): \(UserDefaults.standard.bool(forKey: Self.forcedCompletionKey))")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS forceMarkAllStepsCompleted() called")
        
        // Set the forced completion flag in UserDefaults
        UserDefaults.standard.set(true, forKey: Self.forcedCompletionKey)
        UserDefaults.standard.synchronize() // Force immediate write
        
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] Set forced completion flag in UserDefaults")
        print("📊 JOURNEY: [DEV_SKIP] Verified flag value: \(UserDefaults.standard.bool(forKey: Self.forcedCompletionKey))")
        #endif
        
        // Also mark any loaded steps as completed
        let actualSteps = pathSteps.filter { !$0.id.hasPrefix("coming_soon_") }
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] Marking \(actualSteps.count) loaded steps as completed...")
        #endif
        for step in actualSteps {
            PracticeManager.shared.markPracticeAsCompleted(practiceID: step.id)
        }
        
        // Update state immediately
        allStepsCompleted = true
        nextStep = nil
        completedStepCount = actualSteps.count
        refreshTrigger = UUID()
        
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] AFTER:")
        print("📊 JOURNEY: [DEV_SKIP]   - allStepsCompleted: \(allStepsCompleted)")
        print("📊 JOURNEY: [DEV_SKIP]   - completedStepCount: \(completedStepCount)")
        print("📊 JOURNEY: [DEV_SKIP]   - nextStep: \(nextStep?.id ?? "nil")")
        print("📊 JOURNEY: [DEV_SKIP] forceMarkAllStepsCompleted() COMPLETE ✅")
        print("📊 JOURNEY: [DEV_SKIP] ═══════════════════════════════════════════════════")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS forceMarkAllStepsCompleted() - allStepsCompleted=true (forced)")
    }
    
    /// Reset the forced completion flag (used when resetting the journey)
    func resetForcedCompletion() {
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] resetForcedCompletion() called")
        print("📊 JOURNEY: [DEV_SKIP] BEFORE: isForcedComplete=\(UserDefaults.standard.bool(forKey: Self.forcedCompletionKey))")
        #endif
        
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS resetForcedCompletion() called")
        UserDefaults.standard.removeObject(forKey: Self.forcedCompletionKey)
        UserDefaults.standard.synchronize() // Force immediate write
        
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] AFTER: isForcedComplete=\(UserDefaults.standard.bool(forKey: Self.forcedCompletionKey))")
        #endif
    }
    
    /// Get the state of a specific step
    func getStepState(for step: PathStep) -> PathStepState {
        // Handle "coming soon" system step - always locked
        if step.id.hasPrefix("coming_soon_") {
            return .locked
        }
        
        // If this step is completed, return .completed
        if isStepCompleted(step.id) {
            return .completed
        }
        
        // Sort steps by order
        let sortedSteps = pathSteps.sorted(by: { $0.order < $1.order })
        
        // First step is always available
        if step.order == 1 {
            return .next
        }
        
        // Find the previous steps
        let previousSteps = sortedSteps.filter { $0.order < step.order }
        
        // If all previous steps are completed, this step is next
        if !previousSteps.isEmpty && previousSteps.allSatisfy({ isStepCompleted($0.id) }) {
            return .next
        }
        
        // Otherwise, the step is locked
        return .locked
    }
    
    /// Check if a step is completed (delegates to PracticeManager)
    func isStepCompleted(_ stepId: String) -> Bool {
        PracticeManager.shared.isPracticeCompleted(practiceID: stepId)
    }
    
    /// Get all completed steps
    func getCompletedSteps() -> [PathStep] {
        pathSteps.filter { isStepCompleted($0.id) }
    }
    
    /// Check if path recommendation should be shown in AI chat
    func shouldRecommendPath() -> Bool {
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS shouldRecommendPath() checking conditions...")
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS pathSteps.count=\(pathSteps.count) allStepsCompleted=\(allStepsCompleted) nextStep=\(nextStep?.id ?? "nil") onboardingComplete=\(SenseiOnboardingState.shared.isComplete)")
        
        // Don't recommend if all steps are completed
        guard !allStepsCompleted else {
            logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS shouldRecommendPath=false (all steps completed)")
            return false
        }
        
        // Don't recommend if no next step available
        guard nextStep != nil else {
            logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS shouldRecommendPath=false (no next step)")
            return false
        }
        
        // Don't recommend during onboarding
        guard SenseiOnboardingState.shared.isComplete else {
            logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS shouldRecommendPath=false (onboarding not complete)")
            return false
        }
        
        logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS shouldRecommendPath=true")
        return true
    }
    
    /// Get the personalized welcome greeting for the first step only
    /// Returns nil for non-first steps
    /// - Note: This is a synchronous fallback. For AI-polished messages, use RecommendationMessageService.generatePathWelcome()
    func getWelcomeGreeting() -> String? {
        guard let step = nextStep, step.order == 1 else { return nil }
        
        let firstName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)?
            .split(separator: " ").first.map(String.init)
        
        return firstName.map { "Welcome \($0)," } ?? "Welcome traveler,"
    }
    
    /// Get the recommendation message for the current next step
    /// - Note: This is a synchronous fallback. For AI-polished messages, use RecommendationMessageService.generatePathIntro()
    func getRecommendationMessage() -> String? {
        guard let step = nextStep else { return nil }
        
        if step.order == 1 {
            // Shorter intro for first step (welcome is shown separately with custom styling)
            return "I'm Sensei. Here's your first step on the Path to build your practice."
        } else {
            return "Ready to continue your meditation journey? Here's your next step on the Path:"
        }
    }
    
    /// Update path progress tags for analytics (called externally)
    func updatePathProgressTags() {
        PathAnalyticsHandler.shared.updateCurrentPathStateTags()
    }
    
    // MARK: - Private Methods
    
    /// Update all progress-related state
    private func updateProgress() {
        #if DEBUG
        let forcedValue = UserDefaults.standard.bool(forKey: Self.forcedCompletionKey)
        print("📊 JOURNEY: [DEV_SKIP] updateProgress() checking forced flag: \(forcedValue)")
        #endif
        
        // Check if completion was forced via dev mode skip
        // This takes precedence over actual completion state to handle race conditions
        // where path steps haven't loaded yet when the skip was triggered
        if isForcedComplete {
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] ✅ FORCED COMPLETION ACTIVE in updateProgress()")
            print("📊 JOURNEY: [DEV_SKIP] Setting allStepsCompleted=true, nextStep=nil")
            #endif
            
            logger.aiChat("🧠 AI_DEBUG PATH_PROGRESS updateProgress() - forced completion active")
            allStepsCompleted = true
            nextStep = nil
            // Set completed count to total steps if available, otherwise use current count
            let actualSteps = pathSteps.filter { !$0.id.hasPrefix("coming_soon_") }
            completedStepCount = actualSteps.isEmpty ? completedStepCount : actualSteps.count
            
            #if DEBUG
            print("📊 JOURNEY: [DEV_SKIP] completedStepCount=\(completedStepCount), pathSteps.count=\(pathSteps.count)")
            #endif
            
            // Also mark all loaded steps as completed (in case they loaded after the force)
            var markedCount = 0
            for step in actualSteps {
                if !isStepCompleted(step.id) {
                    PracticeManager.shared.markPracticeAsCompleted(practiceID: step.id)
                    markedCount += 1
                }
            }
            
            #if DEBUG
            if markedCount > 0 {
                print("📊 JOURNEY: [DEV_SKIP] Marked \(markedCount) additional steps as completed (loaded after force)")
            }
            print("📊 JOURNEY: [DEV_SKIP] updateProgress() DONE (forced path)")
            #endif
            return
        }
        
        #if DEBUG
        print("📊 JOURNEY: [DEV_SKIP] updateProgress() using normal calculation (not forced)")
        #endif
        
        // Calculate completed steps
        let completed = pathSteps.filter { 
            !$0.id.hasPrefix("coming_soon_") && isStepCompleted($0.id) 
        }
        completedStepCount = completed.count
        
        // Check if all steps are completed
        let actualSteps = pathSteps.filter { !$0.id.hasPrefix("coming_soon_") }
        allStepsCompleted = !actualSteps.isEmpty && completed.count == actualSteps.count
        
        // Find next step
        if allStepsCompleted {
            nextStep = nil
        } else {
            let sortedSteps = actualSteps.sorted(by: { $0.order < $1.order })
            nextStep = sortedSteps.first { getStepState(for: $0) == .next }
            
            // Fallback to first step if no next found
            if nextStep == nil && !sortedSteps.isEmpty {
                nextStep = sortedSteps.first
            }
        }
    }
    
    /// Initialize OneSignal path tags for journey automation
    private func initializeOneSignalPathTags() {
        // Prevent redundant initialization during app lifecycle
        guard !hasInitializedOneSignalTags else {
            logger.eventMessage("PathProgressManager: OneSignal tags already initialized, skipping")
            return
        }
        
        // Ensure we have path steps loaded before initializing tags
        guard !pathSteps.isEmpty else {
            logger.eventMessage("PathProgressManager: No path steps available for OneSignal tag initialization")
            return
        }
        
        hasInitializedOneSignalTags = true
        
        // One-time cleanup of legacy tags to prevent hitting tag limits
        PathAnalyticsHandler.shared.cleanupLegacyPathTags()
        
        // Initialize or update tags based on user's current progress (essential tags only)
        PathAnalyticsHandler.shared.initializePathTagsForNewUser()
        
        logger.eventMessage("PathProgressManager: Initialized OneSignal path tags")
    }
}

