//
//  BuildingScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Building screen - "Your Personalized Path Is Taking Shape"
//  Simple layout with title, Sensei, and sequential loading indicators.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//  This screen has no footer (auto-advances after animation).
//

import SwiftUI

struct BuildingScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    /// Animation states for checklist items
    @State private var item1Complete: Bool = false
    @State private var item2Complete: Bool = false
    @State private var item3Complete: Bool = false
    
    private let checklistItems = [
        "Aligned with your goal",
        "Focused on your challenge",
        "Designed for measurable growth"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ═══════════════════════════════════════════════
            // FLEXIBLE SPACE (title is in unified header)
            // ═══════════════════════════════════════════════
            Spacer()
            
            // ═══════════════════════════════════════════════
            // SENSEI WITH AURA
            // ═══════════════════════════════════════════════
            SenseiView(style: .thinking)
            
            // ═══════════════════════════════════════════════
            // FLEXIBLE SPACE
            // ═══════════════════════════════════════════════
            Spacer()
            
            // ═══════════════════════════════════════════════
            // LOADING CHECKLIST
            // ═══════════════════════════════════════════════
            VStack(alignment: .leading, spacing: 20) {
                BuildingChecklistItem(
                    text: checklistItems[0],
                    isComplete: item1Complete,
                    isAnimating: !item1Complete
                )
                
                BuildingChecklistItem(
                    text: checklistItems[1],
                    isComplete: item2Complete,
                    isAnimating: item1Complete && !item2Complete
                )
                
                BuildingChecklistItem(
                    text: checklistItems[2],
                    isComplete: item3Complete,
                    isAnimating: item2Complete && !item3Complete
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            
            // ═══════════════════════════════════════════════
            // BOTTOM SPACER (fills remaining space)
            // ═══════════════════════════════════════════════
            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            // Reset building progress when screen appears
            viewModel.buildingSubProgress = 0
            startAnimationSequence()
        }
    }
    
    // MARK: - Animation Sequence
    
    private func startAnimationSequence() {
        // Item 1 completes at 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                item1Complete = true
                viewModel.buildingSubProgress = 1.0 / 3.0
            }
        }
        
        // Item 2 completes at 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                item2Complete = true
                viewModel.buildingSubProgress = 2.0 / 3.0
            }
        }
        
        // Item 3 completes at 4.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                item3Complete = true
                viewModel.buildingSubProgress = 1.0
            }
        }
    }
}

// MARK: - Building Checklist Item

private struct BuildingChecklistItem: View {
    let text: String
    let isComplete: Bool
    let isAnimating: Bool
    
    /// Rotation angle for spinning animation
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        HStack(spacing: 27) {
            // Status indicator (24x24 frame)
            ZStack {
                if isComplete {
                    // Completed: static checkmark
                    Image("buildingCheck")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.dojoTurquoise)
                } else if isAnimating {
                    // Loading: spinning circle
                    Image("buildingCircle")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.dojoTurquoise)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.0)
                                .repeatForever(autoreverses: false)
                            ) {
                                rotationAngle = 360
                            }
                        }
                } else {
                    // Pending: empty space (no icon)
                    Color.clear
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 24, height: 24)
            
            // Text (246px fixed width frame)
            Text(text)
                .onboardingLabelStyle()
                .frame(width: 246, alignment: .leading)
        }
        .frame(width: 297) // 24 + 27 + 246 = 297
    }
}

// MARK: - Preview

#if DEBUG
struct BuildingScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .building) {
            BuildingScreen(viewModel: OnboardingViewModel())
        }
    }
}
#endif
