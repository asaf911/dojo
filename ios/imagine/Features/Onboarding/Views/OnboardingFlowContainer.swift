//
//  OnboardingFlowContainer.swift
//  imagine
//
//  Created by Cursor on 1/17/26.
//
//  Fixed layout container for ALL onboarding and subscription screens.
//  Uses GeometryReader to define exact zones for header, content, and footer.
//
//  ARCHITECTURE:
//  ┌─────────────────────────────────────────────┐
//  │              SAFE AREA TOP                  │
//  ├─────────────────────────────────────────────┤
//  │                                             │
//  │           HEADER ZONE                       │  ← Fixed position (top)
//  │   (mute/close, progress bar, title)         │
//  │                                             │
//  ├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┤
//  │                                             │
//  │           CONTENT ZONE                      │  ← Fills remaining space
//  │   (screen-specific content)                 │
//  │                                             │
//  ├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┤
//  │                                             │
//  │           FADE OVERLAY                      │  ← Bottom fade (configurable %)
//  │                                             │
//  ├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┤
//  │                                             │
//  │           FOOTER ZONE                       │  ← Fixed position (bottom)
//  │   (primary button, secondary action)        │
//  │                                             │
//  ├─────────────────────────────────────────────┤
//  │              SCREEN BOTTOM                  │
//  └─────────────────────────────────────────────┘
//
//  KEY PRINCIPLE: Header and footer are NOT part of content flow.
//  They are absolutely positioned. Screens fill the content zone only.
//

import SwiftUI

// MARK: - Background Configuration

/// Configuration for screen background
struct OnboardingBackgroundConfig {
    let imageName: String
    
    init(imageName: String) {
        self.imageName = imageName
    }
}

// MARK: - Layout Constants (Single Source of Truth)

/// Layout constants for the onboarding flow container
enum OnboardingFlowLayout {
    // Footer positioning (from screen bottom, ignoring safe area)
    static let footerBottomFromScreen: CGFloat = 50
    static let primaryButtonHeight: CGFloat = 46
    static let secondaryActionHeight: CGFloat = 50  // Space for secondary text
    
    /// Total footer zone height (button + bottom space)
    static var footerZoneHeight: CGFloat {
        primaryButtonHeight + footerBottomFromScreen
    }
    
    // Header positioning
    /// Vertical offset to move header up from default position (negative = up)
    static let headerVerticalOffset: CGFloat = -28
    
    // Header constants (matching OnboardingUnifiedHeader.Layout)
    static let headerTopPadding: CGFloat = 8
    static let headerRow1Height: CGFloat = 32
    static let headerRow1ToRow2Gap: CGFloat = 14
    static let headerRow2Height: CGFloat = 8
    static let headerRow2ToRow3Gap: CGFloat = 28
    static let headerTitleEstimatedHeight: CGFloat = 44  // Single line title
    static let headerSubtitleEstimatedHeight: CGFloat = 24  // Single line subtitle
}

// MARK: - Footer Configuration

/// Configuration for the footer in OnboardingFlowContainer
struct OnboardingFlowFooterConfig {
    let primaryButton: PrimaryButtonConfig?
    let secondaryAction: SecondaryActionConfig?
    
    struct PrimaryButtonConfig {
        let text: String
        let style: OnboardingButtonStyle
        let isEnabled: Bool
        let isLoading: Bool
        let action: () -> Void
        
        init(
            text: String,
            style: OnboardingButtonStyle = .primary,
            isEnabled: Bool = true,
            isLoading: Bool = false,
            action: @escaping () -> Void
        ) {
            self.text = text
            self.style = style
            self.isEnabled = isEnabled
            self.isLoading = isLoading
            self.action = action
        }
    }
    
    struct SecondaryActionConfig {
        let text: String
        let action: () -> Void
    }
    
    init(
        primaryButton: PrimaryButtonConfig? = nil,
        secondaryAction: SecondaryActionConfig? = nil
    ) {
        self.primaryButton = primaryButton
        self.secondaryAction = secondaryAction
    }
    
    /// Convenience for simple primary-only footer
    init(
        primaryText: String,
        primaryStyle: OnboardingButtonStyle = .primary,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.primaryButton = PrimaryButtonConfig(
            text: primaryText,
            style: primaryStyle,
            isEnabled: isEnabled,
            isLoading: isLoading,
            action: action
        )
        self.secondaryAction = nil
    }
}

// MARK: - Header Configuration

/// Configuration for the header in OnboardingFlowContainer
struct OnboardingFlowHeaderConfig {
    let actionButton: OnboardingUnifiedHeader.ActionButton
    let showsProgressBar: Bool
    let progress: Double
    let title: String?
    let subtitle: String?
    
