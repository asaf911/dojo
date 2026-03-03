import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            Image("ImagineIconNoBG")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 150)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .onAppear {
                    // Animate the logo fading in and scaling up
                    withAnimation(.easeOut(duration: 0.7)) {
                        logoScale = 1.1
                        logoOpacity = 1.0
                    }
                    // Slight bounce back
                    withAnimation(.easeInOut(duration: 0.3).delay(0.7)) {
                        logoScale = 1.0
                    }
                }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
    }
}


