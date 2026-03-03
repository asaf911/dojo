//
//  MindfulMinutesScreen.swift
//  imagine
//
//  Created by Cursor on 2/5/26.
//
//  Mindful Minutes screen - Asks for Apple Health write permission to sync sessions.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//  HealthKit connection is handled by the container's footer.
//

import SwiftUI

// MARK: - Mindful Minutes Screen

struct MindfulMinutesScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    // MARK: - Content
    
    private let bodyText = "Track your Mindful Minutes. Build consistency."
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // 32px from title
            Spacer().frame(height: 32)
            
            // AppleHealth image (original 782x1580, crop 330x305 of whitespace)
            // Resulting visible size: 452x1275, scaled to fit width
            Image("AppleHealth")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width - 64, height: 350)
                .clipped()
            
            // 32px below image
            Spacer().frame(height: 32)
            
            // AppleHealthIcon (left-aligned with padding)
            Image("AppleHealthIcon")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
            
            // 16px below icon
            Spacer().frame(height: 16)
            
            // Body text (left-aligned)
            Text(bodyText)
                .onboardingBodyLargeStyle()
                .foregroundColor(Color("ColorTextPrimary"))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
            
            // Auto space to footer
            Spacer()
        }
    }
}

// MARK: - Previews

#if DEBUG
struct MindfulMinutesScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .healthMindfulMinutes) {
            MindfulMinutesScreen(viewModel: OnboardingViewModel())
        }
        .previewDisplayName("Mindful Minutes Screen")
    }
}
#endif
