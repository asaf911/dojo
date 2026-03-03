//
//  SenseiView.swift
//  imagine
//
//  The main Sensei component - a reusable animated character with glowing aura.
//  Use this view in screens to display the Sensei.
//
//  BASIC USAGE:
//  ------------
//  Simple usage with default settings:
//
//      SenseiView(style: .listening)
//
//  With spacing:
//
//      SenseiView(style: .listening, topSpacing: 50)
//
//  CONVENIENCE FACTORY METHODS:
//  ----------------------------
//  Quick creation with preset configurations:
//
//      SenseiView.listening(topSpacing: 50)
//      SenseiView.thinking()
//      SenseiView.ready(topSpacing: 50)
//
//  ADVANCED USAGE (External Animator):
//  -----------------------------------
//  For parent-level animation control:
//
//      struct MyScreen: View {
//          @StateObject private var senseiAnimator = SenseiAnimator()
//
//          var body: some View {
//              VStack {
//                  SenseiView(style: .listening, animator: senseiAnimator)
//
//                  Button("Celebrate") {
//                      senseiAnimator.setAnimation(.ready)
//                  }
//              }
//          }
//      }
//
//  COMPONENT STRUCTURE:
//  --------------------
//  SenseiView composes:
//  - SenseiAura (back layer) - glowing gradient effect
//  - SenseiCharacter (front layer) - the sensei image
//  - SenseiAnimator - coordinates animations for both
//
//  CUSTOMIZATION:
//  --------------
//  - style: Visual appearance (listening, thinking, ready, custom)
//  - characterSize: Size of the sensei image
//  - auraSize: Size of the aura glow
//  - topSpacing/bottomSpacing: Vertical padding
//  - initialAnimation: Animation to play on appear
//

import SwiftUI

// MARK: - SenseiView

/// The main Sensei component with animated character and aura.
///
/// This is the primary API for displaying a Sensei in your views.
/// It manages its own animation state internally, or can accept
/// an external animator for parent-level control.
struct SenseiView: View {
    
    // MARK: - Configuration
    
    /// Visual style determining aura color and opacity
    let style: SenseiStyle
    
    /// Size of the character image
    var characterSize: CGSize
    
    /// Size of the aura glow
    var auraSize: CGSize
    
    /// Space above the Sensei component
    var topSpacing: CGFloat
    
    /// Space below the Sensei component
    var bottomSpacing: CGFloat
    
    /// Animation to play when view appears
    var initialAnimation: SenseiAnimationType
    
    // MARK: - External Animator (Optional)
    
    /// Optional external animator for parent control.
    /// If nil, an internal animator is created.
    private var externalAnimator: SenseiAnimator?
    
    // MARK: - Internal State
    
    /// Internal animator used when no external animator is provided
    @StateObject private var internalAnimator = SenseiAnimator()
    
    /// The active animator (external or internal)
    private var animator: SenseiAnimator {
        externalAnimator ?? internalAnimator
    }
    
    // MARK: - Initialization
    
    /// Creates a Sensei view with the specified configuration.
    ///
    /// - Parameters:
    ///   - style: Visual appearance style (default: .listening)
    ///   - characterSize: Size of the character image (default: 65x50)
    ///   - auraSize: Size of the aura glow (default: 200x170)
    ///   - topSpacing: Space above the component (default: 0)
    ///   - bottomSpacing: Space below the component (default: 0)
    ///   - initialAnimation: Animation to play on appear (default: .listening)
    ///   - animator: Optional external animator for parent control
    init(
        style: SenseiStyle = .listening,
        characterSize: CGSize = CGSize(width: 65, height: 50),
        auraSize: CGSize = CGSize(width: 200, height: 170),
        topSpacing: CGFloat = 0,
        bottomSpacing: CGFloat = 0,
        initialAnimation: SenseiAnimationType = .listening,
        animator: SenseiAnimator? = nil
    ) {
        self.style = style
        self.characterSize = characterSize
        self.auraSize = auraSize
        self.topSpacing = topSpacing
        self.bottomSpacing = bottomSpacing
        self.initialAnimation = initialAnimation
        self.externalAnimator = animator
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Top spacing
            if topSpacing > 0 {
                Spacer().frame(height: topSpacing)
            }
            
            // Sensei with aura
            ZStack {
                // Aura layer (back)
                SenseiAura(
                    animator: animator,
                    style: style,
                    size: auraSize
                )
                
                // Character layer (front)
                SenseiCharacter(
                    animator: animator,
                    size: characterSize
                )
            }
            .frame(width: auraSize.width, height: auraSize.height)
            
            // Bottom spacing
            if bottomSpacing > 0 {
                Spacer().frame(height: bottomSpacing)
            }
        }
        .onAppear {
            // Start the initial animation when view appears
            animator.setAnimation(initialAnimation)
        }
    }
}

// MARK: - Convenience Factory Methods

extension SenseiView {
    
    /// Creates a Sensei in listening state.
    ///
    /// Use for screens where the Sensei is receiving input
    /// or maintaining a calm, attentive presence.
    ///
    /// - Parameter topSpacing: Space above the component
    /// - Returns: Configured SenseiView
    static func listening(topSpacing: CGFloat = 0) -> SenseiView {
        SenseiView(
            style: .listening,
            topSpacing: topSpacing,
            initialAnimation: .listening
        )
    }
    
    /// Creates a Sensei in thinking state.
    ///
    /// Use for screens where processing is happening
    /// (e.g., building screen with loading indicators).
    ///
    /// - Returns: Configured SenseiView
    static func thinking() -> SenseiView {
        SenseiView(
            style: .thinking,
            initialAnimation: .thinking
        )
    }
    
    /// Creates a Sensei in ready state.
    ///
    /// Use for completion screens or calls-to-action
    /// where confidence and energy are appropriate.
    ///
    /// - Parameter topSpacing: Space above the component
    /// - Returns: Configured SenseiView
    static func ready(topSpacing: CGFloat = 0) -> SenseiView {
        SenseiView(
            style: .ready,
            topSpacing: topSpacing,
            initialAnimation: .ready
        )
    }
}

// MARK: - Preview

#if DEBUG
struct SenseiView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Listening style (default)
                VStack {
                    Text("Listening")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    SenseiView.listening()
                }
                
                // Thinking style
                VStack {
                    Text("Thinking")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    SenseiView.thinking()
                }
                
                // Ready style
                VStack {
                    Text("Ready")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    SenseiView.ready()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// External animator demo
struct SenseiView_AnimatorDemo_Previews: PreviewProvider {
    static var previews: some View {
        SenseiAnimatorDemoView()
            .preferredColorScheme(.dark)
    }
}

private struct SenseiAnimatorDemoView: View {
    @StateObject private var animator = SenseiAnimator()
    @State private var currentAnimation: SenseiAnimationType = .listening
    
    var body: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("External Animator Demo")
                    .font(.headline)
                    .foregroundColor(.white)
                
                SenseiView(style: .listening, animator: animator)
                
                Text("Current: \(currentAnimation.displayName)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                HStack(spacing: 12) {
                    ForEach(SenseiAnimationType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            currentAnimation = type
                            animator.setAnimation(type)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            currentAnimation == type
                                ? Color.white.opacity(0.2)
                                : Color.clear
                        )
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    }
                }
            }
        }
    }
}
#endif
