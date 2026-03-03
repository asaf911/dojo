import SwiftUI

// MARK: - Chat Input Component

struct AIChatInput: View {
    @ObservedObject var conversationState: AIConversationState
    @ObservedObject var manager: AIRequestManager
    @ObservedObject var keyboardController: ChatKeyboardController
    
    @FocusState private var textFieldFocused: Bool
    
    let onSend: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 19) {
            // Text input
            TextField("Message Sensei", text: $conversationState.userInput, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(.nunito(size: 16, style: .regular))
                .disabled(manager.isLoading)
                .focused($textFieldFocused)
                .submitLabel(.send)
                .onSubmit {
                    onSend()
                }
            
            // Send button
            Button(action: {
                onSend()
            }) {
                Image(systemName: conversationState.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "arrow.up.circle" : "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(conversationState.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.3) : .dojoTurquoise)
            }
            .disabled(conversationState.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isLoading)
            .scaleEffect(manager.isLoading ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: manager.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            Group {
                if #available(iOS 26.0, *) {
                    // iOS 26+ Liquid Glass effect
                    RoundedRectangle(cornerRadius: 23)
                        .fill(Color.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 23))
                } else {
                    // Fallback for iOS 17-25
                    RoundedRectangle(cornerRadius: 23)
                        .fill(.regularMaterial)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .specularBorder(cornerRadius: 23)
        .padding(.horizontal, 16)
        // Sync FocusState with controller's derived state
        .onChange(of: keyboardController.shouldBeFocused) { _, shouldBeFocused in
            logger.aiChat("🧠 KEYBOARD_INPUT: Controller says shouldBeFocused=\(shouldBeFocused), textFieldFocused=\(textFieldFocused)")
            if textFieldFocused != shouldBeFocused {
                textFieldFocused = shouldBeFocused
            }
        }
        .onChange(of: textFieldFocused) { oldValue, newValue in
            logger.aiChat("🧠 KEYBOARD_INPUT: textFieldFocused changed \(oldValue) -> \(newValue), controller.shouldBeFocused=\(keyboardController.shouldBeFocused)")
            // Sync back to controller only for user-initiated changes
            if newValue && !keyboardController.shouldBeFocused {
                // Something (user tap or iOS auto-focus) tried to expand - ask controller
                keyboardController.userRequestedExpand()
                // If controller still says no (e.g., suppressed), immediately unfocus to prevent keyboard
                if !keyboardController.shouldBeFocused {
                    logger.aiChat("🧠 KEYBOARD_INPUT: Controller rejected expand - resetting FocusState to false")
                    textFieldFocused = false
                }
            } else if !newValue && keyboardController.shouldBeFocused {
                // Something dismissed the keyboard (scroll, tap outside, system)
                keyboardController.collapse()
            }
        }
        .onTapGesture {
            // User tapped on the input area - request expand
            keyboardController.userRequestedExpand()
        }
        .onAppear {
            // Sync initial state
            textFieldFocused = keyboardController.shouldBeFocused
        }
    }
}
