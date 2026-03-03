import Foundation

// ⚠️ DEPRECATED: AIOnboarding feature disabled as of January 2026
// This file is preserved for potential future reuse.
// The flow is disabled via hasPendingSteps() always returning false in SenseiOnboardingState.
// Do not add new functionality - this code path is no longer active.

enum SenseiOnboardingScript {
    static func currentFirstName() -> String? {
        let storedName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)
        return storedName?.split(separator: " ").first.map(String.init)
    }

    static func steps(firstName: String?) -> SenseiOnboardingSequence {
        // Onboarding script - 6-step conversational flow
        // All paths converge on the final prompt education step
        
        // Welcome title with personalization
        let welcomeTitle = firstName.map { "Welcome to Dojo \($0)," } ?? "Welcome to Dojo Traveler,"
        
        // Step 1: Sensei Introduction (personalization choice)
        let introMessage = """
I'm Sensei, your meditation guide.

Every journey is different. By learning a bit about your goals and how you're feeling, I can craft practices made just for you.

Shall we personalize your experience?
"""
        
        // Step 2: Goal Understanding
        let goalPreamble = "Every journey begins with intention."
        let goalQuestion = "What would you like to work on right now?"
        let goalOptions = [
            "Reduce stress",
            "Sleep better",
            "Improve focus",
            "Boost mood",
            "Spiritual growth",
            "Build consistency"
        ]
        
        // Step 3: Baseline Understanding
        let baselinePreamble = "Thanks."
        let baselineQuestion = "How are you feeling today?"
        let baselineOptions = [
            "Stressed",
            "Tired or low",
            "Distracted",
            "Angry or tense",
            "Neutral",
            "Calm or energized"
        ]
        
        // Step 4: Experience Tracking
        let experiencePreamble = "Thank you.\n\nLet me understand your experience."
        let experienceQuestion = "How have you practiced before?"
        let experienceOptions = [
            "Calm or Headspace",
            "Other apps",
            "YouTube or Spotify",
            "On my own",
            "Workshops and retreats",
            "I'm completely new"
        ]
        
        // Step 5: Guidance Style (merged with Dojo differentiation message)
        let guidancePreamble = "Thank you.\n\nDojo is different - it adapts to your goals, your state, and your progress."
        let guidanceQuestion = "How would you like the guidance to feel?"
        let guidanceOptions = [
            "Calm & soft",
            "Direct & clear",
            "Scientific",
            "Spiritual"
        ]

        let steps: SenseiOnboardingSequence = [
            // Step 1: Sensei Introduction - choice to personalize
            SenseiOnboardingMessage(
                id: "new_intro",
                title: welcomeTitle,
                body: introMessage,
                cta: .withSkipToMeditation(
                    continueTitle: "Let's personalize",
                    skipTitle: "Skip it, let's meditate",
                    analyticsActionId: "new_intro_personalize",
                    analyticsSkipId: "new_intro_skip_to_meditation"
                )
            ),
            
            // Step 2: Goal Understanding (combined preamble + question)
            SenseiOnboardingQuestion(
                id: "new_goal_question",
                preamble: goalPreamble,
                question: goalQuestion,
                options: goalOptions,
                allowsMultipleSelection: true,
                cta: .withSkipToMeditation(
                    continueTitle: "Continue",
                    skipTitle: "Skip goals, let's begin",
                    analyticsActionId: "new_goal_question_continue",
                    analyticsSkipId: "new_goal_question_skip_to_meditation"
                )
            ),
            
            // Step 3: Baseline Understanding (combined preamble + question)
            SenseiOnboardingQuestion(
                id: "new_baseline_question",
                preamble: baselinePreamble,
                question: baselineQuestion,
                options: baselineOptions,
                allowsMultipleSelection: true,
                cta: .withSkipToMeditation(
                    continueTitle: "Continue",
                    skipTitle: "Take me to my meditation",
                    analyticsActionId: "new_baseline_question_continue",
                    analyticsSkipId: "new_baseline_question_skip_to_meditation"
                )
            ),
            
            // Step 4: Experience Tracking (combined preamble + question)
            SenseiOnboardingQuestion(
                id: "new_experience_question",
                preamble: experiencePreamble,
                question: experienceQuestion,
                options: experienceOptions,
                allowsMultipleSelection: true,
                cta: .withSkipToMeditation(
                    continueTitle: "Continue",
                    skipTitle: "Start without this",
                    analyticsActionId: "new_experience_question_continue",
                    analyticsSkipId: "new_experience_question_skip_to_meditation"
                )
            ),
            
            // Step 5: Guidance Style (merged with Dojo differentiation, combined preamble + question)
            SenseiOnboardingQuestion(
                id: "new_guidance_question",
                preamble: guidancePreamble,
                question: guidanceQuestion,
                options: guidanceOptions,
                allowsMultipleSelection: false,
                cta: .withSkipToMeditation(
                    continueTitle: "Continue",
                    skipTitle: "No preferences, let's begin",
                    analyticsActionId: "new_guidance_question_continue",
                    analyticsSkipId: "new_guidance_question_skip_to_meditation"
                )
            ),
            
            // Step 6: Prompt Education - teaches about chat input capability
            // Text is contextual based on how user arrived (skip vs complete) - set in view
            // First prompt is time-based (morning/evening/night)
            {
                let hour = Calendar.current.component(.hour, from: Date())
                let timeBasedPrompt: String
                if (5...11).contains(hour) {
                    timeBasedPrompt = "Calming 10m morning meditation"
                } else if (12...20).contains(hour) {
                    timeBasedPrompt = "Relaxing 15m evening session"
                } else {
                    // 21-23, 0-4 (Night)
                    timeBasedPrompt = "20m session to help me sleep"
                }
                
                return SenseiOnboardingPromptEducation(
                    id: "new_prompt_education",
                    introText: nil, // Contextual - set dynamically in view
                    preamble: "",   // Contextual - set dynamically in view
                    instruction: "Try one of these:",
                    examplePrompts: [
                        timeBasedPrompt,
                        "Help me focus for 7 minutes",
                        "Body scan with calming spa music"
                    ]
                )
            }()
        ]

        logger.aiChat("🧠 AI_DEBUG new_onboarding_script_loaded total=\(steps.count)")
        return steps
    }
}

