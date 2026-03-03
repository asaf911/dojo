//
//  HistoryView.swift
//  Dojo
//
//  Created for History feature MVP
//  Updated to use SessionHistoryManager and HistoryCardModel
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject private var historyManager = SessionHistoryManager.shared
    
    var body: some View {
        let _ = print("📜 HISTORY_VIEW: Rendering with \(historyManager.sessions.count) sessions")
        VStack(alignment: .leading, spacing: 12) {
            if historyManager.sessions.isEmpty {
                emptyStateView
            } else {
                sessionListView
            }
        }
        .onAppear {
            print("📜 HISTORY_VIEW: onAppear - sessions count: \(historyManager.sessions.count)")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.4))
            
            Text("No sessions yet")
                .nunitoFont(size: 18, style: .semiBold)
                .foregroundColor(.white.opacity(0.6))
            
            Text("Your completed meditations will appear here")
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Session List
    
    private var sessionListView: some View {
        LazyVStack(spacing: 12) {
            ForEach(historyManager.getHistoryCards()) { card in
                HistoryCardView(card: card)
            }
        }
    }
}

// MARK: - History Card View

struct HistoryCardView: View {
    let card: HistoryCardModel
    @State private var isExpanded: Bool = false
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Title + Chevron (only show chevron if there's expandable content)
            HStack(alignment: .top) {
                Text(card.title)
                    .nunitoFont(size: 16, style: .extraBold)
                    .foregroundColor(titleColor)
                    .lineLimit(isExpanded ? nil : 1)
                
                Spacer()
                
                if hasExpandableContent {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textGray)
                }
            }
            .padding(.bottom, 6)
            
            // Description (if available)
            if let description = card.description, !description.isEmpty {
                Text(description)
                    .font(Font.custom("Nunito", size: 16))
                    .foregroundColor(.textGray)
                    .lineLimit(isExpanded ? nil : 2)
                    .padding(.bottom, 12)
            }
            
