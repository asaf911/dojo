//
//  QuestionOptionsView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-XX
//

import SwiftUI
import UIKit

struct QuestionOptionsView: View {
    let preamble: String?  // Regular text shown above the question
    let question: String   // Bold 22pt question text
    let options: [String]
    let continueTitle: String
    let skipTitle: String?
    let allowsMultipleSelection: Bool
    let isLatestMessage: Bool
    let onContinue: (String?) -> Void  // For single-select: selected option, For multi-select: comma-separated string
    let onSkip: (() -> Void)?
    
    var conversationState: AIConversationState? = nil  // Optional for non-AI chat usage
    
    @State private var selectedOption: String?  // For single-select
    @State private var selectedOptions: Set<String> = []  // For multi-select
    @State private var visibleOptionIndices: Set<Int> = []
    @State private var showButtons: Bool = false
    @State private var heightUpdateCounter: Int = 0 // Force preference key updates
    
    // Computed property to filter visible options for conditional rendering
    // This prevents SwiftUI from calculating layout for invisible options
    private var visibleOptions: [(index: Int, option: String)] {
        if isLatestMessage {
            // Only show options that are in visibleOptionIndices
            return options.enumerated()
                .filter { visibleOptionIndices.contains($0.offset) }
                .map { (index: $0.offset, option: $0.element) }
        } else {
            // For non-latest messages, show all options
            return options.enumerated()
                .map { (index: $0.offset, option: $0.element) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preamble - regular text (if present)
            if let preamble = preamble, !preamble.isEmpty {
                Text(preamble)
                    .nunitoFont(size: 16, style: .medium)
                    .foregroundColor(.white)
                    .lineSpacing(4)
            }
            
            // Question - bold 22pt text (if present)
            if !question.isEmpty {
                Text(question)
                    .font(Font.custom("Nunito", size: 22).weight(.bold))
                    .foregroundColor(.white)
                    .lineSpacing(4)
            }
            
            // Options - conditionally rendered, instant appearance (no transitions)
            VStack(spacing: 12) {
                ForEach(visibleOptions, id: \.index) { item in
                    OptionButton(
                        option: item.option,
                        index: item.index,
                        isSelected: allowsMultipleSelection ? selectedOptions.contains(item.option) : selectedOption == item.option,
                        allowsMultipleSelection: allowsMultipleSelection,
                        onTap: {
                            HapticManager.shared.impact(.light)
                            
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if allowsMultipleSelection {
                                    if selectedOptions.contains(item.option) {
                                        selectedOptions.remove(item.option)
                                    } else {
                                        selectedOptions.insert(item.option)
                                    }
                                } else {
                                    if selectedOption == item.option {
                                        selectedOption = nil
                                    } else {
                                        selectedOption = item.option
                                    }
                                }
                            }
                        }
                    )
                    .id("option_\(item.index)")
                    // NO transition - instant appearance prevents layout shifts
                }
            }
            .frame(maxWidth: .infinity)
            
            // Continue/Skip buttons - conditionally rendered, instant appearance
            if showButtons {
                SenseiCTAView(
                    continueTitle: continueTitle,
                    skipTitle: skipTitle,
                    isEnabled: true,
                    isLoading: false,
                    isValid: allowsMultipleSelection ? !selectedOptions.isEmpty : selectedOption != nil,
                    onContinue: {
                        // For multi-select, pass comma-separated string; for single-select, pass the selected option
                        let result: String?
                        if allowsMultipleSelection {
                            result = selectedOptions.isEmpty ? nil : selectedOptions.joined(separator: ", ")
                        } else {
                            result = selectedOption
                        }
                        onContinue(result)
                    },
                    onSkip: skipTitle != nil ? {
                        onSkip?()
                    } : nil
                )
                .id("question_cta")
                .padding(.top, 8)
                // NO transition - instant appearance prevents layout shifts
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: MessageHeightPreferenceKey.self,
                        value: geometry.size.height + CGFloat(heightUpdateCounter) * 0.001 // Force update with counter
                    )
            }
        )
        .onAppear {
            if isLatestMessage {
                startAnimationSequence()
            } else {
                // For non-latest messages, show everything immediately
                visibleOptionIndices = Set(0..<options.count)
                showButtons = true
            }
        }
        .onChange(of: visibleOptionIndices) { oldIndices, newIndices in
            // Trigger scroll when options become visible
            if newIndices.count > oldIndices.count && isLatestMessage {
                logger.aiChat("🧠 AI_SCROLL: QuestionOptionsView - option appeared, count: \(oldIndices.count) -> \(newIndices.count)")
                // Force preference key update
                heightUpdateCounter += 1
                // Post notification to trigger scroll directly (backup to preference keys)
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: showButtons) { oldValue, newValue in
            // Trigger scroll when buttons appear
            if newValue && !oldValue && isLatestMessage {
                logger.aiChat("🧠 AI_SCROLL: QuestionOptionsView - buttons appeared")
                // Force preference key update
                heightUpdateCounter += 1
                // Post notification to trigger scroll directly (backup to preference keys)
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
    }
    
    // MARK: - Animation Helpers
    
    private func startAnimationSequence() {
        // Show options sequentially with fixed delays
        for index in 0..<options.count {
            let delay = Double(index) * AnimationConstants.sequentialItemDelay
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Add option to visible set - instant appearance
                visibleOptionIndices.insert(index)
                
                // After last option appears, show CTA
                if index == options.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + AnimationConstants.sequentialItemDelay) {
                        showCTA()
                    }
                }
            }
        }
    }
    
    private func showCTA() {
        showButtons = true
    }
}