    init(
        actionButton: OnboardingUnifiedHeader.ActionButton = .mute,
        showsProgressBar: Bool = true,
        progress: Double = 0,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        self.actionButton = actionButton
        self.showsProgressBar = showsProgressBar
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Flow Container

struct OnboardingFlowContainer<Content: View>: View {
    
    // MARK: - Properties
    
    let backgroundConfig: OnboardingBackgroundConfig
    let headerConfig: OnboardingFlowHeaderConfig
    let footerConfig: OnboardingFlowFooterConfig?
    let fadeConfig: PurpleFadeConfig
    let content: Content
    
    // MARK: - Initializer
    
    init(
        backgroundConfig: OnboardingBackgroundConfig,
        headerConfig: OnboardingFlowHeaderConfig,
        footerConfig: OnboardingFlowFooterConfig? = nil,
        fadeConfig: PurpleFadeConfig = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundConfig = backgroundConfig
        self.headerConfig = headerConfig
        self.footerConfig = footerConfig
        self.fadeConfig = fadeConfig
        self.content = content()
    }
    
    // MARK: - Computed Properties
    
    /// Calculate header height based on configuration
    private var headerHeight: CGFloat {
        var height: CGFloat = OnboardingFlowLayout.headerTopPadding + OnboardingFlowLayout.headerRow1Height
        
        // Progress bar row (always reserved, even when hidden)
        height += OnboardingFlowLayout.headerRow1ToRow2Gap + OnboardingFlowLayout.headerRow2Height
        
        // Title row (only if title is present)
        if headerConfig.title != nil {
            height += OnboardingFlowLayout.headerRow2ToRow3Gap + OnboardingFlowLayout.headerTitleEstimatedHeight
            
            // Subtitle (if present)
            if headerConfig.subtitle != nil {
                height += 12 + OnboardingFlowLayout.headerSubtitleEstimatedHeight
            }
        }
        
        return height
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // ═══════════════════════════════════════════════════════════════
                // LAYER 0: Background image (full screen, ignores safe area)
                // ═══════════════════════════════════════════════════════════════
                Color.backgroundDarkPurple
                    .overlay(
                        Image(backgroundConfig.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .ignoresSafeArea()
                
                // ═══════════════════════════════════════════════════════════════
                // LAYER 1: Fade overlay (purple at bottom, clear at top)
                // ═══════════════════════════════════════════════════════════════
                PurpleFadeOverlay(config: fadeConfig)
                
                // ═══════════════════════════════════════════════════════════════
                // LAYER 2: Header (fixed to top, offset up)
                // ═══════════════════════════════════════════════════════════════
                VStack(spacing: 0) {
                    OnboardingUnifiedHeader(
                        actionButton: headerConfig.actionButton,
                        showsProgressBar: headerConfig.showsProgressBar,
                        progress: headerConfig.progress,
                        title: headerConfig.title,
                        subtitle: headerConfig.subtitle
                    )
                    Spacer()
                }
                .offset(y: OnboardingFlowLayout.headerVerticalOffset)
                
                // ═══════════════════════════════════════════════════════════════
                // LAYER 3: Content (bounded to zone between header and footer)
                // ═══════════════════════════════════════════════════════════════
                VStack(spacing: 0) {
                    // Header zone reservation (pushes content below header)
                    // Adjusted for header offset (header moved up, so content starts higher)
                    Color.clear
                        .frame(height: headerHeight + OnboardingFlowLayout.headerVerticalOffset)
                    
                    // Content fills available space
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Footer zone reservation (keeps content above footer)
                    if footerConfig != nil {
                        Color.clear
                            .frame(height: OnboardingFlowLayout.footerZoneHeight)
                    }
                }
                
                // ═══════════════════════════════════════════════════════════════
                // LAYER 4: Footer (fixed to bottom)
                // ═══════════════════════════════════════════════════════════════
                if let footer = footerConfig {
                    VStack(spacing: 0) {
                        Spacer()
                        footerView(config: footer)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    // MARK: - Footer View
    
    @ViewBuilder
    private func footerView(config: OnboardingFlowFooterConfig) -> some View {
        VStack(spacing: 0) {
            // Primary action button
            if let primary = config.primaryButton {
                OnboardingPrimaryButton(
                    text: primary.text,
                    style: primary.style,
                    isEnabled: primary.isEnabled,
                    isLoading: primary.isLoading,
                    action: primary.action
                )
            }
            
            // Secondary action or spacer
            if let secondary = config.secondaryAction {
                Button(action: {
                    HapticManager.shared.impact(.light)
                    secondary.action()
                }) {
                    // Text/Supporting/Medium - ColorTextSecondary
                    Text(secondary.text)
                        .onboardingTypography(.supporting)
                        .foregroundColor(Color("ColorTextSecondary"))
                }
                .frame(height: OnboardingFlowLayout.footerBottomFromScreen)
            } else {
                // Reserve space when no secondary action
                Spacer()
                    .frame(height: OnboardingFlowLayout.footerBottomFromScreen)
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingFlowContainer_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // With header, content, and footer
            OnboardingFlowContainer(
                backgroundConfig: .init(imageName: "OnboardingSensei"),
                headerConfig: .init(
                    actionButton: .mute,
                    showsProgressBar: true,
                    progress: 0.33,
                    title: "The sensei is listening"
                ),
                footerConfig: .init(
                    primaryText: "Continue",
                    action: {}
                ),
                fadeConfig: .init(coverage: 0.60)
            ) {
                VStack {
                    Text("Content Area")
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .previewDisplayName("Sensei Style")
            
            // Welcome style
            OnboardingFlowContainer(
                backgroundConfig: .init(imageName: "OnboardingWelcome"),
                headerConfig: .init(
                    actionButton: .mute,
                    showsProgressBar: false,
                    progress: 0
                ),
                footerConfig: .init(
                    primaryText: "Get started",
                    primaryStyle: .secondary,
                    action: {}
                ),
                fadeConfig: .init(coverage: 0.55)
            ) {
                VStack {
                    Text("Welcome Content")
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .previewDisplayName("Welcome Style")
            
            // Subscription style (close button)
            OnboardingFlowContainer(
                backgroundConfig: .init(imageName: "SubscriptionTrial"),
                headerConfig: .init(
                    actionButton: .close(action: {}),
                    showsProgressBar: false,
                    progress: 0,
                    title: "7-day free trial"
                ),
                footerConfig: .init(
                    primaryButton: .init(text: "Start Trial", action: {}),
                    secondaryAction: .init(text: "View all plans", action: {})
                ),
                fadeConfig: .init(coverage: 0.65)
            ) {
                VStack {
                    Text("Subscription Content")
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .previewDisplayName("Subscription Style")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
