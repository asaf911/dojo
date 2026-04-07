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
                            
                            ForEach(config.cueSettings, id: \.id) { cueSetting in
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
        switch setting.triggerType {
        case .start:
            return "at start"
        case .end:
            return "at end"
        case .minute:
            if let minute = setting.minute {
                let totalSeconds = minute * 60
                return "at \(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
            }
            return ""
        case .second:
            if let sec = setting.minute {
                return "at \(sec / 60):\(String(format: "%02d", sec % 60))"
            }
            return ""
        }
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

