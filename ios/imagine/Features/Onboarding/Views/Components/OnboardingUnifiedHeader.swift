//
//  OnboardingUnifiedHeader.swift
//  imagine
//
//  Created by Cursor on 1/16/26.
//
//  Unified header component for ALL onboarding and subscription screens.
//  Uses FIXED-POSITION SLOTS to guarantee pixel-perfect consistency.
//
//  CRITICAL: Every element has a fixed Y position from the safe area top.
//  Space is RESERVED even when content is hidden, ensuring no positional drift.
//
//  Layout Slots (from safe area top):
//  ┌────────────────────────────────────────────────────┐
//  │ 8px padding                                        │
//  │ ┌────────────────────────────────────────────────┐ │
//  │ │ ROW 1: Action Button (32px height)             │ │
//  │ └────────────────────────────────────────────────┘ │
//  │ 14px gap                                           │
//  │ ┌────────────────────────────────────────────────┐ │
//  │ │ ROW 2: Progress Bar (8px height, reserved)     │ │
//  │ └────────────────────────────────────────────────┘ │
//  │ 28px gap                                           │
//  │ ┌────────────────────────────────────────────────┐ │
//  │ │ ROW 3: Title + Subtitle (variable height)      │ │
//  │ └────────────────────────────────────────────────┘ │
//  └────────────────────────────────────────────────────┘
//

import SwiftUI

// MARK: - Unified Header

struct OnboardingUnifiedHeader: View {
    
    // MARK: - Layout Constants (Single Source of Truth)
    
    enum Layout {
        // Vertical spacing
        static let topPadding: CGFloat = 8             // From safe area top to Row 1
        static let row1Height: CGFloat = 32            // Mute/Close button row height
        static let row1ToRow2Gap: CGFloat = 14         // Gap between Row 1 and Row 2
        static let row2Height: CGFloat = 8             // Progress bar slot height
        static let row2ToRow3Gap: CGFloat = 28         // Gap between Row 2 and Row 3
        
        // Horizontal padding
        static let horizontalPadding: CGFloat = 32     // Title and progress bar
        static let buttonPadding: CGFloat = 20         // Action buttons
    }
    
    // MARK: - Action Button Configuration
    
    enum ActionButton {
        case mute                                                    // Standard mute button (onboarding)
        case close(action: () -> Void)                              // X button only (subscription free trial)
        case backAndClose(back: () -> Void, close: () -> Void)      // Back + X buttons (subscription choose plan)
    }
    
    // MARK: - Properties
    
    /// Action button configuration (mute, close, or back+close)
    let actionButton: ActionButton
    
    /// Whether to show the progress bar
    let showsProgressBar: Bool
    
    /// Progress value (0.0 to 1.0)
    let progress: Double
    
    /// Title text (nil = no title displayed)
    let title: String?
    
    /// Subtitle text (optional, shown below title)
    let subtitle: String?
    
    // MARK: - Initializers
    
    /// Full initializer with all options
    init(
        actionButton: ActionButton,
        showsProgressBar: Bool,
        progress: Double,
        title: String?,
        subtitle: String? = nil
    ) {
        self.actionButton = actionButton
        self.showsProgressBar = showsProgressBar
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
    }
    
    /// Convenience initializer for onboarding screens using OnboardingStep
    init(step: OnboardingStep, progress: Double) {
        self.actionButton = .mute
        self.showsProgressBar = step.showsProgressBar
        self.progress = progress
        self.title = step.showsTitleInHeader ? step.title : nil
        self.subtitle = step.showsTitleInHeader ? step.subtitle : nil
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // ═══════════════════════════════════════════════════════════════
            // ROW 1: Action Button Slot
            // Fixed height: 32px, Fixed Y: 8px from safe area top
            // ═══════════════════════════════════════════════════════════════
            HStack {
                // Left side: Back button (only for .backAndClose)
                if case .backAndClose(let backAction, _) = actionButton {
                    Button(action: {
                        HapticManager.shared.impact(.light)
                        backAction()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: Layout.row1Height)
                    }
                }
                
                Spacer()
                
                // Right side: Mute or Close button
                switch actionButton {
                case .mute:
                    MuteUnmuteButton()
                        .frame(height: Layout.row1Height)
                    
                case .close(let closeAction):
                    closeButton(action: closeAction)
                    
                case .backAndClose(_, let closeAction):
                    closeButton(action: closeAction)
                }
            }
            .frame(height: Layout.row1Height)
            .padding(.horizontal, Layout.buttonPadding)
            .padding(.top, Layout.topPadding)
            
            // ═══════════════════════════════════════════════════════════════
            // ROW 2: Progress Bar Slot
            // Fixed height: 8px (RESERVED even when hidden)
            // Fixed Y: Row1 bottom + 14px gap
            // ═══════════════════════════════════════════════════════════════
            Group {
                if showsProgressBar {
                    OnboardingProgressBar(progress: progress)
                } else {
                    // Reserve the space to maintain consistent positioning
                    Color.clear
                }
            }
            .frame(height: Layout.row2Height)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, Layout.row1ToRow2Gap)
            
            // ═══════════════════════════════════════════════════════════════
            // ROW 3: Title Slot
            // Variable height (depends on text length)
            // Fixed Y: Row2 bottom + 28px gap
            // ═══════════════════════════════════════════════════════════════
            if let title = title {
                VStack(spacing: 12) {
                    Text(title)
                        .onboardingDisplayStyle()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .nunitoFont(size: 16, style: .medium)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.top, Layout.row2ToRow3Gap)
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func closeButton(action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            Image(.iconX)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: Layout.row1Height, height: Layout.row1Height)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingUnifiedHeader_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Onboarding with title (Sensei step)
            previewContainer(
                header: OnboardingUnifiedHeader(
                    actionButton: .mute,
                    showsProgressBar: true,
                    progress: 1.0/6.0,
                    title: "The sensei is listening",
                    subtitle: nil
                ),
                name: "Onboarding - With Title"
            )
            
            // Onboarding without title (Welcome step)
            previewContainer(
                header: OnboardingUnifiedHeader(
                    actionButton: .mute,
                    showsProgressBar: false,
                    progress: 0,
                    title: nil,
                    subtitle: nil
                ),
                name: "Onboarding - Welcome (No Title)"
            )
            
            // Subscription - Free Trial (close button only)
            previewContainer(
                header: OnboardingUnifiedHeader(
                    actionButton: .close(action: {}),
                    showsProgressBar: false,
                    progress: 0,
                    title: "7-day free trial",
                    subtitle: nil
                ),
                name: "Subscription - Free Trial"
            )
            
            // Subscription - Choose Plan (back + close)
            previewContainer(
                header: OnboardingUnifiedHeader(
                    actionButton: .backAndClose(back: {}, close: {}),
                    showsProgressBar: false,
                    progress: 0,
                    title: "Choose your plan",
                    subtitle: nil
                ),
                name: "Subscription - Choose Plan"
            )
        }
    }
    
    @ViewBuilder
    static func previewContainer(header: OnboardingUnifiedHeader, name: String) -> some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.backgroundDarkPurple.ignoresSafeArea()
                Image("OnboardingSensei")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                
                // Fade overlay - covers bottom 50% of screen
                PurpleFadeOverlay(coverage: 0.50)
                
                VStack(spacing: 0) {
                    header
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName(name)
    }
}
#endif
