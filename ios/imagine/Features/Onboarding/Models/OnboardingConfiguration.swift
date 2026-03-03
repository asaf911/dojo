//
//  OnboardingConfiguration.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Configuration for the onboarding flow.
//  Supports A/B testing with different step sequences, copy overrides, and feature flags.
//

import Foundation

// MARK: - Onboarding Configuration

/// Configuration for the onboarding flow - supports A/B testing
struct OnboardingConfiguration {
    
    // MARK: - Properties
    
    /// Which steps are included in this flow variant
    let activeSteps: [OnboardingStep]
    
    /// Flow variant identifier for analytics
    let variantId: String
    
    /// Whether to show progress bar
    let showProgressBar: Bool
    
    /// Whether to allow skip on certain screens
    let allowSkip: Bool
    
    /// Screen-specific copy overrides
    let copyOverrides: [OnboardingStep: ScreenCopy]
    
    // MARK: - Screen Copy Override
    
    struct ScreenCopy {
        let title: String?
        let subtitle: String?
        let ctaText: String?
        
        init(title: String? = nil, subtitle: String? = nil, ctaText: String? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.ctaText = ctaText
        }
    }
    
    // MARK: - Initialization
    
    init(
        activeSteps: [OnboardingStep] = OnboardingStep.allCases,
        variantId: String = "control",
        showProgressBar: Bool = true,
        allowSkip: Bool = false,
        copyOverrides: [OnboardingStep: ScreenCopy] = [:]
    ) {
        self.activeSteps = activeSteps
        self.variantId = variantId
        self.showProgressBar = showProgressBar
        self.allowSkip = allowSkip
        self.copyOverrides = copyOverrides
    }
    
    // MARK: - Helper Methods
    
    /// Get title for a step (with override if available)
    func title(for step: OnboardingStep) -> String {
        copyOverrides[step]?.title ?? step.title
    }
    
    /// Get subtitle for a step (with override if available)
    func subtitle(for step: OnboardingStep) -> String? {
        if let override = copyOverrides[step]?.subtitle {
            return override
        }
        return step.subtitle
    }
    
    /// Get CTA text for a step (with override if available)
    func ctaText(for step: OnboardingStep) -> String {
        copyOverrides[step]?.ctaText ?? step.ctaText
    }
    
    /// Total number of steps in this configuration
    var totalSteps: Int {
        activeSteps.count
    }
    
    /// Check if a step is included in this configuration
    func includes(_ step: OnboardingStep) -> Bool {
        activeSteps.contains(step)
    }
    
    /// Get index of a step within active steps
    func index(of step: OnboardingStep) -> Int? {
        activeSteps.firstIndex(of: step)
    }
    
    /// Get the next step after a given step
    func nextStep(after step: OnboardingStep) -> OnboardingStep? {
        guard let currentIndex = index(of: step),
              currentIndex + 1 < activeSteps.count else {
            return nil
        }
        return activeSteps[currentIndex + 1]
    }
    
    /// Get the previous step before a given step
    func previousStep(before step: OnboardingStep) -> OnboardingStep? {
        guard let currentIndex = index(of: step),
              currentIndex > 0 else {
            return nil
        }
        return activeSteps[currentIndex - 1]
    }
    
    // MARK: - Default Configuration
    
    /// Default configuration with all steps
    static var `default`: OnboardingConfiguration {
        OnboardingConfiguration(
            activeSteps: OnboardingStep.allCases,
            variantId: "control",
            showProgressBar: true,
            allowSkip: false,
            copyOverrides: [:]
        )
    }
    
    // MARK: - A/B Test Variants
    
    /// Short flow variant - fewer steps for testing conversion
    static var shortFlow: OnboardingConfiguration {
        OnboardingConfiguration(
            activeSteps: [.welcome, .goals, .building, .ready],
            variantId: "short_flow_v1",
            showProgressBar: true,
            allowSkip: false,
            copyOverrides: [:]
        )
    }
    
    /// Skippable variant - allows users to skip steps
    static var skippable: OnboardingConfiguration {
        OnboardingConfiguration(
            activeSteps: OnboardingStep.allCases,
            variantId: "skippable_v1",
            showProgressBar: true,
            allowSkip: true,
            copyOverrides: [:]
        )
    }
}
