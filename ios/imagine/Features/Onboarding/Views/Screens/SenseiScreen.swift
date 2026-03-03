//
//  SenseiScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Sensei screen - "The Sensei Is Listening"
//  Introduces the adaptive AI concept with familiarity selection.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//  This screen has no footer (auto-advances on selection).
//

import SwiftUI

struct SenseiScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    /// Tracks which option is currently selected (for visual feedback before navigation)
    @State private var selectedOption: OnboardingFamiliarity? = nil
    
    /// Familiarity options from the enum
    private var familiarityOptions: [OnboardingFamiliarity] {
        OnboardingFamiliarity.allCases
    }
    
    /// Delay before navigation to show selection feedback (200ms is ideal per UX research)
    private let selectionFeedbackDelay: Double = 0.2
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ═══════════════════════════════════════════════
            // FLEXIBLE SPACE (title is in unified header)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(minHeight: 20, maxHeight: 40)
            
            // ═══════════════════════════════════════════════
            // SENSEI WITH AURA
            // ═══════════════════════════════════════════════
            SenseiView(style: .listening, topSpacing: 50)
            
            // ═══════════════════════════════════════════════
            // SUBTITLE
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 24)
            
            Text("Not one-size-fits-all")
                .onboardingSubtitleStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ═══════════════════════════════════════════════
            // BODY TEXT
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 8)
            
            Text("Structured for your level")
                .onboardingBodyLargeStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ═══════════════════════════════════════════════
            // QUESTION TEXT
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 14)
            
            Text("Where are you starting?")
                .onboardingBodyStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // ═══════════════════════════════════════════════
            // OPTIONS (tap to select & advance)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 14)
            
            VStack(spacing: 12) {
                ForEach(familiarityOptions, id: \.self) { option in
                    SenseiOptionButton(
                        title: option.displayName,
                        isSelected: selectedOption == option
                    ) {
                        // Show selection feedback
                        withAnimation(.easeOut(duration: 0.1)) {
                            selectedOption = option
                        }
                        
                        // Store selection and advance after brief delay (200ms)
                        // This gives user confidence their selection registered
                        DispatchQueue.main.asyncAfter(deadline: .now() + selectionFeedbackDelay) {
                            viewModel.setFamiliarity(option.displayName)
                            viewModel.advance()
                        }
                    }
                }
            }
            
            // ═══════════════════════════════════════════════
            // BOTTOM SPACER (fills remaining space)
            // ═══════════════════════════════════════════════
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Sensei Option Button

/// Option button that triggers selection and advances to next screen
private struct SenseiOptionButton: View {
    let title: String
    var isSelected: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            Text(title)
                .onboardingButtonTextStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                .background(
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
struct SenseiScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .sensei) {
            SenseiScreen(viewModel: OnboardingViewModel())
        }
    }
}
#endif