// MARK: - Option Button Component

struct OptionButton: View {
    let option: String
    let index: Int
    let isSelected: Bool
    let allowsMultipleSelection: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                Group {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .hidden()
                    }
                }
                .frame(width: 40)
                
                Text(option)
                    .nunitoFont(size: 16, style: .semiBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                Image(systemName: "checkmark")
                    .hidden()
                    .frame(width: 40)
            }
            .padding(.horizontal, 8)
            .frame(height: 46, alignment: .center)
            .background {
                Group {
                    if #available(iOS 26.0, *) {
                        // iOS 26+ Liquid Glass effect
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                            .overlay {
                                // Purple tint for selected state at designer spec (69%)
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.selectedLightPurple.opacity(0.69))
                                        .blendMode(.plusLighter)
                                }
                            }
                    } else {
                        // Fallback for iOS 17-25
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                            if isSelected {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.selectedLightPurple.opacity(0.69))
                                    .blendMode(.plusLighter)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .specularBorder(cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        // NO opacity, NO scale, NO transition, NO animation
        // Instant appearance - SwiftUI handles it naturally
        // Only animate selection state changes
        .animation(AnimationConstants.itemAppearanceAnimation, value: isSelected)
    }
}

struct QuestionOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        let mockConversationState = AIConversationState()
        
        VStack(spacing: 40) {
                // Preview with preamble and question
                QuestionOptionsView(
                    preamble: "Every journey begins with intention.",
                    question: "What would you like to work on right now?",
                    options: [
                        "Stress relief",
                        "Better sleep",
                        "Increased focus",
                        "Emotional balance"
                    ],
                    continueTitle: "Continue",
                    skipTitle: "Skip",
                    allowsMultipleSelection: true,
                    isLatestMessage: true,
                    onContinue: { selected in
                        print("Continue tapped with: \(selected ?? "none")")
                    },
                    onSkip: {
                        print("Skip tapped")
                    },
                    conversationState: mockConversationState
                )
                
                // Preview without preamble
                QuestionOptionsView(
                    preamble: nil,
                    question: "How do you prefer the style of guidance?",
                    options: [
                        "Soft and calming",
                        "Direct and structured",
                        "Motivational",
                        "No preference"
                    ],
                    continueTitle: "Continue",
                    skipTitle: "Skip",
                    allowsMultipleSelection: false,
                    isLatestMessage: true,
                    onContinue: { selected in
                        print("Continue tapped with: \(selected ?? "none")")
                    },
                    onSkip: {
                        print("Skip tapped")
                    },
                    conversationState: mockConversationState
                )
        }
        .padding()
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
