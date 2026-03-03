//
//  HeaderControlsView.swift
//  imagine
//
//  Created by Asaf Shamir on 4/16/25.
//

import SwiftUI

// MARK: - Header Controls View

/// Right-side header controls with mute button and optional additional controls.
/// Used within UnifiedHeaderView as trailing content.
///
/// Layout: [Additional Controls] [Mute Button]
/// - Mute button is always present
/// - Additional controls appear to the left of mute
struct HeaderControlsView<AdditionalContent: View>: View {
    @ViewBuilder var additionalContent: () -> AdditionalContent
    
    var body: some View {
        HStack(spacing: 8) {
            additionalContent()
            
            MuteUnmuteButton()
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Convenience Initializer (No Additional Content)

extension HeaderControlsView where AdditionalContent == EmptyView {
    init() {
        self.additionalContent = { EmptyView() }
    }
}

// MARK: - Preview

#if DEBUG
struct HeaderControlsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Default (mute only)
            HeaderControlsView()
            
            // With additional button
            HeaderControlsView {
                Button(action: {}) {
                    Image(systemName: "plus.message")
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding()
        .background(Color.backgroundDarkPurple)
        .previewLayout(.sizeThatFits)
    }
}
#endif
