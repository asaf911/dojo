import SwiftUI

// MARK: - Subtle three-dot thinking indicator (Cursor-style)

struct ThinkingIndicatorView: View {
    private let dotSize: CGFloat = 6
    private let spacing: CGFloat = 6
    private let baseScale: CGFloat = 0.8
    private let scaleAmplitude: CGFloat = 0.22
    private let baseOpacity: Double = 0.45
    private let opacityAmplitude: Double = 0.5
    private let speed: Double = 0.85   // smaller is slower
    private let phaseDelay: Double = 0.22

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate / speed
            HStack(spacing: spacing) {
                ForEach(0..<3) { index in
                    let phase = (t - Double(index) * phaseDelay) * 2 * .pi
                    let normalized = (sin(phase) + 1) / 2 // 0...1
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(baseScale + scaleAmplitude * normalized)
                        .opacity(baseOpacity + opacityAmplitude * normalized)
                }
            }
            .drawingGroup()
        }
        .accessibilityLabel("Thinking")
        .accessibilityAddTraits(.isStaticText)
    }
}


