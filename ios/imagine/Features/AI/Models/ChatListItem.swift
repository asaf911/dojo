import Foundation

// MARK: - Chat List Item

/// Represents a renderable item in the chat list - either a date divider or a message
enum ChatListItem: Identifiable {
    case dateDivider(date: Date, id: String)
    case message(ChatMessage)
    
    var id: String {
        switch self {
        case .dateDivider(_, let id):
            return id
        case .message(let msg):
            return msg.id.uuidString
        }
    }
}

// MARK: - Date Divider Helper

extension Array where Element == ChatMessage {
    /// Transforms messages into a list with date dividers inserted where day boundaries occur
    func withDateDividers() -> [ChatListItem] {
        guard !isEmpty else { return [] }
        
        var result: [ChatListItem] = []
        var lastMessageDay: Date?
        
        for message in self {
            let messageDay = Calendar.current.startOfDay(for: message.timestamp)
            
            // Insert divider if this is a new day
            // Skip "Today" divider for the very first message (redundant - user knows it's today)
            if lastMessageDay == nil || messageDay != lastMessageDay {
                let isFirstMessageToday = lastMessageDay == nil && Calendar.current.isDateInToday(messageDay)
                if !isFirstMessageToday {
                    let dividerId = "divider-\(Int(messageDay.timeIntervalSince1970))"
                    result.append(.dateDivider(date: messageDay, id: dividerId))
                }
                lastMessageDay = messageDay
            }
            
            result.append(.message(message))
        }
        
        return result
    }
}

// MARK: - Date Formatting

extension Date {
    /// Returns "Today", "Yesterday", or "Nov 6" format for chat dividers
    var chatDividerText: String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }
    }
}
