import SwiftUI

// MARK: - Unified CTA Component

struct SenseiCTAView: View {
    // Required
    let continueTitle: String
    let onContinue: () -> Void
    
    // Optional
    let skipTitle: String?
    let onSkip: (() -> Void)?
    
    // State
    let isEnabled: Bool
    let isLoading: Bool
    let isValid: Bool  // For question validation
    @State private var isContinueTapped: Bool = false
    
    // Default values
    init(
        continueTitle: String,
        skipTitle: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        isValid: Bool = true,
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.continueTitle = continueTitle
        self.skipTitle = skipTitle
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.isValid = isValid
        self.onContinue = onContinue
        self.onSkip = onSkip
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Skip button (left) - no background/frame, wraps to 2 lines
            if let skipTitle = skipTitle {
                Button {
                    triggerHapticFeedback(style: .medium)
                    onSkip?()
                } label: {
                    Text(skipTitle)
                        .nunitoFont(size: 15, style: .regular)
                        .foregroundColor(.foregroundLightGray)
                        .underline()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 150, alignment: .center)
                        .padding(.vertical, 8)
                }
                .disabled(isLoading)
            }
            
            // Continue/Confirm button (right) - liquid glass style, never truncates
            Button {
                triggerHapticFeedback(style: .medium)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isContinueTapped = true
                }
                onContinue()
            } label: {
                Text(continueTitle)
                    .nunitoFont(size: 16, style: .semiBold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: true, vertical: false)
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
                                        // Purple tint for selected state (matching OptionButton)
                                        if isContinueTapped {
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
                                    if isContinueTapped {
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
            .disabled(!isEnabled || isLoading || !isValid)
            .opacity((!isEnabled || !isValid) ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isContinueTapped)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: MessageHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
            }
        )
        .onAppear {
            logger.aiChat("🧠 AI_SCROLL: SenseiCTAView appeared - posting scroll trigger notification")
            // Post notification to trigger scroll directly (backup to preference keys)
            NotificationCenter.default.post(name: .aiScrollTrigger, object: nil)
        }
    }
    
    // MARK: - Helper Functions
    
    private func triggerHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        HapticManager.shared.impact(style)
    }
}

