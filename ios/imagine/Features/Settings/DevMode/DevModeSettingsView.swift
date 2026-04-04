//
//  DevModeSettingsView.swift
//  imagine
//
//  Created by Cursor on 2/4/26.
//
//  Dev mode settings for journey phase skipping.
//  Extracted from SettingsView for cleaner separation.
//

import SwiftUI

/// Dev mode settings view for journey phase skipping and testing.
struct DevModeSettingsView: View {
    
    @StateObject private var skipService = DevModeSkipService.shared
    @ObservedObject private var journeyManager = ProductJourneyManager.shared
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    @State private var selectedDestination: JourneySkipDestination = .learningPhaseStart
    
    /// Callback for the "Test New User" action (handled by parent for alert state)
    var onTestNewUser: (() -> Void)?
    
    @State private var selectedVoiceId: String = "Asaf"
    @State private var useDevServer: Bool = false
    @State private var showFractionalScreen: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            devModeHeader
            serverCard
            fractionalModulesCard
            currentStateCard
            narrationVoiceCard
            skipDestinationCard
            actionButtons
        }
        .onAppear {
            initializeSelectedDestination()
            selectedVoiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
            useDevServer = SharedUserStorage.retrieve(forKey: .useDevServer, as: Bool.self, defaultValue: false)
        }
    }
    
    // MARK: - Header
    
    private var devModeHeader: some View {
        HStack {
            Image(systemName: "gear.circle.fill")
                .foregroundColor(.dojoTurquoise)
            Text("Developer Mode Active")
                .nunitoFont(size: 14, style: .bold)
                .foregroundColor(.dojoTurquoise)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Server Card
    
    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.dojoTurquoise)
            
            HStack {
                Text("Use Dev Server")
                    .nunitoFont(size: 14, style: .regular)
                    .foregroundColor(.foregroundLightGray)
                Spacer()
                Toggle("", isOn: $useDevServer)
                    .tint(.dojoTurquoise)
                    .labelsHidden()
                    .onChange(of: useDevServer) { _, newValue in
                        SharedUserStorage.save(value: newValue, forKey: .useDevServer)
                        print("[Server][Config] Toggled to server=\(newValue ? "Dev" : "Production")")
                    }
            }
            
            Text(useDevServer ? "Dev (imaginedev-e5fd3)" : "Production (imagine-c6162)")
                .nunitoFont(size: 12, style: .regular)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.backgroundPurple)
        .cornerRadius(12)
    }

    // MARK: - Fractional Modules Card

    private var fractionalModulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fractional Modules (MVP)")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.dojoTurquoise)

            Text("Test runtime-composed Nostril Focus from atomic clips.")
                .nunitoFont(size: 12, style: .regular)
                .foregroundColor(.white.opacity(0.5))

            Button {
                showFractionalScreen = true
            } label: {
                Text("Open Fractional NF")
                    .nunitoFont(size: 14, style: .bold)
                    .foregroundColor(.backgroundDarkPurple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.dojoTurquoise)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.backgroundPurple)
        .cornerRadius(12)
        .sheet(isPresented: $showFractionalScreen) {
            FractionalModules.Screen()
                .environmentObject(navigationCoordinator)
        }
    }
    
    // MARK: - Current State Card
    
    private var currentStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current State")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.dojoTurquoise)
            
            stateRow("Phase", journeyManager.currentPhase.displayName)
            stateRow("Path Progress", "\(PathProgressManager.shared.completedStepCount)/\(PathProgressManager.shared.totalStepCount) steps")
            stateRow("Routines", "\(journeyManager.getRoutineCompletionCount())/3")
            
            // Verification feedback
            if let result = skipService.lastSkipResult {
                verificationFeedback(result)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.backgroundPurple)
        .cornerRadius(12)
    }
    
    private func stateRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.foregroundLightGray)
            Spacer()
            Text(value)
                .nunitoFont(size: 14, style: .bold)
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private func verificationFeedback(_ result: DevModeSkipResult) -> some View {
        switch result {
        case .success(let destination, let verification):
            HStack(spacing: 6) {
                Image(systemName: verification.allPassed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(verification.allPassed ? .green : .orange)
                Text("\(destination.displayName): \(verification.summary)")
                    .nunitoFont(size: 12, style: .regular)
                    .foregroundColor(verification.allPassed ? .green : .orange)
            }
            .padding(.top, 4)
            
        case .failure(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .nunitoFont(size: 12, style: .regular)
                    .foregroundColor(.red)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Narration Voice Card

    private var narrationVoiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Narration Voice")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.dojoTurquoise)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice:")
                    .nunitoFont(size: 14, style: .regular)
                    .foregroundColor(.foregroundLightGray)

                Picker("", selection: $selectedVoiceId) {
                    Text("Asaf").tag("Asaf")
                    Text("Dan").tag("Dan")
                }
                .pickerStyle(.menu)
                .tint(.dojoTurquoise)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedVoiceId) { _, newValue in
                    SharedUserStorage.save(value: newValue, forKey: .narrationVoiceId)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.backgroundPurple)
        .cornerRadius(12)
    }

    // MARK: - Skip Destination Card

    private var skipDestinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skip to Destination")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.dojoTurquoise)
            
            // Destination picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination:")
                    .nunitoFont(size: 14, style: .regular)
                    .foregroundColor(.foregroundLightGray)
                
                Picker("", selection: $selectedDestination) {
                    ForEach(JourneySkipDestination.allCases, id: \.self) { dest in
                        Text(dest.displayName).tag(dest)
                    }
                }
                .pickerStyle(.menu)
                .tint(.dojoTurquoise)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(selectedDestination.stateDescription)
                    .nunitoFont(size: 12, style: .regular)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Skip button
            Button {
                performSkip()
            } label: {
                HStack(spacing: 8) {
                    if skipService.isSkipping {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "forward.fill")
                    }
                    Text(skipService.isSkipping ? "Skipping..." : "Skip to Destination")
                        .nunitoFont(size: 14, style: .semiBold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.dojoTurquoise)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(skipService.isSkipping)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.backgroundPurple)
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            // Reset Journey
            SettingsActionButton(
                title: "Reset Journey (Keep UID)",
                systemImageName: "arrow.counterclockwise.circle.fill",
                action: {
                    Task {
                        await skipService.skipTo(.onboardingStart)
                        selectedDestination = .onboardingStart
                    }
                }
            )
            
            // Test New User (delegates to parent for alert handling)
            if let onTestNewUser = onTestNewUser {
                SettingsActionButton(
                    title: "Test New User (Clear UID)",
                    systemImageName: "person.badge.plus",
                    textColor: .textOrange,
                    backgroundColor: .textOrange.opacity(0.15),
                    action: onTestNewUser
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func initializeSelectedDestination() {
        switch journeyManager.currentPhase {
        case .onboarding:
            selectedDestination = .onboardingStart
        case .subscription:
            selectedDestination = .subscriptionStart
        case .path:
            selectedDestination = .learningPhaseStart
        case .dailyRoutines:
            selectedDestination = .personalizedPhaseStart
        case .customization:
            selectedDestination = .customPractices
        }
    }
    
    private func performSkip() {
        Task {
            let result = await skipService.skipTo(selectedDestination)
            
            // Handle navigation after skip
            if case .success(let dest, _) = result {
                if dest.targetPhase.isInAppPhase {
                    navigationCoordinator.currentView = .main
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SelectTab"),
                        object: 0
                    )
                }
                // Pre-app phases auto-navigate via ContentView observation
            }
        }
    }
    
}

// MARK: - Preview

#if DEBUG
struct DevModeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DevModeSettingsView(
            onTestNewUser: { print("Test new user tapped") }
        )
        .environmentObject(NavigationCoordinator())
        .background(Color.backgroundNavy)
    }
}
#endif
