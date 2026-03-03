//
//  DojoScreenContainer.swift
//  imagine
//
//  Created by Asaf Shamir on 4/11/25.
//

import SwiftUI

// MARK: - Dojo Screen Container

/// Universal container for all main menu views.
/// Provides consistent layout with background, header gradient, content area, and footer.
///
/// Z-Layer Structure:
/// - z0: Background (color + optional image) & Footer
/// - z1: Header gradient (non-interactive, for scroll effect)
/// - z2: Content
/// - z3: Header controls (interactive)
struct DojoScreenContainer<Content: View, HeaderTrailing: View>: View {
    let content: Content
    let headerTitle: String?
    let headerSubtitle: String?
    let backgroundImageName: String?
    let backAction: (() -> Void)?
    let showBackButton: Bool
    let backgroundDarkeningOpacity: Double?
    let menuAction: (() -> Void)?
    let showMenuButton: Bool
    let showFooter: Bool
    let headerTrailingContent: HeaderTrailing
    
    init(
        headerTitle: String? = nil,
        headerSubtitle: String? = nil,
        backgroundImageName: String? = nil,
        backAction: (() -> Void)? = nil,
        showBackButton: Bool = true,
        backgroundDarkeningOpacity: Double? = nil,
        menuAction: (() -> Void)? = nil,
        showMenuButton: Bool = false,
        showFooter: Bool = true,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.backgroundImageName = backgroundImageName
        self.backAction = backAction
        self.showBackButton = showBackButton
        self.backgroundDarkeningOpacity = backgroundDarkeningOpacity
        self.menuAction = menuAction
        self.showMenuButton = showMenuButton
        self.showFooter = showFooter
        self.headerTrailingContent = headerTrailing()
    }
    
    var body: some View {
        ZStack {
            // z0: Background - image or color fills entire screen
            backgroundLayer
            
            // z0: Footer overlay (optional)
            if showFooter {
                VStack {
                    Spacer()
                    FooterView()
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .zIndex(0)
            }
            
            // z1: Header gradient background (non-interactive) - below content for scroll effect
            VStack {
                headerGradient
                Spacer()
            }
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
            .zIndex(1)
            
            // z2: Main content with automatic top offset for header
            VStack(spacing: 0) {
                // Automatic spacer to push content below header
                Spacer().frame(height: HeaderLayout.contentTopOffset)
                
                // Content area - individual views should apply .topFadeMask(height: 20)
                // to their ScrollViews (not static elements like filters)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .zIndex(2)
            
            // z3: Interactive header controls - ABOVE content
            VStack {
                UnifiedHeaderView(
                    title: headerTitle ?? "",
                    subtitle: headerSubtitle,
                    showMenuButton: showMenuButton,
                    menuAction: menuAction,
                    backAction: backAction,
                    showBackButton: showBackButton
                ) {
                    headerTrailingContent
                }
                
                Spacer()
            }
            .ignoresSafeArea(.container, edges: .top)
            .zIndex(3)
        }
    }
    
    // MARK: - Background Layer
    
    private var backgroundLayer: some View {
        GeometryReader { geometry in
            Color.backgroundDarkPurple
                .overlay(
                    Group {
                        if let imageName = backgroundImageName {
                            ZStack {
                                Image(imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                                
                                if let opacity = backgroundDarkeningOpacity {
                                    Color.black.opacity(opacity)
                                }
                            }
                        }
                    }
                )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Upper Fade Gradient (Non-interactive)
    
    /// Consistent upper fade gradient used across all views
    /// Height: 222px, fades from solid purple to transparent
    private var headerGradient: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: UIScreen.main.bounds.width, height: 222)
            .background(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.18),
                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3).opacity(0.76), location: 0.56),
                        Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3).opacity(0), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
            )
    }
}

// MARK: - Convenience Initializer (Default Header Controls)

extension DojoScreenContainer where HeaderTrailing == HeaderControlsView<EmptyView> {
    init(
        headerTitle: String? = nil,
        headerSubtitle: String? = nil,
        backgroundImageName: String? = nil,
        backAction: (() -> Void)? = nil,
        showBackButton: Bool = true,
        backgroundDarkeningOpacity: Double? = nil,
        menuAction: (() -> Void)? = nil,
        showMenuButton: Bool = false,
        showFooter: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.backgroundImageName = backgroundImageName
        self.backAction = backAction
        self.showBackButton = showBackButton
        self.backgroundDarkeningOpacity = backgroundDarkeningOpacity
        self.menuAction = menuAction
        self.showMenuButton = showMenuButton
        self.showFooter = showFooter
        self.headerTrailingContent = HeaderControlsView()
    }
}

// MARK: - Preview

struct DojoScreenContainer_Previews: PreviewProvider {
    static var previews: some View {
        // Default header controls
        DojoScreenContainer(
            headerTitle: "Sample Title",
            headerSubtitle: "Sample Subtitle",
            backgroundImageName: "DojoBackground",
            backAction: {},
            showMenuButton: true
        ) {
            ScrollView {
                VStack {
                    Text("Sample Content")
                        .foregroundColor(.white)
                }
            }
        }
        .previewDisplayName("Default Controls")
        
        // Custom header controls
        DojoScreenContainer(
            headerTitle: "Sensei",
            backgroundImageName: "SenseiBackground",
            showMenuButton: true,
            showFooter: false,
            headerTrailing: {
                HeaderControlsView {
                    Button(action: {}) {
                        Image(systemName: "plus.message")
                            .foregroundColor(.white)
                    }
                }
            }
        ) {
            Text("Chat Content")
                .foregroundColor(.white)
        }
        .previewDisplayName("Custom Controls")
    }
}
