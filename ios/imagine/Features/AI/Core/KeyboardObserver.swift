import SwiftUI
import Combine

// MARK: - Keyboard Observer

/// Observes keyboard show/hide notifications and publishes keyboard state
/// Used to coordinate scroll adjustments when keyboard appears/disappears
@MainActor
final class KeyboardObserver: ObservableObject {
    /// Current keyboard height (0 when hidden)
    @Published var keyboardHeight: CGFloat = 0
    
    /// Whether keyboard is currently visible
    @Published var isKeyboardVisible: Bool = false
    
    /// Animation duration from keyboard notification
    @Published var animationDuration: TimeInterval = 0.25
    
    /// Animation curve from keyboard notification
    @Published var animationCurve: UIView.AnimationCurve = .easeInOut
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupKeyboardObservers()
    }
    
    private func setupKeyboardObservers() {
        // Keyboard will show
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardWillShow(notification)
            }
            .store(in: &cancellables)
        
        // Keyboard will change frame (handles resize during typing, emoji keyboard, etc.)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardWillChangeFrame(notification)
            }
            .store(in: &cancellables)
        
        // Keyboard will hide
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardWillHide(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        extractAnimationParameters(from: userInfo)
        
        let newHeight = keyboardFrame.height
        let wasVisible = isKeyboardVisible
        
        Task { @MainActor in
            isKeyboardVisible = true
            keyboardHeight = newHeight
            logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Will show - height=\(newHeight), wasVisible=\(wasVisible)")
        }
    }
    
    private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        extractAnimationParameters(from: userInfo)
        
        // Only update if keyboard is on screen (frame.origin.y < screen height)
        let screenHeight = UIScreen.main.bounds.height
        let isOnScreen = keyboardFrame.origin.y < screenHeight
        let newHeight = keyboardFrame.height
        let currentHeight = keyboardHeight
        
        if isOnScreen, newHeight != currentHeight {
            Task { @MainActor in
                logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Frame changed - height=\(currentHeight) -> \(newHeight)")
                keyboardHeight = newHeight
                isKeyboardVisible = true
            }
        }
    }
    
    private func handleKeyboardWillHide(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        extractAnimationParameters(from: userInfo)
        
        let previousHeight = keyboardHeight
        logger.aiChat("🧠 AI_DEBUG [KEYBOARD]: Will hide - was height=\(previousHeight)")
        
        Task { @MainActor in
            isKeyboardVisible = false
            keyboardHeight = 0
        }
    }
    
    private func extractAnimationParameters(from userInfo: [AnyHashable: Any]) {
        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
        let curve = curveValue.flatMap { UIView.AnimationCurve(rawValue: $0) }
        
        Task { @MainActor in
            if let duration {
                animationDuration = duration
            }
            if let curve {
                animationCurve = curve
            }
        }
    }
    
    /// SwiftUI animation that matches keyboard animation curve and duration
    var swiftUIAnimation: Animation {
        switch animationCurve {
        case .easeIn:
            return .easeIn(duration: animationDuration)
        case .easeOut:
            return .easeOut(duration: animationDuration)
        case .easeInOut:
            return .easeInOut(duration: animationDuration)
        case .linear:
            return .linear(duration: animationDuration)
        @unknown default:
            return .easeInOut(duration: animationDuration)
        }
    }
}

