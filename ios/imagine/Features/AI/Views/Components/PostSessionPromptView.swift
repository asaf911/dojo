//
//  PostSessionPromptView.swift
//  imagine
//
//  Self-contained view for the post-session "Would you like to meditate more?" prompt.
//  Renders two side-by-side glass-effect buttons (Yes / No) following existing design patterns.
//  Independent component — does not depend on QuestionOptionsView or SenseiCTAView.
//

import SwiftUI

// MARK: - Post Session Prompt View

/// Displays Yes/No buttons for the post-session continuation prompt.
/// Appears after the question text finishes its typing animation.
struct PostSessionPromptView: View {
    let prompt: PostSessionPrompt
    let isLatestMessage: Bool
    let onYes: () -> Void
    let onNo: () -> Void
    
    // MARK: - State
    
    /// Which button the user tapped (nil = no selection yet).
    /// Initialized from `prompt.responded` so persisted state survives view re-creation.
    @State private var selectedResponse: Bool? = nil
    
    /// Guards against double-taps
    @State private var actionIsProcessing: Bool = false
    
    /// Controls sequential button appearance
    @State private var showYesButton: Bool = false
    @State private var showNoButton: Bool = false
    
    /// Forces preference key updates for scroll tracking
    @State private var heightUpdateCounter: Int = 0
    
    /// Whether the prompt was already responded to (from persisted model)
    private var alreadyResponded: Bool { prompt.responded }
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 12) {
            // Yes button
            if showYesButton {
                promptButton(
                    label: prompt.yesLabel,
                    isSelected: selectedResponse == true,
                    isHidden: selectedResponse == false
                ) {
                    handleYesTapped()
                }
            }
            
            // No button
            if showNoButton {
                promptButton(
                    label: prompt.noLabel,
                    isSelected: selectedResponse == false,
                    isHidden: selectedResponse == true
                ) {
                    handleNoTapped()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // Restore persisted response state so buttons render correctly after re-creation
            if alreadyResponded {
                selectedResponse = prompt.respondedYes
                actionIsProcessing = true
                showYesButton = true
                showNoButton = true
            } else if isLatestMessage {
                startAppearanceSequence()
            } else {
                // Non-latest messages: show buttons immediately
                showYesButton = true
                showNoButton = true
            }
        }
        .onChange(of: showYesButton) { oldValue, newValue in
            if newValue && !oldValue && isLatestMessage && !alreadyResponded {
                logger.aiChat("🤔 [POST_SESSION_PROMPT] Yes button appeared")
                heightUpdateCounter += 1
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
        .onChange(of: showNoButton) { oldValue, newValue in
            if newValue && !oldValue && isLatestMessage && !alreadyResponded {
                logger.aiChat("🤔 [POST_SESSION_PROMPT] No button appeared")
                heightUpdateCounter += 1
                NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
            }
        }
    }
    
    // MARK: - Button Component
    
    @ViewBuilder
    private func promptButton(
        label: String,
        isSelected: Bool,
        isHidden: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .nunitoFont(size: 16, style: .semiBold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(height: 46, alignment: .center)
                .background {
                    Group {
                        if #available(iOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.clear)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(Color.selectedLightPurple.opacity(0.69))
                                            .blendMode(.plusLighter)
                                    }
                                }
                        } else {
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
        .disabled(actionIsProcessing)
        .opacity(isHidden ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeOut(duration: 0.25), value: isHidden)
    }
    
    // MARK: - Appearance Animation
    
    private func startAppearanceSequence() {
        // Show Yes button first
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            showYesButton = true
        }
        // Show No button after sequential delay
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationConstants.sequentialItemDelay) {
            showNoButton = true
        }
    }
    
    // MARK: - Tap Handlers
    
    private func handleYesTapped() {
        guard !actionIsProcessing else { return }
        actionIsProcessing = true
        
        HapticManager.shared.impact(.light)
        logger.aiChat("🤔 [POST_SESSION_PROMPT] User tapped YES")
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedResponse = true
        }
        
        // Small delay to let the selection animation play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onYes()
        }
    }
    
    private func handleNoTapped() {
        guard !actionIsProcessing else { return }
        actionIsProcessing = true
        
        HapticManager.shared.impact(.light)
        logger.aiChat("🤔 [POST_SESSION_PROMPT] User tapped NO")
        
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedResponse = false
        }
        
        // Small delay to let the selection animation play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onNo()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PostSessionPromptView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 24) {
                Text("Would you like to keep meditating?")
                    .nunitoFont(size: 16, style: .medium)
                    .foregroundColor(.white)
                
                PostSessionPromptView(
                    prompt: .standard(),
                    isLatestMessage: true,
                    onYes: { print("Yes tapped") },
                    onNo: { print("No tapped") }
                )
            }
            .padding()
        }
    }
}
#endif
