//
//  PathStepView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-04-25
//

import SwiftUI
import Kingfisher
import FirebaseAnalytics

// PathStepState is defined in PathProgressManager.swift

struct PathStepView: View {
    // The path step to display
    let pathStep: PathStep
    
    // Bindings and objects required for navigation and playback
    @Binding var selectedFile: AudioFile?
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    @ObservedObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    // Step state
    var stepState: PathStepState
    
    // MARK: - UI Configuration based on state
    
    // Colors based on state
    private var textColor: Color {
        switch stepState {
        case .completed, .locked: return .textForegroundGray
        case .next: return .foregroundLightGray
        }
    }
    
    private var titleColor: Color {
        switch stepState {
        case .completed, .locked: return .textForegroundGray
        case .next: return .textTurquoise
        }
    }
    
    private var textOpacity: Double {
        return (stepState == .completed || stepState == .locked) ? 0.35 : 1.0
    }
    
    private var strokeColor: Color {
        switch stepState {
        case .completed: return Color.textPurple.opacity(0.5)
        case .locked: return .textForegroundGray.opacity(0.5)
        case .next: return Color.textTurquoise.opacity(0.5)
        }
    }
    
    private var shadowColor: Color {
        switch stepState {
        case .completed: return Color.textPurple.opacity(0.25)
        case .locked: return .textForegroundGray.opacity(0.25)
        case .next: return Color.textTurquoise.opacity(0.25)
        }
    }
    
    var body: some View {
        ZStack {
            cardContent
                .onTapGesture {
                    if stepState != .locked {
                        handleTap()
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Private Views
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Step number
            Text("Step \(pathStep.order)")
                .font(Font.custom("Nunito", size: 16).weight(.bold))
                .foregroundColor(textColor)
                .opacity(textOpacity)
            
            // Title
            Text(pathStep.title)
                .font(Font.custom("Nunito", size: 15).weight(.bold))
                .foregroundColor(titleColor)
                .lineLimit(2)
                .opacity(textOpacity)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Lesson/Practice and duration
            HStack(spacing: 4) {
                if pathStep.id.hasPrefix("coming_soon_") {
                    // Special case for "coming soon" step
                    Text("Stay")
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                    
                    Text("tuned")
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                } else {
                    // Regular case for normal steps
                    let typeLabel = pathStep.isLesson ? "Lesson" : "Practice"
                    Text(typeLabel)
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                    
                    Text("•")
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                    
                    Text("\(pathStep.duration) min")
                        .font(Font.custom("Nunito", size: 14).italic())
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                }
            }
            
            // Status icon
            statusIcon
                .padding(.top, 4)
        }
        .frame(width: 121, alignment: .leading)
        .padding(20)
        .background(cardBackground)
        .cornerRadius(28)
        .shadow(color: shadowColor, radius: 2, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .inset(by: 0.5)
                .stroke(strokeColor, lineWidth: 1)
        )
    }
    
    private var cardBackground: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .opacity(0.95)
    }
    
    private var statusIcon: some View {
        HStack {
            switch stepState {
            case .completed:
                // Checkmark for completed state
                ZStack {
                    Circle()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.textPurple)
                        .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 4)
                    
                    Image("pathCheckmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                
                Text("Completed")
                    .font(Font.custom("Nunito", size: 12).weight(.bold))
                    .foregroundColor(.textPurple)
                    .padding(.leading, 4)
                
            case .locked:
                // Lock icon for locked state
                ZStack {
                    Circle()
                        .frame(width: 32, height: 32)
                        .foregroundColor(Color.planTop)
                        .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 4)
                    
                    Image("pathLock")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 19, height: 19)
                }
                
            case .next:
                // Play icon for next state
                ZStack(alignment: .center) {
                    Circle()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.32), radius: 3, x: 0, y: 4)
                    
                    // Using a fixed position ZStack to ensure perfect centering
                    ZStack {
                        Image(systemName: "play.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13, height: 13)
                            .offset(x: 1.5) // Fine-tuned offset for perfect centering
                            .foregroundColor(.backgroundDarkPurple)
                    }
                    .frame(width: 32, height: 32) // Match the circle size
                }
            }
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleTap() {
        // Add haptic feedback
        HapticManager.shared.impact(.light)
        
        // Track the step view analytics event
        PathAnalyticsHandler.shared.trackStepViewed(step: pathStep)
        
        // If locked, don't proceed
        if stepState == .locked {
            return
        }
        
        // Fade out background music
        GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
        
        // Check subscription gate (post-first-session, not subscribed)
        let audioFile = pathStep.toAudioFile()
        if subscriptionManager.shouldGatePlay {
            subscriptionManager.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=PathStepView")
            #endif
            navigationCoordinator.subscriptionSource = .pathStep
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        
        // Set the selected file and navigate
        selectedFile = audioFile
        audioPlayerManager.selectedFile = audioFile
        
        // Set up SessionContextManager for the path session
        SessionContextManager.shared.setupPathSession(
            entryPoint: .pathScreen,
            pathStep: pathStep,
            origin: .userSelected
        )
        
        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
    }
}

struct PathStepView_Previews: PreviewProvider {
    static var samplePathStep: PathStep = PathStep(
        id: "step_1",
        title: "What Is Meditation?",
        description: "Begin your journey with the fundamentals of meditation",
        audioUrl: "gs://imagine-c6162.appspot.com/Path/Step_1-What_Is_Meditation.mp3",
        duration: 5,
        imageUrl: "gs://imagine-c6162.appspot.com/practice_images/Deep Body Scan.png",
        order: 1,
        premium: false,
        isLesson: true
    )
    
    static var previews: some View {
        Group {
            PathStepView(
                pathStep: samplePathStep,
                selectedFile: .constant(nil),
                audioPlayerManager: AudioPlayerManager(),
                subscriptionManager: SubscriptionManager.shared,
                stepState: .next
            )
            .previewDisplayName("Next Step")
            
            PathStepView(
                pathStep: samplePathStep,
                selectedFile: .constant(nil),
                audioPlayerManager: AudioPlayerManager(),
                subscriptionManager: SubscriptionManager.shared,
                stepState: .completed
            )
            .previewDisplayName("Completed Step")
            
            PathStepView(
                pathStep: samplePathStep,
                selectedFile: .constant(nil),
                audioPlayerManager: AudioPlayerManager(),
                subscriptionManager: SubscriptionManager.shared,
                stepState: .locked
            )
            .previewDisplayName("Locked Step")
        }
        .environmentObject(NavigationCoordinator())
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}
