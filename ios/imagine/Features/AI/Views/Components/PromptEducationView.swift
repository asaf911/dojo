//
//  PromptEducationView.swift
//  Dojo
//
//  View component for the final onboarding step that educates users
//  about the chat input capability and offers example prompts.
//

import SwiftUI

// MARK: - Prompt Education Action

enum PromptEducationAction {
    case promptSelected(String)  // User tapped an example prompt - fills input and focuses keyboard
    case typeMyOwn               // User wants to type their own - just focuses keyboard
}

// MARK: - Prompt Education View

struct PromptEducationView: View {
    let preamble: String
    let instruction: String
    let examplePrompts: [String]
    let isLatestMessage: Bool
    
    let onAction: (PromptEducationAction) -> Void
    
    @State private var visibleOptionIndices: Set<Int> = []
    @State private var heightUpdateCounter: Int = 0
    
    // All options including "Type my own" at the end
    private var allOptions: [String] {
        examplePrompts + ["Type my own request"]
    }
    
    // Computed property to filter visible options for conditional rendering
    private var visibleOptions: [(index: Int, option: String)] {
        if isLatestMessage {
            return allOptions.enumerated()
                .filter { visibleOptionIndices.contains($0.offset) }
                .map { (index: $0.offset, option: $0.element) }
        } else {
            return allOptions.enumerated()
                .map { (index: $0.offset, option: $0.element) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preamble - bold title (only show if not empty - handled by parent)
            if !preamble.isEmpty {
                Text(preamble)
                    .font(Font.custom("Nunito", size: 22).weight(.bold))
                    .foregroundColor(.white)
                    .lineSpacing(4)
            }
            
            // Instruction
            Text(instruction)
                .nunitoFont(size: 16, style: .medium)
                .foregroundColor(.white.opacity(0.8))
            
            // Options - using same styling as QuestionOptionsView
            VStack(spacing: 12) {
                ForEach(visibleOptions, id: \.index) { item in
                    PromptOptionButton(
                        option: item.option,
                        index: item.index,
                        onTap: {
                            HapticManager.shared.impact(.light)
                            if item.index == examplePrompts.count {
                                // "Type my own" - just focus keyboard
                                onAction(.typeMyOwn)
                            } else {
                                // Example prompt - fill and focus keyboard
                                onAction(.promptSelected(item.option))
                            }
                        }
                    )
                    .id("prompt_option_\(item.index)")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: MessageHeightPreferenceKey.self,
                        value: geometry.size.height + CGFloat(heightUpdateCounter) * 0.001
                    )
            }
        )
        .onAppear {
            if isLatestMessage {
                startAnimationSequence()
            } else {
                visibleOptionIndices = Set(0..<allOptions.count)
            }
        }
        .onChange(of: visibleOptionIndices) { oldIndices, newIndices in
            if newIndices.count > oldIndices.count && isLatestMessage {
                logger.aiChat("🧠 AI_SCROLL: PromptEducationView - option appeared, count: \(oldIndices.count) -> \(newIndices.count)")
                heightUpdateCounter += 1
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
    }
    
    // MARK: - Animation Helpers
    
    private func startAnimationSequence() {
        // Show options sequentially with fixed delays
        for index in 0..<allOptions.count {
            let delay = Double(index) * AnimationConstants.sequentialItemDelay
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                visibleOptionIndices.insert(index)
            }
        }
    }
}

// MARK: - Prompt Option Button (matches OptionButton styling from QuestionOptionsView)

struct PromptOptionButton: View {
    let option: String
    let index: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(option)
                .nunitoFont(size: 16, style: .semiBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
                .frame(height: 46, alignment: .center)
                .background {
                    Group {
                        if #available(iOS 26.0, *) {
                            // iOS 26+ Liquid Glass effect
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.clear)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                        } else {
                            // Fallback for iOS 17-25
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .specularBorder(cornerRadius: 24)
                .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Preview

struct PromptEducationView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PromptEducationView(
                preamble: "Any specific requests?",
                instruction: "Try one of these:",
                examplePrompts: [
                    "A relaxing evening meditation",
                    "Help me focus for 5 minutes",
                    "A body scan for stress relief"
                ],
                isLatestMessage: false,
                onAction: { action in
                    print("Action: \(action)")
                }
            )
        }
        .padding()
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}

