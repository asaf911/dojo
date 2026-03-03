//
//  OnboardingSelectableCard.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Selectable card component for the onboarding flow.
//  Used for Goals (multi-select) and Hurdle (single-select) screens.
//

import SwiftUI

// MARK: - Selectable Card

struct OnboardingSelectableCard: View {
    
    let title: String
    var icon: String? = nil
    var isSystemIcon: Bool = true
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            ZStack {
                // Centered title with optional icon
                HStack(spacing: 8) {
                    if let icon = icon {
                        if isSystemIcon {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundColor(isSelected ? .dojoTurquoise : .textOnboardingTitleGray)
                        } else {
                            Image(icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                        }
                    }
                    
                    Text(title)
                        .font(Font.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundColor(.textOnboardingTitleGray)
                }
                
                // Selection indicator on trailing edge
                HStack {
                    Spacer()
                    selectionIndicator
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
            .padding(.horizontal, 16)
            .background(
                // Clean background - let glassEffect handle the glass treatment
                RoundedRectangle(cornerRadius: 23)
                    .fill(isSelected ? Color.onboardingButtonSelected : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .liquidGlass(cornerRadius: 23, style: .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 23)
                    .stroke(
                        isSelected ? Color.dojoTurquoise : Color.clear,
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .specularBorder(cornerRadius: 23)
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .contentShape(RoundedRectangle(cornerRadius: 23))
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Selection Indicator
    
    @ViewBuilder
    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Color.dojoTurquoise : Color.white.opacity(0.3),
                    lineWidth: 2
                )
                .frame(width: 24, height: 24)
            
            if isSelected {
                Circle()
                    .fill(Color.dojoTurquoise)
                    .frame(width: 24, height: 24)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.backgroundDarkPurple)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingSelectableCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            OnboardingSelectableCard(
                title: "Relaxation",
                icon: "leaf.fill",
                isSelected: true
            ) {}
            
            OnboardingSelectableCard(
                title: "Spiritual growth",
                icon: "sparkles",
                isSelected: false
            ) {}
            
            OnboardingSelectableCard(
                title: "Better sleep",
                icon: "moon.fill",
                isSelected: false
            ) {}
            
            OnboardingSelectableCard(
                title: "Can't quiet the mind",
                isSelected: true
            ) {}
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 40)
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
#endif
