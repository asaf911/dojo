//
//  PracticeBadges.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-23
//

import SwiftUI

public struct RecentlyPlayedBadge: View {
    public init() {}
    public var body: some View {
        Text("Recently Played")
            .font(Font.custom("Nunito", size: 12).weight(.bold))
            .kerning(0.07)
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(.black).opacity(0.15))
            .cornerRadius(5)
    }
}

/// DEPRECATED: Free badge muted. All users get one free meditation; subscription is prompted on 2nd session attempt.
/// Keeping for reference. Previously shown on gallery items when user could play without subscription.
public struct FreeBadge: View {
    public init() {}
    public var body: some View {
        Text("Free")
            .font(Font.custom("Nunito", size: 12).weight(.bold))
            .kerning(0.07)
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.black).opacity(0.15))
            .cornerRadius(8)
    }
}

public struct CompletedBadge: View {
    public init() {}
    public var body: some View {
        Text("Completed")
            .font(Font.custom("Nunito", size: 12).weight(.bold))
            .kerning(0.07)
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(.dojoTurquoise).opacity(0.70))
            .cornerRadius(5)
    }
}

struct PracticeBadges_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RecentlyPlayedBadge()
            CompletedBadge()
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .previewLayout(.sizeThatFits)
    }
}
