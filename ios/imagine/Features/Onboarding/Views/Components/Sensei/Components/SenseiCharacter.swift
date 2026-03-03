//
//  SenseiCharacter.swift
//  imagine
//
//  The Sensei character image layer with animation support.
//  This component renders the Sensei icon and applies transforms from the animator.
//
//  USAGE:
//  ------
//  Typically used internally by SenseiView, but can be used standalone:
//
//      @StateObject private var animator = SenseiAnimator()
//
//      SenseiCharacter(animator: animator)
//          .onAppear { animator.setAnimation(.listening) }
//
//  CUSTOMIZATION:
//  --------------
//  - size: Change character dimensions
//  - imageName: Use a different image asset
//
//  The component automatically applies these transforms from the animator:
//  - offset (floating animation)
//  - scale (breathing/emphasis)
//  - opacity (fade transitions)
//

import SwiftUI

// MARK: - SenseiCharacter

/// The Sensei character image with animated transforms.
///
/// This view renders the Sensei icon and observes the animator
/// to apply floating, scaling, and opacity effects.
struct SenseiCharacter: View {
    
    // MARK: - Dependencies
    
    /// The animator controlling this character's transforms
    @ObservedObject var animator: SenseiAnimator
    
    // MARK: - Configuration
    
    /// Size of the character image
    let size: CGSize
    
    /// Name of the image asset to use
    let imageName: String
    
    // MARK: - Initialization
    
    /// Creates a Sensei character view.
    ///
    /// - Parameters:
    ///   - animator: The animator controlling transforms
    ///   - size: Character size (default: 65x50)
    ///   - imageName: Image asset name (default: "glowingSensei")
    init(
        animator: SenseiAnimator,
        size: CGSize = CGSize(width: 65, height: 50),
        imageName: String = "glowingSensei"
    ) {
        self.animator = animator
        self.size = size
        self.imageName = imageName
    }
    
    // MARK: - Body
    
    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            // Apply animator transforms
            .scaleEffect(animator.characterScale)
            .opacity(animator.characterOpacity)
            .offset(animator.characterOffset)
    }
}

// MARK: - Preview

#if DEBUG
struct SenseiCharacter_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Default size
                SenseiCharacterPreview(label: "Default (65x50)")
                
                // Larger size
                SenseiCharacterPreview(
                    label: "Large (100x77)",
                    size: CGSize(width: 100, height: 77)
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Preview helper that creates its own animator
private struct SenseiCharacterPreview: View {
    let label: String
    var size: CGSize = CGSize(width: 65, height: 50)
    
    @StateObject private var animator = SenseiAnimator()
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            SenseiCharacter(animator: animator, size: size)
                .onAppear {
                    animator.setAnimation(.listening)
                }
        }
    }
}
#endif
