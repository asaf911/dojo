//
//  GlassEffectModifier.swift
//  imagine
//
//  Created by Cursor on 1/16/26.
//
//  Reusable liquid glass effect modifier for iOS 26+.
//  Applies native glassEffect on iOS 26+, falls back to shadows on earlier versions.
//

import SwiftUI

// MARK: - Glass Effect Style

enum GlassEffectStyle {
    case primary    // For gradient buttons - uses regular glass
    case secondary  // For transparent buttons - uses clear glass
}

// MARK: - Glass Effect Modifier

struct GlassEffectModifier: ViewModifier {
    let cornerRadius: CGFloat
    var style: GlassEffectStyle = .secondary
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .primary:
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            case .secondary:
                content
                    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            // Fallback for iOS < 26
            content
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 0)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies liquid glass effect with iOS 26+ native support
    /// - Parameters:
    ///   - cornerRadius: Corner radius for the glass shape
    ///   - style: `.primary` for gradient buttons, `.secondary` for transparent buttons
    func liquidGlass(cornerRadius: CGFloat, style: GlassEffectStyle = .secondary) -> some View {
        modifier(GlassEffectModifier(cornerRadius: cornerRadius, style: style))
    }
}
