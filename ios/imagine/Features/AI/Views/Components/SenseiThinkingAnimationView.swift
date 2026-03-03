import SwiftUI

// MARK: - Sensei Thinking Animation Component

struct SenseiThinkingAnimationView: View {
    // Configuration
    @Binding var isActive: Bool
    @Binding var intent: String?
    let totalDuration: TimeInterval? // Optional auto-dismiss
    
    // Internal state for animations
    @State private var isVisible: Bool = false
    @State private var autoDismissTask: Task<Void, Never>?
    
    // MARK: - Text Configuration
    
    /// Returns the appropriate text based on classified intent
    static func text(for intent: String?) -> String {
        guard let intent = intent else {
            // Before classification
            return "Thinking..."
        }
        
        // After classification - action-oriented text
        switch intent {
        case "meditation":
            return "Designing session..."
        case "explain":
            return "Gathering thoughts..."
        case "app_help":
            return "Checking..."
        default:
            // conversation, out_of_scope, etc.
            return "Writing..."
        }
    }
    
    /// Current text based on intent
    private var currentText: String {
        Self.text(for: intent)
    }
    
    // Default initializer
    init(
        isActive: Binding<Bool>,
        intent: Binding<String?> = .constant(nil),
        totalDuration: TimeInterval? = nil
    ) {
        self._isActive = isActive
        self._intent = intent
        self.totalDuration = totalDuration
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Sensei icon
            Image("tabSensei")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
            
            // Animated gradient text
            animatedGradientText
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .onChange(of: isActive) { oldValue, newValue in
            if newValue {
                showAnimation()
            } else {
                hideAnimation()
            }
        }
        .onAppear {
            if isActive {
                showAnimation()
            }
        }
        .onDisappear {
            cleanup()
        }
        .accessibilityLabel("Sensei is thinking")
        .accessibilityAddTraits(.isStaticText)
    }
    
    // MARK: - Animated Gradient Text
    
    private var animatedGradientText: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let normalizedTime = (time / AnimationConstants.senseiThinkingGradientSpeed).truncatingRemainder(dividingBy: 1.0)
            let offset = normalizedTime // Range: 0 to 1
            
            Text(currentText)
                .nunitoFont(size: 16, style: .medium)
                .foregroundColor(.clear)
                .background(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: .white, location: 0.0),
                            Gradient.Stop(color: .white, location: max(0, offset - 0.15)),
                            Gradient.Stop(color: .selectedLightPurple, location: offset),
                            Gradient.Stop(color: .white, location: min(1, offset + 0.15)),
                            Gradient.Stop(color: .white, location: 1.0)
                        ],
                        startPoint: UnitPoint(x: 0, y: 0.5),
                        endPoint: UnitPoint(x: 1, y: 0.5)
                    )
                )
                .mask(
                    Text(currentText)
                        .nunitoFont(size: 16, style: .medium)
                )
                .animation(.easeInOut(duration: 0.3), value: currentText)
        }
    }
    
    // MARK: - Animation Control
    
    private func showAnimation() {
        guard !isVisible else { return }
        
        // Fade in
        withAnimation(.easeOut(duration: AnimationConstants.senseiThinkingFadeDuration)) {
            isVisible = true
        }
        
        // Setup auto-dismiss if needed
        if let totalDuration = totalDuration {
            autoDismissTask?.cancel()
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(totalDuration * 1_000_000_000))
                if isActive {
                    isActive = false
                }
            }
        }
    }
    
    private func hideAnimation() {
        guard isVisible else { return }
        
        cleanup()
        
        withAnimation(.easeIn(duration: AnimationConstants.senseiThinkingFadeDuration)) {
            isVisible = false
        }
    }
    
    private func cleanup() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
}
