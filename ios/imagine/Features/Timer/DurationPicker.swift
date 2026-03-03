import SwiftUI

/// A simple SwiftUI wheel picker for selecting minutes from 1–60, with "min" positioned next to the selected option.
struct CountdownPicker: View {
    @Binding var minutes: Int

    var body: some View {
        ZStack {
            // Custom Wheel Picker
            CustomWheelPicker(minutes: $minutes)
                .frame(height: 180)
                .clipped()

            // Static "min" text positioned next to the center option
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Spacer() // Push "min" to align dynamically with the center row
                    Text("min")
                        .nunitoFont(size: 24, style: .regular) // Smaller font for "min"
                        .foregroundColor(.foregroundLightGray)
                        .padding(.leading, 5) // Add a consistent space between number and "min"
                }
                .frame(height: 40) // Match the height of the picker row
                .offset(x: calculatedMinOffset()) // Dynamically calculate position
                .allowsHitTesting(false) // Ensure the picker remains interactive
                Spacer()
            }
        }
    }

    /// Dynamically calculates the position of the "min" text based on its alignment with the picker center.
    private func calculatedMinOffset() -> CGFloat {
        return -110 // Replace this with any logic if you want it to adjust dynamically
    }
}

struct CountdownPicker_Previews: PreviewProvider {
    @State static var testMinutes = 5

    static var previews: some View {
        CountdownPicker(minutes: $testMinutes)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.black)
    }
}
