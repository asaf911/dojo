import SwiftUI

// MARK: - Specular Border Modifier
// Reusable specular highlight border style for liquid glass containers
// Uses geometry-based radial gradients to ensure corners fade consistently regardless of frame size

struct SpecularBorderModifier: ViewModifier {
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                let size = geometry.size
                let fadeRadius = cornerRadius * 1.25
                
                ZStack {
                    // Base specular border - visible everywhere
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    
                    // Erase top-right corner with radial gradient
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    Gradient.Stop(color: Color.white, location: 0.0),
                                    Gradient.Stop(color: Color.white, location: 0.5),
                                    Gradient.Stop(color: Color.clear, location: 1.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: fadeRadius
                            )
                        )
                        .frame(width: fadeRadius * 2, height: fadeRadius * 2)
                        .position(x: size.width, y: 0)
                        .blendMode(.destinationOut)
                    
                    // Erase bottom-left corner with radial gradient
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    Gradient.Stop(color: Color.white, location: 0.0),
                                    Gradient.Stop(color: Color.white, location: 0.5),
                                    Gradient.Stop(color: Color.clear, location: 1.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: fadeRadius
                            )
                        )
                        .frame(width: fadeRadius * 2, height: fadeRadius * 2)
                        .position(x: 0, y: size.height)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func specularBorder(cornerRadius: CGFloat) -> some View {
        modifier(SpecularBorderModifier(cornerRadius: cornerRadius))
    }
}

