//
//  ExploreView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-13
//

import SwiftUI

struct ExploreView: View {
    @Binding var showCommunitySheet: Bool
    @Binding var source: String?

    @State private var audioFiles: [AudioFile] = []

    // Observables
    @EnvironmentObject var audioPlayerManager: AudioPlayerManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @ObservedObject var practiceManager = PracticeManager.shared
    @ObservedObject var bpmTracker = PracticeBPMTracker.shared
    
    // Menu toggle environment
    @Environment(\.toggleMenu) private var toggleMenu

    let userName = SharedUserStorage.retrieve(forKey: .userName, as: String.self)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Use presentationMode for the custom back button.
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            DojoScreenContainer(
                headerTitle: "Meditations",
                headerSubtitle: nil,
                backgroundImageName: "ExploreBackground",
                backAction: { presentationMode.wrappedValue.dismiss() },
                showBackButton: false,
                backgroundDarkeningOpacity: 0.2,
                menuAction: toggleMenu,
                showMenuButton: true
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    ExploreGalleryView(
                        audioFiles: audioFiles.filter {
                            $0.category == .deepdive || $0.category == .routines
                        },
                        selectedFile: $audioPlayerManager.selectedFile,
                        audioPlayerManager: audioPlayerManager
                    )
                }
                .padding(.horizontal, 26)
            }
        }
        .onFirstAppear {
            fetchSubscriptionStatus()
            AppFunctions.loadAudioFiles { loaded in
                self.audioFiles = loaded
            }
        }
        .onDisappear {
        }
        .navigationBarBackButtonHidden(true)
        // Enable interactive pop by embedding an accessor view that sets the gesture delegate.
        .background(InteractivePopGestureSetter())
    }

    // MARK: - Helper Functions for ExploreView

    private func shouldShowPracticeSummary() -> Bool {
        return audioPlayerManager.didJustFinishSession
    }

    private func completionRatePercent() -> Double {
        guard audioPlayerManager.totalDuration > 0 else { return 0 }
        return (audioPlayerManager.currentTime / audioPlayerManager.totalDuration) * 100
    }

    private func practiceDurationMinutes() -> Int {
        Int(ceil(audioPlayerManager.totalDuration / 60.0))
    }

    private func finalStartBPM() -> Double {
        return bpmTracker.startBPM
    }

    private func finalEndBPM() -> Double {
        return bpmTracker.endBPM
    }

    private func dismissSummary() {
        withAnimation {
            navigationCoordinator.resetPracticeRating()
            bpmTracker.resetData()
            audioPlayerManager.didJustFinishSession = false
            navigationCoordinator.showPracticeRating = false
        }
    }

    private func fetchSubscriptionStatus() {
        subscriptionManager.refreshSubscriptionStatus()
    }
}

struct ExploreView_Previews: PreviewProvider {
    @State static var showCommunitySheet = false
    @State static var source: String? = nil

    static var previews: some View {
        let subscriptionManager = SubscriptionManager(isUserSubscribed: false)
        let navigationCoordinator = NavigationCoordinator()
        let audioPlayerManager = AudioPlayerManager()

        return ExploreView(showCommunitySheet: .constant(false), source: .constant(nil))
            .environmentObject(subscriptionManager)
            .environmentObject(navigationCoordinator)
            .environmentObject(audioPlayerManager)
            .environmentObject(PracticeManager.shared)
            .background(Color.backgroundDarkPurple)
    }
}

// MARK: - Interactive Pop Gesture Setter
struct InteractivePopGestureSetter: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            if let navigationController = controller.navigationController {
                navigationController.interactivePopGestureRecognizer?.delegate = context.coordinator
                navigationController.interactivePopGestureRecognizer?.isEnabled = true
            }
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let navController = gestureRecognizer.view?.window?.rootViewController as? UINavigationController {
                return navController.viewControllers.count > 1
            }
            return true
        }
    }
}
