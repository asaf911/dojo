//
//  TimerCreationView.swift
//  Dojo
//
//  Create screen: `TimerView` — duration, cues, soundscape, binaural, play/share.
//

import SwiftUI
import UIKit

/// `true` when this process is an Xcode SwiftUI preview (`XCODE_RUNNING_FOR_PREVIEWS`).
private enum XcodePreviewRuntime {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

struct TimerView: View {
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

    /// Practice length derived from fractional module durations (and reconciled cue triggers).
    private var sessionPracticeMinutes: Int {
        cueSettings.computedPracticeMinutesForCreateScreen()
    }

    var body: some View {
        DojoScreenContainer(
            headerTitle: "Create",
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
                    SessionLengthReadout(
                        practiceMinutes: sessionPracticeMinutes,
                        stepCount: cueSettings.count
                    )
                    .padding(.top, 4)

                    DividerView()

                    CueConfigurationView(
                        practiceMinutes: sessionPracticeMinutes,
                        cueSettings: $cueSettings
                    )

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
            // Lets nested `List` reorder previews extend past the scroll view during the initial lift.
            .scrollClipDisabled(true)
            .topFadeMask(height: 5)
        }
        .onAppear {
            if XcodePreviewRuntime.isActive {
                SharedUserStorage.save(value: true, forKey: .useDevServer)
            }
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
                // Previews: skip persisted timer rows (stale prod/local sessions) and always use dev catalogs.
                if !XcodePreviewRuntime.isActive {
                    loadSavedConfiguration()
                }
            }
            
            // Check if data is already loaded
            checkDataLoaded()

            // Generate initial share link (also reconciles cue rows to the derived session length).
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
            if !XcodePreviewRuntime.isActive {
                saveConfiguration()
            }
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
                // Pass `URL` as its own item so Messages and other targets keep the full link (including long `plan=`).
                ActivityViewController(activityItems: [shareMessage, url])
            } else {
                Text("No share link generated.")
                    .nunitoFont(size: 16, style: .medium)
                    .padding()
            }
        }

        .onChange(of: selectedBackgroundSound) { _, _ in
            updateShareLink()
        }
        .onChange(of: cueSettings) { _, newValue in
            #if DEBUG
            print("AI_debug [TimerView] onChange cueSettings count=\(newValue.count) cueIds=\(newValue.map(\.cue.id).joined(separator: ","))")
            #endif
            updateShareLink()
        }
    }

    private func syncSessionFromCues() {
        #if DEBUG
        let before = cueSettings.count
        #endif
        var next = cueSettings
        next.reconcileCreateScreenAutoSession()
        cueSettings = next
        #if DEBUG
        print("AI_debug [TimerView] syncSessionFromCues before=\(before) after=\(cueSettings.count)")
        #endif
    }
    
    // MARK: - Persistence Helpers
    
    private func processDeepLinkSettings(_ timerSetting: MeditationConfiguration) {
        print("🎛️ TimerView: Processing deep link settings - duration: \(timerSetting.duration), sound: \(timerSetting.backgroundSound.name), title: \(timerSetting.title ?? "nil")")
        DispatchQueue.main.async {
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

            // Update share link after applying deep link settings
            updateShareLink()
        }
    }
    
    private func currentTimerSetting() -> MeditationConfiguration {
        return MeditationConfiguration(
            duration: sessionPracticeMinutes,
            backgroundSound: selectedBackgroundSound,
            cueSettings: cueSettings,
            title: nil,
            binauralBeat: selectedBinauralBeat
        )
    }
    
    private func saveConfiguration() {
        syncSessionFromCues()
        let setting = currentTimerSetting()
        SharedUserStorage.save(value: setting, forKey: .timerSettings)
        logger.eventMessage("TimerView: Saved timer configuration: \(setting)")
        
        // Update share link after saving configuration
        updateShareLink()
    }
    
    private func loadSavedConfiguration() {
        if let savedSetting = SharedUserStorage.retrieve(forKey: .timerSettings, as: MeditationConfiguration.self) {
            selectedBackgroundSound = savedSetting.backgroundSound
            cueSettings = savedSetting.cueSettings
            // Restore binaural beat if present in saved config; otherwise keep current
            if let beat = savedSetting.binauralBeat {
                selectedBinauralBeat = beat
            }
            logger.eventMessage("TimerView: Loaded saved timer configuration: \(savedSetting)")

            // Update share link after loading configuration
            updateShareLink()
        }
    }
    
    // MARK: - Share Link Generation and Message
    
    // Add a method to update the share link whenever timer settings change
    private func updateShareLink() {
        #if DEBUG
        print("AI_debug [TimerView] updateShareLink enter cueCount=\(cueSettings.count)")
        #endif
        syncSessionFromCues()
        shareLink = generateShareLink()
        if let link = shareLink {
            logger.eventMessage("Share link updated: \(link.absoluteString)")
        }
    }
    
    private func generateShareLink() -> URL? {
        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        let timerConfig = MeditationConfiguration.makeTimerSessionConfig(
            durationMinutes: sessionPracticeMinutes,
            backgroundSound: selectedBackgroundSound,
            binauralBeat: selectedBinauralBeat,
            cueSettings: cueSettings,
            title: nil,
            voiceId: voiceId,
            isDeepLinked: false,
            description: nil
        )
        return TimerOneLinkShareURLBuilder.makeTimerShareURL(
            timerConfig: timerConfig,
            campaign: "custom",
            afSub1: "Custom Meditation"
        )
    }
    
    private var shareMessage: String {
        "Try this custom \(sessionPracticeMinutes)m meditation I made for you."
    }

    // MARK: - Play Flow Helpers

    private func buildLocalTimerConfig() -> TimerSessionConfig {
        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        #if DEBUG
        print("[TimerCreationView] buildLocalTimerConfig offline voiceId=\(voiceId) cueCount=\(cueSettings.count)")
        #endif
        return MeditationConfiguration.makeTimerSessionConfig(
            durationMinutes: sessionPracticeMinutes,
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
        syncSessionFromCues()
        GeneralBackgroundMusicController.shared.fadeOutForPractice()
        if !ConnectivityHelper.isConnectedToInternet() {
            performPlayWithConfig(buildLocalTimerConfig())
        } else {
            Task {
                do {
                    let package = try await MeditationsService.shared.createMeditationManual(
                        duration: sessionPracticeMinutes,
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

/// Practice length driven by module durations on the create screen (read-only).
private struct SessionLengthReadout: View {
    let practiceMinutes: Int
    let stepCount: Int

    private var stepsLabel: String {
        switch stepCount {
        case 0:
            return "Add Steps"
        case 1:
            return "1 Step"
        default:
            return "\(stepCount) Steps"
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("\(practiceMinutes) min")
                .allenoireFont(size: 36)
                .foregroundColor(.white)
                .baselineOffset(-2)
                .monospacedDigit()
                .multilineTextAlignment(.center)

            Text(stepsLabel)
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.foregroundLightGray.opacity(0.92))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

/// Create screen preview: **dev server only** (synchronous) so `Config` / catalogs never use production for the first frame.
private struct TimerViewPreviewShell: View {
    init() {
        SharedUserStorage.save(value: true, forKey: .useDevServer)
    }

    var body: some View {
        TimerView()
            .environmentObject(NavigationCoordinator())
            .environment(\.toggleMenu, {})
    }
}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        TimerViewPreviewShell()
            .previewDisplayName("Create")
    }
}
