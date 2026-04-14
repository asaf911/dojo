//
//  PlayerView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-17
//
//  Unified player view supporting both guided (MP3) and timer meditation sessions.
//

import SwiftUI
import MediaPlayer
import Kingfisher
import UIKit

struct PlayerView: View {
    // MARK: - Session Type
    
    /// The type of session being played
    var sessionType: SessionType
    
    // MARK: - Guided Session Properties
    
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    var selectedFile: AudioFile?
    @Binding var durationIndex: Int
    
    // MARK: - Timer Session Properties
    
    /// Observed wrapper for timer session - allows view to re-render when session state changes
    @ObservedObject var timerSessionWrapper: TimerMeditationSessionWrapper
    
    /// Binding to track whether timer assets are being prepared/downloaded
    @Binding var isPreparingTimerAssets: Bool
    
    /// Convenience accessor for the actual session
    var timerSession: TimerMeditationSession? {
        timerSessionWrapper.session
    }
    
    // MARK: - State
    
    @State private var showShareSheet: Bool = false
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    // Watch pairing manager
    @ObservedObject private var watchPairingManager = WatchPairingManager.shared
    
    var onBackButtonPress: () -> Void
    
    // MARK: - Computed Properties
    
    /// Title to display - from AudioFile for guided, or config title for timer
    private var displayTitle: String {
        switch sessionType {
        case .guided:
            return selectedFile?.title ?? "Meditation"
        case .timer:
            return timerSession?.config.title ?? "Meditation Session"
        }
    }
    
    /// All sessions have a background image (practice image or fallback)
    private var showBackgroundImage: Bool {
        true
    }
    
    /// Whether controls are disabled (downloading for guided, or preparing assets for timer)
    private var controlsDisabled: Bool {
        (sessionType == .guided && audioPlayerManager.isDownloading) ||
        (sessionType == .timer && isPreparingTimerAssets)
    }
    
    /// Whether to show the share button (both guided and timer sessions)
    private var showShareButton: Bool {
        switch sessionType {
        case .guided:
            return selectedFile != nil
        case .timer:
            return timerSession != nil
        }
    }
    
    /// Whether to show description (guided sessions only)
    private var showDescription: Bool {
        sessionType == .guided && !(selectedFile?.description.isEmpty ?? true)
    }
    
    // MARK: - Share Functionality
    
    private func generateShareLink() -> URL? {
        let baseURL = Config.oneLinkBaseURL
        var components = URLComponents(string: baseURL)
        
        switch sessionType {
        case .guided:
            guard let file = selectedFile else { return nil }
            // Determine campaign based on whether it's a Path meditation
            let campaign = file.tags.contains("path") ? "path" : "explore"
            components?.queryItems = [
                URLQueryItem(name: "practiceId", value: file.id),
                URLQueryItem(name: "c", value: campaign),
                URLQueryItem(name: "af_sub1", value: file.title)
            ]
            
        case .timer:
            guard let config = timerSession?.config else { return nil }
            let subtitle = config.title ?? "Custom Meditation"
            return TimerOneLinkShareURLBuilder.makeTimerShareURL(
                timerConfig: config,
                campaign: "custom",
                afSub1: subtitle
            )
        }
        
        return components?.url
    }
    
    /// Short line only — the share sheet also passes `URL` separately so the full query string (e.g. `plan=`) is not lost to link detection inside one long string.
    private var shareCaptionText: String {
        switch sessionType {
        case .guided:
            return "Try this Dojo meditation I thought you'd like."
        case .timer:
            guard let config = timerSession?.config else {
                return "Try this custom meditation I made for you."
            }
            return "Try this custom \(config.minutes)m meditation I made for you."
        }
    }

    private var shareActivityItems: [Any] {
        let text = shareCaptionText
        if let url = generateShareLink() {
            return [text, url]
        }
        return [text]
    }
    
    // MARK: - Unified Player Container
    
    /// Unified container wrapping all player sections in a single card
    @ViewBuilder
    private func unifiedPlayerContainer(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .center, spacing: 24) {
            // 1. Controls - shared by both guided and timer sessions
            PlayerControlsView(
                audioPlayerManager: audioPlayerManager,
                selectedFile: selectedFile,
                sessionType: sessionType,
                timerSessionWrapper: timerSessionWrapper
            )
            .disabled(controlsDisabled)
            
            // 2. Live Heart Rate Status Card (when HR monitoring enabled)
            if SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false) {
                sectionDivider
                
                LiveHeartRateCard()
                    .disabled(controlsDisabled)
            }
            
