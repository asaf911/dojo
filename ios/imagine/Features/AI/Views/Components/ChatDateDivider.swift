import SwiftUI

// MARK: - Chat Date Divider

/// Visual divider showing the date between messages from different days
/// Displays "Today", "Yesterday", or "Nov 6" format
struct ChatDateDivider: View {
    let date: Date
    
    var body: some View {
        HStack(spacing: 24) {
            dividerLine
            
            Text(date.chatDividerText)
                .font(Font.custom("Nunito", size: 11))
                .foregroundColor(.chatDivider)
            
            dividerLine
        }
        .padding(.vertical, 24)
    }
    
    private var dividerLine: some View {
        Rectangle()
            .fill(Color.chatDivider)
            .frame(height: 0.5)
    }
}
