//
//  CreateView.swift
//  Dojo
//
//  Create tab: custom session builder — duration, steps, soundscape, binaural, start practice.
//

import Foundation
import SwiftUI

/// `true` when this process is an Xcode SwiftUI preview (`XCODE_RUNNING_FOR_PREVIEWS`).
private enum XcodePreviewRuntime {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

struct CreateView: View {
    @State private var selectedBackgroundSound: BackgroundSound = BackgroundSound(id: "None", name: "None", url: "")
    @State private var cueSettings: [CueSetting] = []
    @State private var selectedBinauralBeat: BinauralBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
    @State private var isDeepLinked: Bool = false  // Only used to pass along the flag
    @State private var meditationTitle: String? = nil  // Title from AI or deep link

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.toggleMenu) private var toggleMenu
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @StateObject private var catalogsManager = CatalogsManager.shared

    /// Practice length derived from fractional module durations (and reconciled cue triggers).
    private var sessionPracticeMinutes: Int {
        cueSettings.computedPracticeMinutesForCreateScreen()
    }

    /// Editor card inset from screen edges (matches `AIChatContainerView.chatContainer` stacking).
    @ViewBuilder
    private var createEditorContainer: some View {
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
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 28)
        }
        // Lets nested `List` reorder previews extend past the scroll view during the initial lift.
        .scrollClipDisabled(true)
        .topFadeMask(height: 5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surfaceBackground(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.planBorder.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    var body: some View {
        DojoScreenContainer(
            headerTitle: "Create",
            backgroundImageName: "CreateBackground",
            backAction: {
                if isDeepLinked {
                    // Just do nothing for deep links as we're already in the MainContainerView
                } else {
                    presentationMode.wrappedValue.dismiss()
                }
            },
            showBackButton: false,
            menuAction: toggleMenu,
            showMenuButton: true,
            showFooter: false
        ) {
            VStack(spacing: 0) {
                createEditorContainer

                Spacer().frame(height: 16)

                OnboardingPrimaryButton(
                    text: NSLocalizedString("Timer_PlayButton", bundle: .main, comment: "Create screen primary action"),
                    style: .primary,
                    action: handlePlayButtonTap
                )
                .padding(.horizontal, 24)
            }
            .safeAreaPadding(.bottom, 16)
        }
        .onAppear {
            if XcodePreviewRuntime.isActive {
                SharedUserStorage.save(value: true, forKey: .useDevServer)
            }
            // Always fetch fresh catalogs when online; fetchCatalogs falls back to cache when offline
            catalogsManager.fetchCatalogs(triggerContext: "CreateView|onAppear preload") { success in
                if success {
                    logger.eventMessage("Catalogs loaded successfully")
                }
            }
            
            // Check for deep link settings immediately on appear
            if let timerSetting = navigationCoordinator.deepLinkedMeditationConfiguration {
                print("🎛️ CreateView onAppear: Found deep linked meditation configuration - duration: \(timerSetting.duration)")
                logger.eventMessage("CreateView onAppear: Found deep linked meditation configuration")
                processDeepLinkSettings(timerSetting)
            } else {
                print("🎛️ CreateView onAppear: No deep linked meditation configuration found")
                logger.eventMessage("CreateView onAppear: No deep linked meditation configuration found")
                // Previews: skip persisted timer rows (stale prod/local sessions) and always use dev catalogs.
                if !XcodePreviewRuntime.isActive {
                    loadSavedConfiguration()
                }
            }
            
            // Reconcile cue rows to derived session length and refresh share URL for logs.
            updateShareLink()
        }
        // Re-add the onReceive handler for deepLinkedMeditationConfiguration as a backup
        // in case the settings are set after the view appears
        .onReceive(navigationCoordinator.$deepLinkedMeditationConfiguration) { timerSetting in
            if let timerSetting = timerSetting {
                logger.eventMessage("CreateView onReceive: Received deep linked meditation configuration")
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

        .onChange(of: selectedBackgroundSound) { _, _ in
            updateShareLink()
        }
        .onChange(of: cueSettings) { _, newValue in
            #if DEBUG
            print("AI_debug [CreateView] onChange cueSettings count=\(newValue.count) cueIds=\(newValue.map(\.cue.id).joined(separator: ","))")
            #endif
            // Defer past the current view update so `CueConfigurationView` rows are not evaluated with a
            // stale `index` while `syncSessionFromCues()` mutates `cueSettings` (e.g. fractional stepper).
            Task { @MainActor in
                updateShareLink()
            }
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
        print("AI_debug [CreateView] syncSessionFromCues before=\(before) after=\(cueSettings.count)")
        #endif
    }
    
    // MARK: - Persistence Helpers
    
    private func processDeepLinkSettings(_ timerSetting: MeditationConfiguration) {
        print("🎛️ CreateView: Processing deep link settings - duration: \(timerSetting.duration), sound: \(timerSetting.backgroundSound.name), title: \(timerSetting.title ?? "nil")")
        DispatchQueue.main.async {
            selectedBackgroundSound = timerSetting.backgroundSound
            cueSettings = timerSetting.cueSettings
            meditationTitle = timerSetting.title
            if let beat = timerSetting.binauralBeat {
                selectedBinauralBeat = beat
                logger.eventMessage("CreateView: Applied deep link binaural beat: \(beat.name)")
            } else {
                let forced = navigationCoordinator.timerBinauralBeat
                if forced.id != "None" {
                    selectedBinauralBeat = forced
                    logger.eventMessage("CreateView: Applied forced navigation binaural beat: \(forced.name)")
                } else {
                    logger.eventMessage("CreateView: No binaural beat found in deep link; keeping current selection: \(selectedBinauralBeat.name)")
                }
            }
            navigationCoordinator.deepLinkedMeditationConfiguration = nil
            isDeepLinked = true
            print("🎛️ CreateView: Successfully applied deep linked timer settings")
            logger.eventMessage("CreateView: Applied deep linked timer setting - duration: \(timerSetting.duration), sound: \(timerSetting.backgroundSound.name), title: \(timerSetting.title ?? "nil")")

            // Update share link after applying deep link settings
            updateShareLink()
        }
    }
    
    private func currentSessionConfiguration() -> MeditationConfiguration {
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
        let setting = currentSessionConfiguration()
        SharedUserStorage.save(value: setting, forKey: .timerSettings)
        logger.eventMessage("CreateView: Saved timer configuration: \(setting)")
        
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
            logger.eventMessage("CreateView: Loaded saved timer configuration: \(savedSetting)")

            // Update share link after loading configuration
            updateShareLink()
        }
    }
    
    // MARK: - Session sync & share URL (for logs)

    /// Reconciles cue rows to the derived session length and regenerates the custom-meditation share URL for logging.
    private func updateShareLink() {
        #if DEBUG
        print("AI_debug [CreateView] updateShareLink enter cueCount=\(cueSettings.count)")
        #endif
        syncSessionFromCues()
        if let link = generateShareLink() {
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
    
    // MARK: - Play Flow Helpers

    private func buildLocalPlaySessionConfiguration() -> TimerSessionConfig {
        let voiceId = SharedUserStorage.retrieve(forKey: .narrationVoiceId, as: String.self, defaultValue: "Asaf")
        #if DEBUG
        print("[CreateView] buildLocalPlaySessionConfiguration offline voiceId=\(voiceId) cueCount=\(cueSettings.count)")
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

    // MARK: - Button Actions

    private func handlePlayButtonTap() {
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=CreateView")
            #endif
            navigationCoordinator.subscriptionSource = .createScreen
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        syncSessionFromCues()
        GeneralBackgroundMusicController.shared.fadeOutForPractice()
        if !ConnectivityHelper.isConnectedToInternet() {
            performPlayWithConfig(buildLocalPlaySessionConfiguration())
        } else {
            Task {
                do {
                    let package = try await MeditationsService.shared.createMeditationManual(
                        duration: sessionPracticeMinutes,
                        backgroundSoundId: selectedBackgroundSound.id,
                        binauralBeatId: selectedBinauralBeat.id == "None" ? nil : selectedBinauralBeat.id,
                        cueSettings: cueSettings,
                        triggerContext: "CreateView|Create tapped"
                    )
                    await MainActor.run {
                        performPlayWithConfig(package.toTimerSessionConfig(isDeepLinked: isDeepLinked))
                    }
                } catch {
                    print("[Server][Meditations] createMeditationManual: failure trigger=CreateView|Create tapped offline fallback - \(error.localizedDescription)")
                    await MainActor.run {
                        performPlayWithConfig(buildLocalPlaySessionConfiguration())
                    }
                }
            }
        }
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
private struct CreateViewPreviewShell: View {
    init() {
        SharedUserStorage.save(value: true, forKey: .useDevServer)
    }

    var body: some View {
        CreateView()
            .environmentObject(NavigationCoordinator())
            .environment(\.toggleMenu, {})
    }
}

struct CreateView_Previews: PreviewProvider {
    static var previews: some View {
        CreateViewPreviewShell()
            .previewDisplayName("Create")
    }
}
