//
//  TimerCreationView.swift
//  Dojo
//
//  Create screen: `TimerView` — duration, cues, soundscape, binaural, play/share.
//

import SwiftUI
import UIKit

struct TimerView: View {
    @State private var selectedMinutes: Int = 5
    @State private var navigateToCountdown = false
    @State private var selectedBackgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: "")
    @State private var cueSettings: [CueSetting] = []
    @State private var selectedBinauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
    @State private var isDeepLinked: Bool = false  // Only used to pass along the flag
    @State private var isDataLoaded: Bool = false  // Track if data is loaded
    @State private var meditationTitle: String? = nil  // Title from AI or deep link

    // State for sharing
    @State private var showShareSheet: Bool = false
    @State private var shareLink: URL? = nil // Add a state variable to hold the current share link
    



    @Environment(\.presentationMode) var presentationMode
    @Environment(\.toggleMenu) private var toggleMenu
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @StateObject private var catalogsManager = CatalogsManager.shared

    var body: some View {
        DojoScreenContainer(
            headerTitle: "Create",
            headerSubtitle: "Design a meditation that fits you",
            backgroundImageName: "timerBackground",
            backAction: {
                if isDeepLinked {
                    // Just do nothing for deep links as we're already in the MainContainerView
                } else {
                    presentationMode.wrappedValue.dismiss()
                }
            },
            showBackButton: false,
            menuAction: toggleMenu,
            showMenuButton: true
        ) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Spacer().frame(height: 5)
                    CountdownPicker(minutes: $selectedMinutes)
                        .frame(height: 200)
                        .clipped()

                    DividerView()

                    CueConfigurationView(selectedMinutes: $selectedMinutes, cueSettings: $cueSettings)

                    DividerView()

                    BackgroundSoundSelectionView(selectedSound: $selectedBackgroundSound)
                    BinauralBeatSelectionView(selectedBeat: $selectedBinauralBeat)
                    
                    // HStack containing the Share and Play buttons side by side.
                    HStack(spacing: 14) {
                        // Share Button: icon only.
                        Button(action: {
                            handleShareButtonTap()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .foregroundColor(isDataLoaded ? Color.dojoTurquoise : Color.gray)
                                .padding()
                        }
                        .disabled(!isDataLoaded)
                        
                        // Play Button - navigates to player immediately, assets prepared on Player screen
                        Button(action: handlePlayButtonTap) {
                            Text("Timer_PlayButton")
                                .nunitoFont(size: 16, style: .bold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(.foregroundDarkBlue)
                            .background(Color.dojoTurquoise)
                            .cornerRadius(25)
                        }
                    }
                    
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 120)
            }
            .topFadeMask(height: 5)
        }
        .onAppear {
            // Always fetch fresh catalogs when online; fetchCatalogs falls back to cache when offline
            catalogsManager.fetchCatalogs(triggerContext: "TimerCreationView|onAppear preload") { success in
                if success {
                    logger.eventMessage("Catalogs loaded successfully")
                }
                checkDataLoaded()
            }
            
            // Check for deep link settings immediately on appear
            if let timerSetting = navigationCoordinator.deepLinkedMeditationConfiguration {
                print("🎛️ TimerView onAppear: Found deep linked meditation configuration - duration: \(timerSetting.duration)")
                logger.eventMessage("TimerView onAppear: Found deep linked meditation configuration")
                processDeepLinkSettings(timerSetting)
            } else {
                print("🎛️ TimerView onAppear: No deep linked meditation configuration found")
                logger.eventMessage("TimerView onAppear: No deep linked meditation configuration found")
                // Only load saved configuration if no deep-linked setting is pending
                loadSavedConfiguration()
            }
            
            // Check if data is already loaded
            checkDataLoaded()
            
            // Generate initial share link
            updateShareLink()
        }
        // Re-add the onReceive handler for deepLinkedMeditationConfiguration as a backup
        // in case the settings are set after the view appears
        .onReceive(navigationCoordinator.$deepLinkedMeditationConfiguration) { timerSetting in
            if let timerSetting = timerSetting {
                logger.eventMessage("TimerView onReceive: Received deep linked meditation configuration")
                processDeepLinkSettings(timerSetting)
            }
        }
        .onDisappear {
            saveConfiguration()
        }
        .navigationBarBackButtonHidden(true)
        .swipeBackEntireScreen {
            if isDeepLinked {
                // Do nothing on swipe back for deep linked view
            } else {
                presentationMode.wrappedValue.dismiss()
            }
        }
        .background(InteractivePopGestureSetter())
        .sheet(isPresented: $showShareSheet) {
            if let url = shareLink {
                // Passing the URL's string representation avoids sandbox extension errors.
                ActivityViewController(activityItems: [shareMessage, url.absoluteString])
            } else {
                Text("No share link generated.")
                    .nunitoFont(size: 16, style: .medium)
                    .padding()
            }
        }

        .onChange(of: selectedMinutes) { _, _ in
            clampFractionalDurationsToSessionCap()
            updateShareLink()
        }
        .onChange(of: selectedBackgroundSound) { _, _ in
            updateShareLink()
        }
        .onChange(of: cueSettings) { _, _ in
            updateShareLink()
        }
    }
    
    // MARK: - Persistence Helpers
    
    private func processDeepLinkSettings(_ timerSetting: MeditationConfiguration) {
        print("🎛️ TimerView: Processing deep link settings - duration: \(timerSetting.duration), sound: \(timerSetting.backgroundSound.name), title: \(timerSetting.title ?? "nil")")
        DispatchQueue.main.async {
            selectedMinutes = timerSetting.duration
            selectedBackgroundSound = timerSetting.backgroundSound
            cueSettings = timerSetting.cueSettings
            meditationTitle = timerSetting.title
            if let beat = timerSetting.binauralBeat {
                selectedBinauralBeat = beat
                logger.eventMessage("TimerView: Applied deep link binaural beat: \(beat.name)")
            } else {
                let forced = navigationCoordinator.timerBinauralBeat
                if forced.id != "None" {
                    selectedBinauralBeat = forced
                    logger.eventMessage("TimerView: Applied forced navigation binaural beat: \(forced.name)")
                } else {
                    logger.eventMessage("TimerView: No binaural beat found in deep link; keeping current selection: \(selectedBinauralBeat.name)")
                }
            }
            navigationCoordinator.deepLinkedMeditationConfiguration = nil
            isDeepLinked = true
            print("🎛️ TimerView: Successfully applied deep linked timer settings")
            logger.eventMessage("TimerView: Applied deep linked timer setting - duration: \(timerSetting.duration), sound: \(timerSetting.backgroundSound.name), title: \(timerSetting.title ?? "nil")")

            clampFractionalDurationsToSessionCap()
            // Update share link after applying deep link settings
            updateShareLink()
        }
    }

    /// Keeps fractional module duration ≤ session length so server-side expansion fits the relax-phase window.
    private func clampFractionalDurationsToSessionCap() {
        let cap = max(1, selectedMinutes)
        for i in cueSettings.indices where cueSettings[i].allowsManualFractionalDuration {
            if let fd = cueSettings[i].fractionalDuration, fd > cap {
                cueSettings[i].fractionalDuration = cap
            }
        }
    }
    
    private func currentTimerSetting() -> MeditationConfiguration {
        return MeditationConfiguration(
            duration: selectedMinutes,
            backgroundSound: selectedBackgroundSound,
            cueSettings: cueSettings,
            title: nil,
            binauralBeat: selectedBinauralBeat
        )
    }
    
    private func saveConfiguration() {
        let setting = currentTimerSetting()
        SharedUserStorage.save(value: setting, forKey: .timerSettings)
        logger.eventMessage("TimerView: Saved timer configuration: \(setting)")
        
        // Update share link after saving configuration
        updateShareLink()
    }
    
    private func loadSavedConfiguration() {
        if let savedSetting = SharedUserStorage.retrieve(forKey: .timerSettings, as: MeditationConfiguration.self) {
            selectedMinutes = savedSetting.duration
            selectedBackgroundSound = savedSetting.backgroundSound
            cueSettings = savedSetting.cueSettings
            // Restore binaural beat if present in saved config; otherwise keep current
            if let beat = savedSetting.binauralBeat {
                selectedBinauralBeat = beat
            }
            logger.eventMessage("TimerView: Loaded saved timer configuration: \(savedSetting)")

            clampFractionalDurationsToSessionCap()
            // Update share link after loading configuration
            updateShareLink()
        }
    }
    
    // MARK: - Share Link Generation and Message
    
    // Add a method to update the share link whenever timer settings change
    private func updateShareLink() {
        shareLink = generateShareLink()
        if let link = shareLink {
            logger.eventMessage("Share link updated: \(link.absoluteString)")
        }
    }
    
    private func generateShareLink() -> URL? {
        let baseURL = Config.oneLinkBaseURL
        var components = URLComponents(string: baseURL)
        // Subtract colon and comma from allowed set so that they are percent-encoded.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":,"))
        let durValue = "\(selectedMinutes)".addingPercentEncoding(withAllowedCharacters: allowed)
        let bsValue = selectedBackgroundSound.id
        let bsEncoded = bsValue.addingPercentEncoding(withAllowedCharacters: allowed)
        let cuRawValue = cueSettings.compactMap { cueSetting -> String? in
            let id = cueSetting.cue.id
            let trigger: String
            switch cueSetting.triggerType {
            case .start:
                trigger = "S"
            case .end:
                trigger = "E"
            case .minute:
                if let minute = cueSetting.minute {
                    trigger = "\(minute)"
                } else {
                    trigger = ""
                }
            case .second:
                if let sec = cueSetting.minute {
                    trigger = "s\(sec)"
                } else {
                    trigger = ""
                }
            }
            return "\(id):\(trigger)"
        }.joined(separator: ",")
        let cuEncoded = cuRawValue.addingPercentEncoding(withAllowedCharacters: allowed)
        let bbValue = selectedBinauralBeat.id
        let bbEncoded = bbValue.addingPercentEncoding(withAllowedCharacters: allowed)
        components?.queryItems = [
            URLQueryItem(name: "dur", value: durValue),
            URLQueryItem(name: "bs", value: bsEncoded),
            URLQueryItem(name: "bb", value: bbEncoded),
            URLQueryItem(name: "cu", value: cuEncoded),
            URLQueryItem(name: "c", value: "custom"),
            URLQueryItem(name: "af_sub1", value: "Custom Meditation")
        ]
        return components?.url
    }
    
    private var shareMessage: String {
        let cueNames = cueSettings.map { $0.cue.name }.joined(separator: ", ")
        return "I just created a custom \(selectedMinutes)-minute meditation session with \"\(selectedBackgroundSound.name)\" playing in the background and sound cues (like \(cueNames)) to guide you through. Made just for you!"
    }

    // MARK: - Play Flow Helpers

    private func buildLocalTimerConfig() -> TimerSessionConfig {
        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        #if DEBUG
        print("[TimerCreationView] buildLocalTimerConfig offline voiceId=\(voiceId) cueCount=\(cueSettings.count)")
        #endif
        return MeditationConfiguration.makeTimerSessionConfig(
            durationMinutes: selectedMinutes,
            backgroundSound: selectedBackgroundSound,
            binauralBeat: selectedBinauralBeat,
            cueSettings: cueSettings,
            title: nil,
            voiceId: voiceId,
            isDeepLinked: false,
            description: nil
        )
    }

    private func performPlayWithConfig(_ timerConfig: TimerSessionConfig) {
        if SessionContextManager.shared.isAIOriginated {
            SessionContextManager.shared.markUserModified(timerConfig: timerConfig)
        } else {
            SessionContextManager.shared.setupCustomMeditationSession(
                entryPoint: .createScreen,
                timerConfig: timerConfig,
                origin: .userSelected,
                customizationLevel: .none
            )
        }
        navigationCoordinator.navigateToTimerCountdown(
            totalMinutes: timerConfig.minutes,
            playbackDurationSeconds: timerConfig.playbackDurationSeconds,
            backgroundSound: timerConfig.backgroundSound,
            cueSettings: timerConfig.cueSettings,
            binauralBeat: timerConfig.binauralBeat,
            isDeepLinked: isDeepLinked,
            title: timerConfig.title ?? meditationTitle
        )
    }

    // MARK: - Data Loading

    private func checkDataLoaded() {
        isDataLoaded = !catalogsManager.sounds.isEmpty && !catalogsManager.cues.isEmpty && !catalogsManager.beats.isEmpty
        logger.eventMessage("Data loaded status: \(isDataLoaded)")
    }

    // MARK: - Button Actions

    private func handlePlayButtonTap() {
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=TimerCreationView")
            #endif
            navigationCoordinator.subscriptionSource = .createScreen
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        GeneralBackgroundMusicController.shared.fadeOutForPractice()
        if !ConnectivityHelper.isConnectedToInternet() {
            performPlayWithConfig(buildLocalTimerConfig())
        } else {
            Task {
                do {
                    let package = try await MeditationsService.shared.createMeditationManual(
                        duration: selectedMinutes,
                        backgroundSoundId: selectedBackgroundSound.id,
                        binauralBeatId: selectedBinauralBeat.id == "None" ? nil : selectedBinauralBeat.id,
                        cueSettings: cueSettings,
                        triggerContext: "TimerCreationView|Create tapped"
                    )
                    await MainActor.run {
                        performPlayWithConfig(package.toTimerSessionConfig(isDeepLinked: isDeepLinked))
                    }
                } catch {
                    print("[Server][Meditations] createMeditationManual: failure trigger=TimerCreationView|Create tapped offline fallback - \(error.localizedDescription)")
                    await MainActor.run {
                        performPlayWithConfig(buildLocalTimerConfig())
                    }
                }
            }
        }
    }

    private func handleShareButtonTap() {
        // Ensure share link is up to date
        updateShareLink()
        
        if let link = shareLink {
            logger.eventMessage("Share button tapped with link: \(link.absoluteString)")
        } else {
            logger.errorMessage("No share link generated.")
        }
        showShareSheet = true
    }
}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        TimerView()
            .environmentObject(NavigationCoordinator())
    }
}
