//
//  PracticeItemView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-23
//

import SwiftUI
import Kingfisher

// Badge views are now imported from PracticeBadges.swift

struct PracticeItemView: View {
    // The audio file whose data is to be displayed.
    let audioFile: AudioFile
    
    // Bindings and objects required to invoke PracticeTapHandler.
    @Binding var selectedFile: AudioFile?
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    @ObservedObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator

    // Determines which badge (if any) to display based on practice type and completion status.
    private var badgeView: AnyView? {
        if audioFile.category == .learn {
            // For .learn practices, show "Completed" badge if completed.
            if PracticeManager.shared.isPracticeCompleted(practiceID: audioFile.id) {
                return AnyView(CompletedBadge())
            }
        } else {
            // For other practices, show "Recently Played" badge if completed within the last week.
            if PracticeManager.shared.isPracticeRecentlyPlayed(practiceID: audioFile.id) {
                return AnyView(RecentlyPlayedBadge())
            }
        }
        
        return nil
    }

    var body: some View {
        Button(action: {
            // Add haptic feedback
            HapticManager.shared.impact(.light)
            
            // Fade out background music over 2 seconds
            GeneralBackgroundMusicController.shared.fadeOutMusic(duration: 2.0)
            
            if subscriptionManager.shouldGatePlay {
                subscriptionManager.logGateState()
                #if DEBUG
                print("📊 [SUBSCRIPTION_GATE] Play blocked — source=PracticeItemView")
                #endif
                navigationCoordinator.subscriptionSource = .explore
                navigationCoordinator.navigateTo(.subscription)
                return
            }
            
            // Set the selected file for the audio player manager
            selectedFile = audioFile
            audioPlayerManager.selectedFile = audioFile
            
            // Set up SessionContextManager for the library session
            SessionContextManager.shared.setupLibrarySession(
                entryPoint: .exploreScreen,
                audioFile: audioFile,
                origin: .userSelected
            )
            
            // Instead of navigating, show player as sheet
            navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    // Practice title
                    VStack(alignment: .leading, spacing: 4) {
                        Text(audioFile.title)
                            .nunitoFont(size: 16, style: .extraBold)
                            .foregroundColor(.selectedLightPurple)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Practice description
                        Text(audioFile.description)
                            .nunitoFont(size: 16, style: .semiBold)
                            .foregroundColor(.textForegroundGray)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // HStack with play icon and duration/badges
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.textForegroundGray)

                        Spacer()

                        HStack(spacing: 11) {
                            if let badge = badgeView {
                                badge
                            }
                            Text("\(audioFile.durations.first?.length ?? 0) min")
                                .nunitoFont(size: 14, style: .bold)
                                .foregroundColor(.white.opacity(0.88))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 30)
                .frame(width: 340, height: 172, alignment: .center)
                .surfaceBackground(cornerRadius: 24)
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 4)
                
                // DEPRECATED: Free badge muted. All users get one free meditation; subscription is prompted on 2nd session attempt.
                // Keeping code for reference. Previously showed when !subscriptionManager.shouldGatePlay.
                // if !subscriptionManager.shouldGatePlay {
                //     FreeBadge()
                //         .padding([.top, .trailing], 12)
                // }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PracticeItemView_Previews: PreviewProvider {
    static var sampleAudioFile: AudioFile = AudioFile(
        id: "sample001",
        title: "Calming Breeze",
        category: .relax,
        description: "A soothing 10-minute session to help you relax and unwind.",
        imageFile: "https://example.com/sampleImage.png",
        durations: [Duration(length: 10, fileName: "sampleFile.mp3")],
        premium: true,
        tags: ["relaxation", "mindfulness"]
    )
    
    static var previews: some View {
        PracticeItemView(
            audioFile: sampleAudioFile,
            selectedFile: .constant(nil),
            audioPlayerManager: AudioPlayerManager(),
            subscriptionManager: SubscriptionManager.shared
        )
        .environmentObject(NavigationCoordinator())
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}
