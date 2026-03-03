//
//  CardComponents.swift
//  imagine
//
//  Created for Clean Recommendation Card Architecture
//
//  Shared UI components used across primary and secondary cards.
//

import SwiftUI

// MARK: - Card Play Button

/// Play button with configurable style for recommendation cards
struct CardPlayButton: View {
    enum Style {
        case filled      // Solid background (primary cards)
        case outline     // Border only (secondary cards)
    }
    
    let style: Style
    let onPlay: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.medium)
            onPlay()
        }) {
            ZStack {
                Circle()
                    .fill(style == .filled ? Color.white : Color.clear)
                    .frame(width: 32, height: 32)
                
                if style == .outline {
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        .frame(width: 32, height: 32)
                }
                
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(style == .filled ? .buttonNavy : .white)
            }
            .shadow(color: .black.opacity(style == .filled ? 0.32 : 0), radius: 3, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Card Duration Badge

/// Duration display badge for recommendation cards
struct CardDurationBadge: View {
    enum Style {
        case capsule    // Background capsule (primary cards)
        case plain      // No background (secondary cards)
    }
    
    let minutes: Int
    let style: Style
    
    var body: some View {
        Text("\(minutes) min")
            .font(Font.custom("Nunito", size: 14).weight(.medium))
            .foregroundColor(style == .capsule ? Color("ColorTextSecondary") : .foregroundLightGray)
            .padding(.horizontal, style == .capsule ? 12 : 0)
            .padding(.vertical, style == .capsule ? 4 : 0)
            .background(
                Group {
                    if style == .capsule {
                        Capsule()
                            .fill(Color(red: 0.08, green: 0.08, blue: 0.14).opacity(0.75))
                    }
                }
            )
    }
}

// MARK: - Card More Button

/// "..." more options button for secondary cards
struct CardMoreButton: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            onTap()
        }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Previews

#if DEBUG
struct CardComponents_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundNavy.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Play buttons
                HStack(spacing: 20) {
                    CardPlayButton(style: .filled, onPlay: {})
                    CardPlayButton(style: .outline, onPlay: {})
                }
                
                // Duration badges
                HStack(spacing: 20) {
                    CardDurationBadge(minutes: 10, style: .capsule)
                    CardDurationBadge(minutes: 15, style: .plain)
                }
                
                // More button
                CardMoreButton(onTap: {})
            }
        }
    }
}
#endif
