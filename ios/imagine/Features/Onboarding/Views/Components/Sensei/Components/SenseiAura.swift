//
//  SenseiAura.swift
//  imagine
//
//  Glowing aura effect behind the Sensei character.
//  Uses layered gradients for a natural glow with visible rotation.
//
//  USAGE:
//  ------
//  Typically used internally by SenseiView, but can be used standalone:
//
//      @StateObject private var animator = SenseiAnimator()
//
//      SenseiAura(animator: animator, style: .listening)
//          .onAppear { animator.setAnimation(.listening) }
//
//  CUSTOMIZATION:
//  --------------
//  - style: Visual appearance (color, opacity)
//  - size: Aura dimensions
//
//  The component automatically applies these transforms from the animator:
//  - scale (pulsing effect)
//  - opacity (fade effects)
//  - isAuraPulsing (enable/disable pulse animation)
//  - isAuraRotating (enable/disable slow clockwise rotation)
//
//  GRADIENT STRUCTURE:
//  -------------------
//  The aura uses two layered gradients:
//  1. Base radial gradient: Creates the center-to-edge fade
//  2. Angular gradient overlay: Creates visible rotation with subtle
//     opacity variations around the circumference
//

import SwiftUI

// MARK: - SenseiAura

/// Glowing aura effect that appears behind the Sensei character.
///
/// The aura uses a radial gradient that stays solid in the center
/// and fades out naturally at the edges. It can pulse when the
/// animator's `isAuraPulsing` is true.
struct SenseiAura: View {
    
    // MARK: - Dependencies
    
    /// The animator controlling this aura's transforms
    @ObservedObject var animator: SenseiAnimator
    
    // MARK: - Configuration
    
    /// Visual style (determines color and base opacity)
    let style: SenseiStyle
    
    /// Aura dimensions
    let size: CGSize
    
    // MARK: - Animation State
    
    /// Internal pulsing animation state
    @State private var isPulsing: Bool = false
    
    /// Internal rotation angle (in degrees)
    @State private var rotationAngle: Double = 0
    
    // MARK: - Initialization
    
    /// Creates a Sensei aura view.
    ///
    /// - Parameters:
    ///   - animator: The animator controlling transforms
    ///   - style: Visual style (default: .listening)
    ///   - size: Aura size (default: 200x170)
    init(
        animator: SenseiAnimator,
        style: SenseiStyle = .listening,
        size: CGSize = CGSize(width: 200, height: 170)
    ) {
        self.animator = animator
        self.style = style
        self.size = size
    }
    
    // MARK: - Computed Properties
    
