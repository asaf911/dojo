import SwiftUI

struct AuthDividerView: View {
    // The text to display in the center of the divider.
    let text: String

    var body: some View {
        HStack(alignment: .center) {
            // Left line: flexible width.
            line
                .layoutPriority(0)
            // Center text with horizontal padding.
            Text(text)
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.textForegroundGray)
                .padding(.horizontal, 8)
                .lineLimit(1)
                .layoutPriority(1)
            // Right line: flexible width.
            line
                .layoutPriority(0)
        }
    }

    // A computed property that returns a horizontal line that can shrink if needed.
    private var line: some View {
        Rectangle()
            .fill(Color.textForegroundGray)
            .frame(height: 1)
            .opacity(0.5)
            .frame(maxWidth: .infinity)
    }
}

struct AuthDividerView_Previews: PreviewProvider {
    static var previews: some View {
        AuthDividerView(text: "Or sign in with")
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.black)
    }
}
