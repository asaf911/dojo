//
//  VolumeControlsView.swift
//  Dojo
//
//  Volume controls for timer meditation sessions.
//  Provides sliders for Instructions, Ambience, and Binaural Beats.
//

import SwiftUI

struct VolumeControlsView: View {
    @ObservedObject var session: TimerMeditationSession
    var onExpand: (() -> Void)? = nil
    @State private var isExpanded: Bool = false
    
    init(session: TimerMeditationSession, onExpand: (() -> Void)? = nil) {
        self.session = session
        self.onExpand = onExpand
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Title + Chevron
            HStack {
                Text("Volume Controls")
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
            
            // Volume sliders (only when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    // Instructions volume
                    VolumeSliderRow(
                        label: "Instructions",
                        value: Binding(
                            get: { Double(session.instructionsVolume) },
                            set: { session.setInstructionsVolume(Float($0)) }
                        ),
                        isEnabled: true
                    )
                    
                    // Ambience volume
                    VolumeSliderRow(
                        label: "Ambience",
                        value: Binding(
                            get: { Double(session.ambienceVolume) },
                            set: { session.setAmbienceVolume(Float($0)) }
                        ),
                        isEnabled: session.hasBackgroundSound
                    )
                    
                    // Binaural Beats volume
                    VolumeSliderRow(
                        label: "Binaural Beats",
                        value: Binding(
                            get: { Double(session.binauralVolume) },
                            set: { session.setBinauralVolume(Float($0)) }
                        ),
                        isEnabled: session.hasBinauralBeat
                    )
                }
                .padding(.top, 24)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Volume Slider Row

private struct VolumeSliderRow: View {
    let label: String
    @Binding var value: Double
    let isEnabled: Bool
    private let range: ClosedRange<Double> = 0...1
    
    // sliderGray color from assets: #E5E7EB
    private static let sliderGrayUIColor = UIColor(red: 229/255, green: 231/255, blue: 235/255, alpha: 1.0)
    
    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(Font.custom("Nunito", size: 16).weight(.semibold))
                .foregroundColor(.fontsGraySecondary)
                .lineLimit(1)
            
            Spacer()
            
            CustomSlider(
                value: $value,
                range: range,
                isEnabled: isEnabled,
                minimumTrackColor: Self.sliderGrayUIColor,
                maximumTrackColor: Self.sliderGrayUIColor.withAlphaComponent(0.1),
                thumbColor: Self.sliderGrayUIColor,
                thumbDiameter: 8,
                trackHeight: 4
            )
            .frame(width: 200, height: 8)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
    }
}

// MARK: - Preview

struct VolumeControlsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple
                .ignoresSafeArea()
            
            // Wrapper mimicking PlayerView container
            VStack {
                VolumeControlsView(
                    session: TimerMeditationSession(
                        config: TimerSessionConfig(
                            minutes: 10,
                            backgroundSound: BackgroundSound(id: "B4", name: "Ocean Waves", url: "test"),
                            binauralBeat: BinauralBeat(id: "BB1", name: "Alpha", url: "test", description: nil)
                        )
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
                .opacity(0.95)
            )
            .cornerRadius(18)
            .padding(.horizontal, 16)
        }
        .previewDisplayName("Volume Controls")
    }
}