            // 3. Session Description - guided sessions only
            if showDescription, selectedFile != nil {
                sectionDivider
                
                descriptionDisplay
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 4. Practice Overview - timer sessions only (collapsible)
            if sessionType == .timer, let timer = timerSession {
                sectionDivider
                
                PracticeOverviewSection(
                    session: timer,
                    onExpand: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("scrollAnchor", anchor: .bottom)
                        }
                    },
                    onCustomize: {
                        handleCustomize(config: timer.config)
                    }
                )
            }
            
            // 5. Volume Controls - timer sessions only (collapsible)
            if sessionType == .timer, let timer = timerSession {
                sectionDivider
                
                VolumeControlsView(session: timer) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo("scrollAnchor", anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .top)
        .surfaceBackground(cornerRadius: 18)
    }
    
    /// Divider between sections in the unified container
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(height: 1)
    }
    
    // Description text display - always shown in full
    @ViewBuilder
    private var descriptionDisplay: some View {
        if let file = selectedFile {
            Text(file.description)
                .font(Font.custom("Nunito", size: 16))
                .foregroundColor(.textGray)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Background image (practice image or fallback)
                practiceBackgroundImageView
                
                VStack(spacing: 0) {
                    // Custom header with HStack layout
                    headerView
                    
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                // Flexible spacer pushes container to bottom
                                Spacer(minLength: 0)
                                
                                // Unified container wrapping all player sections
                                unifiedPlayerContainer(scrollProxy: scrollProxy)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 24)
                                
                                // Invisible anchor for scroll-to-bottom on section expand
                                Color.clear
                                    .frame(height: 1)
                                    .id("scrollAnchor")
                            }
                            .frame(minHeight: geometry.size.height - 100) // Ensure VStack fills available space (minus header)
                        }
                        .mask(
                            // Apply a gradient mask to the entire ScrollView
                            VStack(spacing: 0) {
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .clear, location: 0.01),
                                        .init(color: .white.opacity(0.5), location: 0.02),
                                        .init(color: .white, location: 0.04),
                                        .init(color: .white, location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                Spacer(minLength: 0)
                            }
                        )
                        .disabled(controlsDisabled)
                    }
                }
                .padding(.bottom, 0)
                
                // Improved full-screen loading overlay (both guided and timer sessions)
                if (sessionType == .guided && audioPlayerManager.isDownloading) ||
                   (sessionType == .timer && isPreparingTimerAssets) {
                    loadingOverlay
                        .zIndex(1000)
                }
            }
        }
        .onAppear {
            handleOnAppear()
        }
        .onDisappear {
            handleOnDisappear()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: shareActivityItems)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(alignment: .top) {
            // Chevron (top leading)
            Button(action: { onBackButtonPress() }) {
                Image("chevronDownLarge")
                    .foregroundColor(.white)
            }
            .disabled(controlsDisabled)
            
            // Title (aligned to leading)
            Text(displayTitle)
                .allenoireFont(size: 36)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .baselineOffset(-2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Share button (guided sessions only)
            if showShareButton {
                Button(action: {
                    HapticManager.shared.impact(.light)
                    showShareSheet = true
                }) {
                    Image("iconShare")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.white)
                }
                .buttonStyle(RoundButtonStyle(isEnabled: !controlsDisabled))
                .disabled(controlsDisabled)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 29)
    }
    
    // MARK: - Lifecycle
    
    private func handleOnAppear() {
        HRDebugLogger.log(.ui, "PlayerView appeared - sessionType=\(sessionType)")
        
        // Unified HR lifecycle for both session types
        // Start HR tracking if feature enabled
        if SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false) {
            PracticeBPMTracker.shared.startNewSession()
        }
        
        // Start heart rate service with session ID
        let sessionId = UUID().uuidString
        HeartRateService.shared.start(sessionId: sessionId)
    }
    
    private func handleOnDisappear() {
        HRDebugLogger.log(.ui, "PlayerView disappeared - sessionType=\(sessionType)")
        
        // Stop heart rate service
        HeartRateService.shared.forceStop()
        if SharedUserStorage.retrieve(forKey: .hrMonitoringEnabled, as: Bool.self, defaultValue: false) {
            PracticeBPMTracker.shared.stopTracking()
        }
    }
    
    // MARK: - Loading Spinner Component
    
    private struct LoadingSpinner: View {
        @State private var isAnimating = false
        
        var body: some View {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                    .frame(width: 60, height: 60)
                
                // Animated inner ring
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [Color.accentColor, Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .onAppear {
                        withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
            }
        }
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        Color.black.opacity(0.5)
            .ignoresSafeArea(.all)
            .overlay(
                VStack(spacing: 20) {
                    // Animated loading indicator
                    LoadingSpinner()
                    
                    // Loading text
                    Text("Preparing Your Practice...")
                        .nunitoFont(size: 18, style: .bold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 40)
            )
            .onTapGesture {
                // Consume tap gestures to prevent pass-through to buttons
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in }
            )
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: audioPlayerManager.isDownloading)
    }
    
    // MARK: - Customize Action
    
    /// Dismiss the player and navigate to the Timer view with the current session config pre-filled for editing
    private func handleCustomize(config: TimerSessionConfig) {
        let editorCues = config.cueSettingsForTimerEditor()
        let configuration = MeditationConfiguration(
            duration: config.minutes,
            backgroundSound: config.backgroundSound,
            cueSettings: editorCues,
            title: config.title,
            binauralBeat: config.binauralBeat.id == "None" ? nil : config.binauralBeat
        )
        
        // End the current session before navigating
        timerSessionWrapper.session?.stop()
        navigationCoordinator.dismissPlayerSheet()
        
        // Small delay to let the player sheet dismiss before navigating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            navigationCoordinator.applyDeepLinkMeditationConfiguration(configuration)
        }
    }
    
    // MARK: - Background Image View
    
    private var practiceBackgroundImageView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Image fills entire background space while maintaining aspect ratio
                Group {
                    if sessionType == .timer {
                        // Timer sessions use PlayerBackground (includes custom meditations - AI or timer generated)
                        Image("PlayerBackground")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else if let file = selectedFile, let imageUrl = file.imageFile, !imageUrl.isEmpty {
                        KFImage(URL(string: imageUrl))
                            .placeholder {
                                Image("PlayerBackground")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        // Default background for guided sessions without their own image
                        Image("PlayerBackground")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
                .overlay(
                    // Top overlay rectangle with purple to clear gradient
                    VStack {
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: geometry.size.width, height: 222)
                            .background(
                                LinearGradient(
                                    stops: [
                                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.18),
                                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3).opacity(0.76), location: 0.56),
                                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3).opacity(0), location: 1.00),
                                    ],
                                    startPoint: UnitPoint(x: 0.5, y: 0),
                                    endPoint: UnitPoint(x: 0.5, y: 1)
                                )
                            )
                        Spacer()
                    }
                )
            }
        }
        .ignoresSafeArea(.all, edges: .top)
    }
}