    /// Base radial gradient for center-to-edge fade.
    ///
    /// This creates the core glow that fades to transparent at edges.
    private var baseRadialGradient: RadialGradient {
        let baseColor = style.auraColor
        let opacity = style.auraOpacity
        
        return RadialGradient(
            gradient: Gradient(stops: [
                // Center: full opacity (solid core)
                .init(color: baseColor.opacity(opacity), location: 0.0),
                // Stay solid through 30%
                .init(color: baseColor.opacity(opacity * 0.95), location: 0.30),
                // Start gentle fade
                .init(color: baseColor.opacity(opacity * 0.7), location: 0.50),
                // Moderate fade
                .init(color: baseColor.opacity(opacity * 0.4), location: 0.70),
                // Aggressive fade at edges
                .init(color: baseColor.opacity(opacity * 0.15), location: 0.85),
                // Fully transparent at edge
                .init(color: baseColor.opacity(0), location: 1.0)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: max(size.width, size.height) / 2
        )
    }
    
    /// Angular gradient for visible rotation effect.
    ///
    /// Creates opacity variations around the circumference
    /// that become visible when the aura rotates.
    private var rotatingAngularGradient: AngularGradient {
        let baseColor = style.auraColor
        let opacity = style.auraOpacity
        
        // Balanced variations - visible but not distracting
        return AngularGradient(
            gradient: Gradient(colors: [
                baseColor.opacity(opacity * 1.0),
                baseColor.opacity(opacity * 0.45),
                baseColor.opacity(opacity * 0.85),
                baseColor.opacity(opacity * 0.35),
                baseColor.opacity(opacity * 0.88),
                baseColor.opacity(opacity * 0.4),
                baseColor.opacity(opacity * 1.0)  // Back to start for seamless loop
            ]),
            center: .center
        )
    }
    
    /// Combined scale from animator and pulse state
    private var effectiveScale: CGFloat {
        let animatorScale = animator.auraScale
        let pulseScale = isPulsing ? (1.0 + SenseiAnimationParameters.auraPulseScaleAmount) : 1.0
        return animatorScale * pulseScale
    }
    
    /// Combined opacity from animator and pulse state
    private var effectiveOpacity: Double {
        let animatorOpacity = animator.auraOpacity
        let pulseOpacity = isPulsing ? SenseiAnimationParameters.auraPulseMinOpacity : 1.0
        return animatorOpacity * pulseOpacity
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Layer 1: Base radial gradient (static, creates edge fade)
            Ellipse()
                .fill(baseRadialGradient)
                .frame(width: size.width, height: size.height)
            
            // Layer 2: Angular gradient (rotates, creates visible motion)
            Ellipse()
                .fill(rotatingAngularGradient)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(rotationAngle))
                .blendMode(.plusLighter)  // Additive blend for brighter highlights
                .opacity(0.72)
            
            // Layer 3: Radial mask to fade edges of angular gradient
            Ellipse()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .clear,
                            .black.opacity(0.4),
                            .black.opacity(0.85)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: max(size.width, size.height) / 2
                    )
                )
                .frame(width: size.width, height: size.height)
                .blendMode(.destinationOut)  // Cut out edges
        }
        .compositingGroup()  // Apply blend modes correctly
        .blur(radius: 15)  // Softens the gradient edges
        .scaleEffect(effectiveScale)
        .opacity(effectiveOpacity)
        .onChange(of: animator.isAuraPulsing) { _, shouldPulse in
            handlePulseChange(shouldPulse)
        }
        .onChange(of: animator.isAuraRotating) { _, shouldRotate in
            handleRotationChange(shouldRotate)
        }
        .onAppear {
            // Start rotation if animator says so
            if animator.isAuraRotating {
                startRotation()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Handle changes to the pulse state from animator
    private func handlePulseChange(_ shouldPulse: Bool) {
        if shouldPulse {
            // Start pulsing animation
            withAnimation(
                .easeInOut(duration: SenseiAnimationConfig.auraPulse.duration)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        } else {
            // Stop pulsing with smooth transition
            withAnimation(.easeOut(duration: 0.3)) {
                isPulsing = false
            }
        }
    }
    
    /// Handle changes to the rotation state from animator
    private func handleRotationChange(_ shouldRotate: Bool) {
        if shouldRotate {
            startRotation()
        } else {
            stopRotation()
        }
    }
    
    /// Start continuous clockwise rotation
    private func startRotation() {
        // Use linear animation for smooth continuous rotation
        withAnimation(
            .linear(duration: SenseiAnimationParameters.auraRotationDuration)
            .repeatForever(autoreverses: false)
        ) {
            rotationAngle = 360
        }
    }
    
    /// Stop rotation smoothly
    private func stopRotation() {
        // Stop at current angle with a gentle ease out
        withAnimation(.easeOut(duration: 0.5)) {
            // Keep current angle, just stop the animation
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SenseiAura_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            
            VStack(spacing: 60) {
                // Listening style
                SenseiAuraPreview(label: "Listening", style: .listening)
                
                // Thinking style
                SenseiAuraPreview(label: "Thinking", style: .thinking)
                
                // Ready style
                SenseiAuraPreview(label: "Ready", style: .ready)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Preview helper that creates its own animator
private struct SenseiAuraPreview: View {
    let label: String
    let style: SenseiStyle
    
    @StateObject private var animator = SenseiAnimator()
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            SenseiAura(animator: animator, style: style)
                .onAppear {
                    animator.setAnimation(.listening)
                }
        }
    }
}
#endif