            // Date and Duration row
            HStack(alignment: .center) {
                // Date with @ symbol
                Text("@ \(card.formattedDate)")
                    .font(Font.custom("Nunito", size: 14).weight(.semibold))
                    .foregroundColor(.textGray)
                
                Spacer()
                
                // Duration pill
                Text(card.formattedDuration)
                    .font(Font.custom("Nunito", size: 14).weight(.medium))
                    .foregroundColor(.textGray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                
                // Three-dot menu button
                Menu {
                    Button(action: {
                        handleOpenInPlayer()
                    }) {
                        Label("Play", systemImage: "play.circle.fill")
                    }
                    
                    if card.sessionType == .custom || card.sessionType == .aiGenerated {
                        Button(action: {
                            handleOpenInTimer()
                        }) {
                            Label {
                                Text("Customize")
                            } icon: {
                                Image("customizeIcon")
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        handleDeleteSession()
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textGray)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .padding(.leading, 8)
            }
            
            // Heart Rate section (only if data available)
            if card.hasHeartRateData {
                if isExpanded {
                    // Show full HeartRateGraphCard when expanded
                    HeartRateGraphCard(
                        samples: card.samples,
                        startBPM: Double(card.startBPM ?? 0),
                        endBPM: Double(card.endBPM ?? 0)
                    )
                    .padding(.top, 14)
                } else {
                    // Show compact heart rate row when collapsed
                    heartRateSection
                        .padding(.top, 14)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceBackground(cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.lightStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasExpandableContent else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
    
    // MARK: - Title Color Based on Session Type
    
    private var titleColor: Color {
        switch card.sessionType {
        case .guided:
            return .selectedLightPurple
        case .custom, .aiGenerated:
            return .dojoTurquoise
        }
    }
    
    /// Whether the card has content that can be expanded
    /// - Heart rate data: shows full graph when expanded
    /// - Long description: shows full text when expanded (threshold ~100 chars for 2 lines)
    private var hasExpandableContent: Bool {
        if card.hasHeartRateData {
            return true
        }
        if let description = card.description, description.count > 100 {
            return true
        }
        return false
    }
    
    // MARK: - Action Handlers
    
    private func handleOpenInPlayer() {
        // Subscription gate (post-first-session, not subscribed)
        if SubscriptionManager.shared.shouldGatePlay {
            SubscriptionManager.shared.logGateState()
            #if DEBUG
            print("📊 [SUBSCRIPTION_GATE] Play blocked — source=HistoryView")
            #endif
            navigationCoordinator.subscriptionSource = .history
            navigationCoordinator.navigateTo(.subscription)
            return
        }
        // Dismiss ProfileSheetView first
        presentationMode.wrappedValue.dismiss()
        
        // Fade out background music
        GeneralBackgroundMusicController.shared.fadeOutForPractice()
        
        // For custom/AI-generated meditations, use the custom meditation player (MeditationPlayerView)
        if card.sessionType == .custom || card.sessionType == .aiGenerated {
            // Get full session to access customConfig
            guard let session = SessionHistoryManager.shared.getSession(by: card.id) else {
                logger.debugMessage("HistoryCardView: Cannot open custom meditation - session not found")
                return
            }
            
            let customConfig = session.customConfig
            let durationMinutes = max(1, card.durationSeconds / 60)
            let backgroundSound = MeditationConfiguration.backgroundSound(forID: customConfig?.backgroundSoundId ?? "None")
            
            let binauralBeat: BinauralBeat = {
                if let beatId = customConfig?.binauralBeatId,
                   let beat = BinauralBeatManager.shared.beats.first(where: { $0.id == beatId }) {
                    return beat
                }
                return BinauralBeat(id: "None", name: "None", url: "", description: nil)
            }()
            
            let cueSettings = reconstructCueSettings(from: customConfig)
            
            // Navigate to custom meditation player with title and description
            navigationCoordinator.navigateToTimerCountdown(
                totalMinutes: durationMinutes,
                backgroundSound: backgroundSound,
                cueSettings: cueSettings,
                binauralBeat: binauralBeat,
                isDeepLinked: false,
                title: session.title,
                description: session.description
            )
        } else {
            // For guided meditations, use the regular player
            guard let practiceId = card.practiceId else {
                logger.debugMessage("HistoryCardView: Cannot open in player - no practiceId")
                return
            }
            
            // Find AudioFile and navigate
            DeepLinkHandler.findAudioFile(by: practiceId) { audioFile in
                DispatchQueue.main.async {
                    if let audioFile = audioFile {
                        navigationCoordinator.navigateToPlayer(with: audioFile, isDownloading: true)
                    } else {
                        logger.debugMessage("HistoryCardView: AudioFile not found for practiceId: \(practiceId)")
                    }
                }
            }
        }
    }
    
    private func handleOpenInTimer() {
        guard card.sessionType == .custom || card.sessionType == .aiGenerated else { return }
        
        // Get full session to access customConfig
        guard let session = SessionHistoryManager.shared.getSession(by: card.id) else {
            logger.debugMessage("HistoryCardView: Cannot open in timer - session not found")
            return
        }
        
        let customConfig = session.customConfig
        
        // Dismiss ProfileSheetView first
        presentationMode.wrappedValue.dismiss()
        
        // Reconstruct timer settings for editing
        let durationMinutes = max(1, card.durationSeconds / 60)
        let backgroundSound = MeditationConfiguration.backgroundSound(forID: customConfig?.backgroundSoundId ?? "None")
        
        let binauralBeat: BinauralBeat? = {
            if let beatId = customConfig?.binauralBeatId,
               let beat = BinauralBeatManager.shared.beats.first(where: { $0.id == beatId }) {
                return beat
            }
            return nil
        }()
        
        let cueSettings = reconstructCueSettings(from: customConfig)
        
        // Create configuration for TimerView editing
        let configuration = MeditationConfiguration(
            duration: durationMinutes,
            backgroundSound: backgroundSound,
            cueSettings: cueSettings,
            title: card.title,
            binauralBeat: binauralBeat
        )
        
        // Navigate to TimerView for editing
        navigationCoordinator.applyDeepLinkMeditationConfiguration(configuration)
    }
    
    private func handleDeleteSession() {
        print("📜 HISTORY_DELETE: User requested delete for session \(card.id.uuidString.prefix(8))...")
        SessionHistoryManager.shared.deleteSession(id: card.id)
    }
    
    // MARK: - Helper Methods
    
    private func reconstructCueSettings(from customConfig: SessionCustomConfig?) -> [CueSetting] {
        guard let customConfig = customConfig else { return [] }
        
        return customConfig.cueIds.compactMap { cueId in
            guard let cue = CueManager.shared.cues.first(where: { $0.id == cueId }) else {
                return nil
            }
            // Default trigger to .start since trigger info is not stored in SessionCustomConfig
            return CueSetting(triggerType: .start, minute: nil, cue: cue)
        }
    }
    
    // MARK: - Heart Rate Section
    
    private var heartRateSection: some View {
        HStack(spacing: 0) {
            // Heart icon
            Image("heartIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundColor(.white)
            
            // "HEART RATE" label
            Text("HEART RATE")
                .font(Font.custom("Nunito", size: 12).weight(.semibold))
                .foregroundColor(.textGray)
                .padding(.leading, 6)
            
            Spacer()
            
            // START value
            if let startBPM = card.startBPM {
                HStack(spacing: 3) {
                    Text("START")
                        .font(Font.custom("Nunito", size: 11))
                        .foregroundColor(.textGray)
                    Text("\(startBPM) bpm")
                        .font(Font.custom("Nunito", size: 11))
                        .foregroundColor(.textGray)
                }
            }
            
            // Separator
            Text("  ")
            
            // END value
            if let endBPM = card.endBPM {
                HStack(spacing: 3) {
                    Text("END")
                        .font(Font.custom("Nunito", size: 11))
                        .foregroundColor(.textGray)
                    Text("\(endBPM) bpm")
                        .font(Font.custom("Nunito", size: 11))
                        .foregroundColor(.textGray)
                }
            }
        }
    }
}

// MARK: - Preview

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 12) {
                    // Sample guided session with heart rate and sample points
                    HistoryCardView(card: HistoryCardModel(
                        from: MeditationSession(
                            sessionType: .guided,
                            source: .dojo,
                            title: "Perfect breath",
                            description: "Learn how to develop breath awareness and calm your mind",
                            practiceId: "test_001",
                            plannedDurationSeconds: 300,
                            actualDurationSeconds: 300,
                            heartRate: SessionHeartRateData(
                                startBPM: 88,
                                endBPM: 71,
                                readingCount: 10,
                                samples: [
                                    HeartRateSamplePoint(minuteOffset: 0, bpm: 88),
                                    HeartRateSamplePoint(minuteOffset: 1, bpm: 85),
                                    HeartRateSamplePoint(minuteOffset: 2, bpm: 82),
                                    HeartRateSamplePoint(minuteOffset: 3, bpm: 78),
                                    HeartRateSamplePoint(minuteOffset: 4, bpm: 75),
                                    HeartRateSamplePoint(minuteOffset: 5, bpm: 71)
                                ]
                            )
                        )
                    ))
                    
                    // Sample custom session without heart rate
                    HistoryCardView(card: HistoryCardModel(
                        from: MeditationSession(
                            sessionType: .custom,
                            source: .timer,
                            title: "Custom Meditation",
                            plannedDurationSeconds: 600,
                            actualDurationSeconds: 600
                        )
                    ))
                    
                    // Sample AI-generated session with heart rate and sample points
                    HistoryCardView(card: HistoryCardModel(
                        from: MeditationSession(
                            sessionType: .aiGenerated,
                            source: .aiChat,
                            title: "Morning Calm",
                            description: "Start your day with peace and clarity through gentle breathing exercises",
                            plannedDurationSeconds: 420,
                            actualDurationSeconds: 420,
                            heartRate: SessionHeartRateData(
                                startBPM: 75,
                                endBPM: 62,
                                readingCount: 8,
                                samples: [
                                    HeartRateSamplePoint(minuteOffset: 0, bpm: 75),
                                    HeartRateSamplePoint(minuteOffset: 1, bpm: 73),
                                    HeartRateSamplePoint(minuteOffset: 2, bpm: 70),
                                    HeartRateSamplePoint(minuteOffset: 3, bpm: 68),
                                    HeartRateSamplePoint(minuteOffset: 4, bpm: 66),
                                    HeartRateSamplePoint(minuteOffset: 5, bpm: 64),
                                    HeartRateSamplePoint(minuteOffset: 6, bpm: 62)
                                ]
                            )
                        )
                    ))
                }
                .padding()
            }
        }
    }
}
