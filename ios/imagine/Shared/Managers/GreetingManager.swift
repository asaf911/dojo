//
//  GreetingManager.swift
//  imagine
//
//  Created by Asaf Shamir on 4/17/25.
//

import Foundation

struct GreetingManager {
    
    // MARK: - Time of Day
    
    enum TimeOfDay {
        case morning, afternoon, evening, night
        
        static func fromCurrentHour() -> TimeOfDay {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
        
        func greetingPrefix() -> String {
            switch self {
            case .morning: return "Good morning"
            case .afternoon: return "Good afternoon"
            case .evening: return "Good evening"
            case .night: return "Good night"
            }
        }
        
        /// Returns the appropriate background image name for this time of day
        var dojoBackgroundImageName: String {
            switch self {
            case .morning: return "DojoBackgroundMorning"
            case .afternoon: return "DojoBackgroundDay"
            case .evening: return "DojoBackgroundEvening"
            case .night: return "DojoBackgroundNight"
            }
        }
    }
    
    // MARK: - Greeting Construction
    
    static func generateGreeting(userName: String, isFirstSessionToday: Bool) -> String {
        let timeOfDay = TimeOfDay.fromCurrentHour()
        let timeGreeting = timeOfDay.greetingPrefix()
        
        let nameGreeting = isFirstSessionToday ? "\(timeGreeting), \(userName)" : "\(timeGreeting), welcome back"
        let cue = pickAnchorPhrase()
        
        // Combine greeting and cue, but keep total length reasonable
        return "\(nameGreeting). \(cue)"
    }
    
    // MARK: - Cue Options
    
    private static func pickAnchorPhrase() -> String {
        let cues = [
            "Get comfortable",
            "Let's begin",
            "Ready to start?",
            "Begin when you're ready",
            "Take a deep breath"
        ]
        return cues.randomElement() ?? "Let's begin"
    }
    
    // MARK: - Word Limit Helper
    
    private static func trimToWordLimit(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        let trimmed = words.prefix(maxWords)
        return trimmed.joined(separator: " ")
    }
}
