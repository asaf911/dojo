//
//  FractionalDurationStepper.swift
//  imagine
//

import SwiftUI

struct FractionalDurationStepper: View {
    @Binding var duration: Int
    var range: ClosedRange<Int> = 1...10

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if duration > range.lowerBound { duration -= 1 }
            } label: {
                Text("–")
                    .nunitoFont(size: 18, style: .medium)
                    .foregroundColor(duration > range.lowerBound ? .white : .white.opacity(0.25))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(duration <= range.lowerBound)

            Text("\(duration)m")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.white)
                .frame(minWidth: 34)
                .monospacedDigit()

            Button {
                if duration < range.upperBound { duration += 1 }
            } label: {
                Text("+")
                    .nunitoFont(size: 18, style: .medium)
                    .foregroundColor(duration < range.upperBound ? .white : .white.opacity(0.25))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(duration >= range.upperBound)
        }
        .background(Color.foregroundLightGray.opacity(0.12))
        .cornerRadius(20)
    }
}
