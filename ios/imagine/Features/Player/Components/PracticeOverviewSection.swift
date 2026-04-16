//
//  PracticeOverviewSection.swift
//  Dojo
//
//  Collapsable practice overview section for the unified player container.
//  Shows session configuration details like duration, soundscape, and binaural beats.
//

import SwiftUI

struct PracticeOverviewSection: View {
    let session: TimerMeditationSession
    var initiallyExpanded: Bool = false
    var onExpand: (() -> Void)? = nil
    var onCustomize: (() -> Void)? = nil
    @State private var isExpanded: Bool = false
    /// Default: module-level timeline only. Dev: triple-tap Instructions toggles to every playback clip (and back).
    @State private var showsModuleInstructionTimeline = true

    init(session: TimerMeditationSession, initiallyExpanded: Bool = false, onExpand: (() -> Void)? = nil, onCustomize: (() -> Void)? = nil) {
        self.session = session
        self.initiallyExpanded = initiallyExpanded
        self.onExpand = onExpand
        self.onCustomize = onCustomize
        self._isExpanded = State(initialValue: initiallyExpanded)
    }
    
    private var config: TimerSessionConfig {
        session.config
    }

    /// Chronological order on the playback timeline (expanded server cues + manual rows).
    private var orderedCueSettings: [CueSetting] {
        config.cueSettings.sorted { sessionSecondForSort($0) < sessionSecondForSort($1) }
    }

    /// Same ordering as `orderedCueSettings`, but optionally uses collapsed fractional modules (timer editor shape).
    private var orderedInstructionCueSettings: [CueSetting] {
        if showsModuleInstructionTimeline {
            return config.cueSettingsForTimerEditor()
                .sorted { sessionSecondForSort($0) < sessionSecondForSort($1) }
        }
        return orderedCueSettings
    }

