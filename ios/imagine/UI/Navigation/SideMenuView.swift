//
//  SideMenuView.swift
//  imagine
//
//  Created for Side Menu Navigation Migration
//

import SwiftUI

/// Menu section enumeration
enum MenuSection: String, CaseIterable, Identifiable {
    case training = "Training"
    case account = "Account"
    
    var id: String { rawValue }
    
    var items: [MenuItem] {
        switch self {
        case .training:
            return [.sensei, .path, .explore, .timer]
        case .account:
            return [.history, .insights, .settings]
        }
    }
}

/// Menu item enumeration for the side menu
enum MenuItem: Int, CaseIterable, Identifiable {
    case sensei = 0
    case explore = 1
    case path = 2
    case timer = 3
    case history = 4
    case insights = 5
    case settings = 6
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .sensei: return "Dojo"
        case .explore: return "Explore"
        case .path: return "The Path"
        case .timer: return "Create"
        case .history: return "History"
        case .insights: return "Progress"
        case .settings: return "Settings"
        }
    }
    
    var iconName: String {
        switch self {
        case .sensei: return "menuDojo"
        case .explore: return "menuExplore"
        case .path: return "menuPath"
        case .timer: return "menuCreate"
        case .history: return "menuHistory"
        case .insights: return "menuInsights"
        case .settings: return "menuSettings"
        }
    }
    
    var isSystemIcon: Bool {
        return false
    }
    
    
    /// Items to show in the menu
    static var visibleItems: [MenuItem] {
        [.sensei, .explore, .path, .timer, .history, .insights, .settings]
    }
}

struct SideMenuView: View {
    @Binding var isOpen: Bool
    @Binding var selectedItem: MenuItem
    var onDismissWithoutSelection: (() -> Void)? = nil
    
    // Menu width
    private let menuWidth: CGFloat = 313
    
    // Drag state for swipe to close
    @State private var dragOffset: CGFloat = 0
    private let closeThreshold: CGFloat = 80 // Minimum drag distance to close
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Tap area to dismiss (transparent)
            if isOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissWithoutSelection()
                    }
            }
            
            // Menu drawer
            HStack(spacing: 0) {
                VStack(alignment: .center, spacing: 0) {
                    // Menu items organized by sections
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(MenuSection.allCases) { section in
                                // Section title
                                sectionTitle(section.rawValue)
                                
                                // Section items
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(section.items) { item in
                                        SideMenuItemView(
                                            iconName: item.iconName,
                                            title: item.title,
                                            isSelected: selectedItem == item,
                                            isSystemIcon: item.isSystemIcon
                                        ) {
                                            selectItem(item)
                                        }
                                    }
                                }
                                
                                // Add divider after Training section
                                if section == .training {
                                    Rectangle()
                                        .fill(Color.menuDivider)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 1)
                                        .padding(.top, 32)
                                        .padding(.bottom, 16) // Account section title adds 16px more = 32px total
                                }
                                
                                // Add profile section after Account section (below Settings)
                                if section == .account {
                                    // Profile component
                                    SideMenuProfileView(onTap: {
                                        selectItem(.settings)
                                    })
                                    .padding(.horizontal, -24) // Offset parent padding - component has its own 24px
                                    .padding(.top, 24)
                                }
                            }
                        }
                        .padding(.horizontal, 24) // 24px unified horizontal padding
                        .padding(.top, 64) // 64px above first section title
                    }
                    
                    Spacer()
                    
                    // App version at bottom left
                    appVersionFooter
                }
                .frame(width: menuWidth, alignment: .top)
                .frame(maxHeight: .infinity)
                .background(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3).opacity(0.95), location: 0.00),
                            Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14).opacity(0.95), location: 0.66),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 1)
                    )
                )
                .ignoresSafeArea()
                .shadow(color: .black.opacity(0.1), radius: 7.5, x: 0, y: 10)
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 4)
                // Swipe left on menu to close
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // Only track leftward drags
                            if value.translation.width < 0 {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            // Close menu if swiped left enough
                            if value.translation.width < -closeThreshold {
                                dismissWithoutSelection()
                            }
                            dragOffset = 0
                        }
                )
                
                Spacer()
            }
            .offset(x: isOpen ? min(0, dragOffset) : -menuWidth)
        }
        .animation(.easeOut(duration: 0.25), value: isOpen)
    }
    
    // MARK: - App Version Footer
    
    private var appVersionFooter: some View {
        HStack {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .nunitoFont(size: 12, style: .regular)
                    .foregroundColor(.foregroundLightGray.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
    }
    
    // MARK: - Section Title
    
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Font.custom("Nunito", size: 12))
            .kerning(0.6)
            .foregroundColor(.foregroundLightGray.opacity(0.7))
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
    
    // MARK: - Helper Methods
    
    private func selectItem(_ item: MenuItem) {
        selectedItem = item
        withAnimation(.easeOut(duration: 0.25)) {
            isOpen = false
        }
    }
    
    private func dismissWithoutSelection() {
        withAnimation(.easeOut(duration: 0.25)) {
            isOpen = false
        }
        onDismissWithoutSelection?()
    }
}

#if DEBUG
#Preview("Side Menu") {
    SideMenuView(
        isOpen: .constant(true),
        selectedItem: .constant(.sensei)
    )
}
#endif

