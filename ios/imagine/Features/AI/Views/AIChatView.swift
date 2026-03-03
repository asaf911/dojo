import SwiftUI

// MARK: - Main AI Chat View (Simplified)

struct AIChatView: View {
    @StateObject private var conversationState = AIConversationState()
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        AIChatContainerView(conversationState: conversationState)
            .navigationBarHidden(true)
            .onAppear {
                // Restore conversation context so chat remains in context across re-presentations
                conversationState.loadIfNeeded()
            }
            .onDisappear {
                // Background music management is handled by actual meditation sessions
            }
    }
}

// Preview removed to reduce compile overhead