    private func sessionSecondForSort(_ setting: CueSetting) -> Int {
        let intro = config.introPrefixSeconds
        switch setting.triggerType {
        case .start:
            return 0
        case .end:
            return intro + config.minutes * 60
        case .minute:
            let m = setting.minute ?? 0
            return intro + m * 60
        case .second:
            return setting.minute ?? 0
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Title + Chevron
            HStack {
                Text("Practice Overview")
                    .font(Font.custom("Nunito", size: 16).weight(.heavy))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(isExpanded ? "chevronDown" : "chevronRight")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let willExpand = !isExpanded
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if willExpand {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onExpand?()
                    }
                }
            }
            
            // Overview details (only when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Soundscape / Background Sound
                    if !config.backgroundSound.name.isEmpty && config.backgroundSound.name != "None" {
                        overviewRow(label: "Soundscape", value: config.backgroundSound.name)
                    }
                    
                    // Binaural Beats
                    if !config.binauralBeat.name.isEmpty && config.binauralBeat.name != "None" {
                        overviewRow(label: "Binaural Beats", value: config.binauralBeat.name)
                    }
                    
                    // Instructions / Cues
                    if !config.cueSettings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Instructions")
                                .nunitoFont(size: 14, style: .semiBold)
                                .foregroundColor(.white.opacity(0.7))

                            ForEach(orderedInstructionCueSettings, id: \.id) { cueSetting in
                                HStack {
                                    Text(cueSetting.cue.name)
                                        .nunitoFont(size: 14, style: .regular)
                                        .foregroundColor(.white.opacity(0.9))

                                    Spacer()

                                    Text(cueTimingText(for: cueSetting))
                                        .nunitoFont(size: 14, style: .regular)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 3) {
                            showsModuleInstructionTimeline.toggle()
                        }
                    }
                    
                    // Customize button
                    if let onCustomize {
                        Button(action: {
                            HapticManager.shared.impact(.medium)
                            onCustomize()
                        }) {
                            Image("customizeIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 24)
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Helper Views
    
    private func overviewRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .nunitoFont(size: 14, style: .semiBold)
                .foregroundColor(.white.opacity(0.9))
        }
    }
    
    private func cueTimingText(for setting: CueSetting) -> String {
        let intro = config.introPrefixSeconds
        let practiceSec = config.minutes * 60

        // Full-session focus modules (I AM / nostril / morning visualization) span the practice and begin at meditation 00:00,
        // even if the editor stored `1 min` (slot index). Matches intro-relative playback after cue shift.
        if isFullSessionFocusModule(setting) {
            return "at 00:00"
        }

        switch setting.triggerType {
        case .start:
            return "at \(meditationClockLabel(for: setting, sessionSecond: 0, intro: intro))"
        case .end:
            return "at \(formatTimelineMMSS(practiceSec))"
        case .minute:
            guard let minute = setting.minute else { return "" }
            let sessionSecond = intro + minute * 60
            return "at \(meditationClockLabel(for: setting, sessionSecond: sessionSecond, intro: intro))"
        case .second:
            guard let sec = setting.minute else { return "" }
            return "at \(meditationClockLabel(for: setting, sessionSecond: sec, intro: intro))"
        }
    }

    /// Intro clips (`INT_*`) use the same negative countdown as the player during the prelude.
    /// All other modules (Perfect Breath, body scan, mantra, …) use the meditation clock from `00:00` — never negative.
    private func meditationClockLabel(for setting: CueSetting, sessionSecond: Int, intro: Int) -> String {
        if intro <= 0 {
            return formatTimelineMMSS(sessionSecond)
        }
        if isIntroTimelineClip(setting) {
            return introCountdownClock(sessionSecond: sessionSecond, introPrefixSeconds: intro)
        }
        let practiceElapsed = max(0, sessionSecond - intro)
        return formatTimelineMMSS(practiceElapsed)
    }

    private func isIntroTimelineClip(_ setting: CueSetting) -> Bool {
        let id = setting.cue.id
        if id == "INT_FRAC" { return true }
        // Expanded intro fractional clips (server-expanded `INT_GRT_*`, etc.)
        if id.hasPrefix("INT_") { return true }
        return false
    }

    /// Intro-only: `-MM:SS` countdown until meditation `00:00`.
    private func introCountdownClock(sessionSecond: Int, introPrefixSeconds: Int) -> String {
        if sessionSecond < introPrefixSeconds {
            let remaining = introPrefixSeconds - sessionSecond
            return "-\(formatTimelineMMSS(remaining))"
        }
        if sessionSecond == introPrefixSeconds {
            return "00:00"
        }
        return formatTimelineMMSS(sessionSecond - introPrefixSeconds)
    }

    /// `IM_FRAC` / `NF_FRAC` / `MV_*_FRAC` / `EV_*_FRAC` with `fractionalDuration` equal to session length: module starts at practice clock 00:00.
    private func isFullSessionFocusModule(_ setting: CueSetting) -> Bool {
        guard let fd = setting.fractionalDuration, fd == config.minutes else { return false }
        switch setting.cue.id {
        case "IM_FRAC", "NF_FRAC", "MV_KM_FRAC", "MV_GR_FRAC", "EV_KM_FRAC", "EV_GR_FRAC":
            return true
        default:
            return false
        }
    }

    private func formatTimelineMMSS(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Preview

#if DEBUG
struct PracticeOverviewSection_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple
                .ignoresSafeArea()
            
            PracticeOverviewSection(
                session: TimerMeditationSession(
                    config: TimerSessionConfig(
                        minutes: 15,
                        backgroundSound: BackgroundSound(id: "B1", name: "Dharapani", url: "test"),
                        binauralBeat: BinauralBeat(id: "BB1", name: "10 Hz (Relaxation)", url: "test", description: nil),
                        cueSettings: [
                            CueSetting(triggerType: .start, cue: Cue(id: "C1", name: "General Introduction", url: "test")),
                            CueSetting(triggerType: .minute, minute: 1, cue: Cue(id: "C2", name: "Perfect Breath (1m)", url: "test")),
                            CueSetting(triggerType: .minute, minute: 2, cue: Cue(id: "C3", name: "Body Scan (7m)", url: "test")),
                            CueSetting(triggerType: .minute, minute: 9, cue: Cue(id: "C4", name: "Mantra", url: "test")),
                            CueSetting(triggerType: .minute, minute: 13, cue: Cue(id: "C5", name: "Vision Clarity", url: "test")),
                            CueSetting(triggerType: .end, cue: Cue(id: "C6", name: "Gentle Bell", url: "test"))
                        ]
                    )
                ),
                initiallyExpanded: true,
                onCustomize: {}
            )
            .padding()
        }
        .previewDisplayName("Practice Overview")
    }
}
#endif

