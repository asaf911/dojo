//
//  UnifiedHeaderView.swift
//  imagine
//
//  Created for Unified Header Architecture
//

import SwiftUI

// MARK: - Menu Toggle Environment Key

/// Environment key for menu toggle action
private struct MenuToggleKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var toggleMenu: () -> Void {
        get { self[MenuToggleKey.self] }
        set { self[MenuToggleKey.self] = newValue }
    }
}

// MARK: - Header Layout Constants

/// Shared constants for header layout across the app
enum HeaderLayout {
    /// Top padding from phone edge (ignoring safe area)
    static var topPadding: CGFloat {
        UIDevice.isRunningOnIPadHardware ? 44 : 66
    }
    
    /// Bottom padding below header content
    static let bottomPadding: CGFloat = 32
    
    /// Horizontal padding
    static let horizontalPadding: CGFloat = 16
    
    /// Total content top offset (topPadding + ~title height + bottomPadding)
    static var contentTopOffset: CGFloat {
        topPadding + 44 + bottomPadding // 66 + 44 + 32 = 142
    }
    
    /// Bottom padding for footer clearance when footer is visible
    static let footerClearance: CGFloat = 120
}

// MARK: - Unified Header View

/// Single source of truth header component used across all side-menu views.
/// Contains only interactive controls and text - gradient background is managed by DojoScreenContainer.
///
/// Layout:
/// ```
/// [Burger/Back] [Title]                    [Trailing Controls]
///               [Subtitle - optional]
/// ```
struct UnifiedHeaderView<TrailingContent: View>: View {
    let title: String
    var subtitle: String? = nil
    var showMenuButton: Bool = true
    var menuAction: (() -> Void)? = nil
    var backAction: (() -> Void)? = nil
    var showBackButton: Bool = false
    @ViewBuilder var trailingContent: () -> TrailingContent
    
    @Environment(\.toggleMenu) private var toggleMenu
    
    private var hasLeadingButton: Bool {
        showMenuButton || (showBackButton && backAction != nil)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row with controls
            HStack(alignment: .center, spacing: 8) {
                // Leading button (hamburger or back)
                leadingButton
                
                // Title text
                Text(title)
                    .allenoireFont(size: 36)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .baselineOffset(-2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Trailing controls
                trailingContent()
            }
            
            // Optional subtitle
            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .nunitoFont(size: 18, style: .medium)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .padding(.leading, hasLeadingButton ? 52 : 0) // 44 (button) + 8 (spacing)
            }
        }
        .padding(.top, HeaderLayout.topPadding)
        .padding(.horizontal, HeaderLayout.horizontalPadding)
        .padding(.bottom, HeaderLayout.bottomPadding)
    }
    
    @ViewBuilder
    private var leadingButton: some View {
        if showMenuButton {
            Button(action: {
                if let action = menuAction {
                    action()
                } else {
                    toggleMenu()
                }
            }) {
                Image("menuBurger")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        } else if showBackButton, let action = backAction {
            Button(action: action) {
                Image(systemName: "chevron.down")
                    .foregroundColor(.white)
                    .font(.system(size: 24, weight: .medium))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        } else {
            // Empty spacer to maintain layout
            Spacer().frame(width: 44, height: 44)
        }
    }
}

// MARK: - Convenience Initializer (No Trailing Content)

extension UnifiedHeaderView where TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showMenuButton: Bool = true,
        menuAction: (() -> Void)? = nil,
        backAction: (() -> Void)? = nil,
        showBackButton: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showMenuButton = showMenuButton
        self.menuAction = menuAction
        self.backAction = backAction
        self.showBackButton = showBackButton
        self.trailingContent = { EmptyView() }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With Menu Button") {
    ZStack {
        Color.backgroundDarkPurple.ignoresSafeArea()
        
        VStack {
            UnifiedHeaderView(
                title: "Sensei",
                subtitle: "Your AI meditation guide"
            ) {
                HeaderControlsView()
            }
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview("Title Only") {
    ZStack {
        Color.backgroundDarkPurple.ignoresSafeArea()
        
        VStack {
            UnifiedHeaderView(title: "Meditations")
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}
#endif
