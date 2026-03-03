//
//  SideMenuItemView.swift
//  imagine
//
//  Created for Side Menu Navigation Migration
//

import SwiftUI

struct SideMenuItemView: View {
    let iconName: String
    let title: String
    let isSelected: Bool
    let isSystemIcon: Bool
    let action: () -> Void
    
    init(
        iconName: String,
        title: String,
        isSelected: Bool = false,
        isSystemIcon: Bool = false,
        action: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.title = title
        self.isSelected = isSelected
        self.isSystemIcon = isSystemIcon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Icon - 28x28 to match PDF asset size (20px content + 4px padding each side)
                Group {
                    if isSystemIcon {
                        Image(systemName: iconName)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.foregroundLightGray)
                    } else {
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: 28, height: 28)
                
                // Title
                Text(title)
                    .font(Font.custom("Nunito", size: 16).weight(.medium))
                    .foregroundColor(.foregroundLightGray)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.selectedLightPurple.opacity(0.2)
                    : Color.clear
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 12
                )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.selectedLightPurple)
                        .frame(width: 1)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.backgroundDarkPurple.ignoresSafeArea()
        
        VStack(spacing: 8) {
            SideMenuItemView(
                iconName: "menuDojo",
                title: "Dojo",
                isSelected: true,
                action: {}
            )
            
            SideMenuItemView(
                iconName: "menuExplore",
                title: "Explore",
                isSelected: false,
                action: {}
            )
            
            SideMenuItemView(
                iconName: "menuHistory",
                title: "History",
                isSelected: false,
                action: {}
            )
        }
        .padding()
    }
}
#endif

