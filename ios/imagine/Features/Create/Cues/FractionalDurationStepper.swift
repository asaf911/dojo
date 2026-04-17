//
//  FractionalDurationStepper.swift
//  imagine
//

import SwiftUI

struct FractionalDurationStepper: View {
    @Binding var duration: Int
    var range: ClosedRange<Int> = 1...10

    /// Layout spec: inner content 67×14, padding 13 H / 9 V → outer 93×32, corner radius 23.
    private enum Metrics {
        static let capsuleCornerRadius: CGFloat = 23
        static let innerWidth: CGFloat = 67
        static let innerHeight: CGFloat = 14
        static let horizontalPadding: CGFloat = 13
        static let verticalPadding: CGFloat = 9
        static let sideControlWidth: CGFloat = 22
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                stepperControls
                    .liquidGlass(cornerRadius: Metrics.capsuleCornerRadius, style: .secondary)
            } else {
                stepperControls
                    .background(Color.foregroundLightGray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.capsuleCornerRadius, style: .continuous))
            }
        }
    }

    private var stepperControls: some View {
        HStack(spacing: 0) {
            Button {
                if duration > range.lowerBound { duration -= 1 }
            } label: {
                Text("–")
                    .nunitoFont(size: 14, style: .medium)
                    .foregroundColor(duration > range.lowerBound ? .white : .white.opacity(0.25))
                    .frame(width: Metrics.sideControlWidth, height: Metrics.innerHeight)
            }
            .buttonStyle(.borderless)
            .disabled(duration <= range.lowerBound)

            Text("\(duration)m")
                .nunitoFont(size: 14, style: .bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .monospacedDigit()

            Button {
                if duration < range.upperBound { duration += 1 }
            } label: {
                Text("+")
                    .nunitoFont(size: 14, style: .medium)
                    .foregroundColor(duration < range.upperBound ? .white : .white.opacity(0.25))
                    .frame(width: Metrics.sideControlWidth, height: Metrics.innerHeight)
            }
            .buttonStyle(.borderless)
            .disabled(duration >= range.upperBound)
        }
        .frame(width: Metrics.innerWidth, height: Metrics.innerHeight, alignment: .center)
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
    }
}
