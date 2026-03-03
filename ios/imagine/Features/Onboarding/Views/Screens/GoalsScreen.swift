//
//  GoalsScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Goals selection screen - "What Do You Seek?"
//  Single-select goal for personalization.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI

struct GoalsScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showMoreGoals: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ═══════════════════════════════════════════════
            // FLEXIBLE SPACE (title is in unified header)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(minHeight: 20, maxHeight: 40)
            
            // ═══════════════════════════════════════════════
            // SENSEI WITH AURA (FIXED - not scrollable)
            // ═══════════════════════════════════════════════
            SenseiView(style: .listening, topSpacing: 50)
            
            // ═══════════════════════════════════════════════
            // SCROLLABLE CONTENT
            // When "More goals" is tapped, content scrolls up
            // to keep footer visible
            // ═══════════════════════════════════════════════
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // TEXT
                        Spacer()
                            .frame(height: 4)
                        
                        Text("This defines your path.")
                            .onboardingBodyLargeStyle()
                            .foregroundColor(Color("ColorTextPrimary"))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // QUESTION TEXT
                        Spacer()
                            .frame(height: 14)
                        
                        Text("Choose one:")
                            .onboardingBodyStyle()
                            .foregroundColor(Color("ColorTextPrimary"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // OPTIONS (single-select)
                        Spacer()
                            .frame(height: 14)
                        
                        VStack(spacing: 12) {
                            // Primary goals (always visible)
                            ForEach(OnboardingGoal.primaryGoals, id: \.self) { goal in
                                GoalsOptionButton(
                                    title: goal.displayName,
                                    icon: goal.iconName,
                                    isSelected: viewModel.responses.selectedGoal == goal
                                ) {
                                    viewModel.selectGoal(goal)
                                }
                            }
                            
                            // Secondary goals (revealed after tapping "More goals")
                            if showMoreGoals {
                                ForEach(OnboardingGoal.secondaryGoals, id: \.self) { goal in
                                    GoalsOptionButton(
                                        title: goal.displayName,
                                        icon: goal.iconName,
                                        isSelected: viewModel.responses.selectedGoal == goal
                                    ) {
                                        viewModel.selectGoal(goal)
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                                
                                // Scroll anchor after last secondary goal
                                Color.clear
                                    .frame(height: 1)
                                    .id("goalsBottom")
                            }
                            
                            // "+ More goals" row (only when collapsed)
                            if !showMoreGoals {
                                MoreGoalsRow {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showMoreGoals = true
                                    }
                                }
                            }
                        }
                    }
                }
                .onChange(of: showMoreGoals) {
                    if showMoreGoals {
                        // Delay to let the new content render
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo("goalsBottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - More Goals Row

/// Tappable row to reveal additional goals
/// Layout matches GoalsOptionButton: Space | Icon | Text | Space
private struct MoreGoalsRow: View {
    let onTap: () -> Void
    
    /// Fixed width for text to match GoalsOptionButton alignment
    private let textWidth: CGFloat = 150
    /// Leading padding to align text with primary button
    private let leadingPadding: CGFloat = 24
    
    var body: some View {
        HStack {
            Spacer()
            
            // Centered content block matching GoalsOptionButton structure
            HStack(spacing: 12) {
                // Icon (same frame as goal icons for alignment)
                Image("iconPlus")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(Color("ColorTextPrimary"))
                
                // Text (same fixed width as goal text)
                Text("More goals")
                    .onboardingButtonTextStyle()
                    .foregroundColor(Color("ColorTextPrimary"))
                    .frame(width: textWidth, alignment: .leading)
            }
            .padding(.leading, leadingPadding)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.impact(.light)
            onTap()
        }
    }
}

// MARK: - Goals Option Button

/// Option button for single-select goals with icon support
/// Layout: Space | Icon | Text | Space (centered content block)
private struct GoalsOptionButton: View {
    let title: String
    var icon: String? = nil
    var isSelected: Bool = false
    let action: () -> Void
    
    /// Fixed width for text to ensure alignment across buttons
    private let textWidth: CGFloat = 150
    /// Leading padding to align text with primary button
    private let leadingPadding: CGFloat = 24
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            HStack {
                Spacer()
                
                // Centered content block with fixed internal structure
                HStack(spacing: 12) {
                    // Icon (fixed size for vertical alignment)
                    if let icon = icon {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(Color("ColorTextPrimary"))
                    }
                    
                    // Text (fixed width, left-aligned internally)
                    Text(title)
                        .font(Font.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundColor(Color("ColorTextPrimary"))
                        .frame(width: textWidth, alignment: .leading)
                }
                .padding(.leading, leadingPadding)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
            .background(
                // Clean background - let glassEffect handle the glass treatment
                RoundedRectangle(cornerRadius: 23)
                    .fill(isSelected ? Color.onboardingButtonSelected : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .liquidGlass(cornerRadius: 23, style: .secondary)
            .specularBorder(cornerRadius: 23)
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .contentShape(RoundedRectangle(cornerRadius: 23))
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#if DEBUG
struct GoalsScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .goals) {
            GoalsScreen(viewModel: OnboardingViewModel())
        }
    }
}
#endif
