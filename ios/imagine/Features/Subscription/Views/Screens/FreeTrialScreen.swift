//
//  FreeTrialScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Free Trial screen - "7-Day Free Trial"
//  Primary subscription screen with trial CTA.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI
import RevenueCat

struct FreeTrialScreen: View {
    
    @ObservedObject var viewModel: SubscriptionViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 14px below title
            Spacer().frame(height: 14)
            
            // Pricing subtitle
            if let package = viewModel.annualPackage {
                // Text/Body/Emphasis - ColorTextPrimary
                Text("Then \(package.localizedPriceString) per year")
                    .onboardingTypography(.bodyLarge)
                    .foregroundColor(Color("ColorTextPrimary"))
                    .multilineTextAlignment(.center)
                
                // 8px
                Spacer().frame(height: 8)
                
                // Text/Supporting/Medium - ColorTextTertiary
                if let monthlyPrice = PriceFormatting.monthlyPrice(from: package) {
                    Text("(\(monthlyPrice) per month)")
                        .onboardingTypography(.supporting)
                        .foregroundColor(Color("ColorTextTertiary"))
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            SenseiView(style: .ready)
            
            Spacer()
            
            // Bottom content
            VStack(spacing: 14) {
                // Text/Heading/Large - ColorTextSecondary
                Text("Train with clarity. Measure your growth")
                    .onboardingTypography(.subtitle)
                    .foregroundColor(Color("ColorTextSecondary"))
                    .multilineTextAlignment(.center)
                
                // Text/Body/Primary - ColorTextTertiary (custom line spacing)
                Text("Reminder 2 days before it ends. Cancel anytime.")
                    .font(Font.custom("Nunito-Medium", size: 16))
                    .tracking(0.32)
                    .lineSpacing(6)
                    .foregroundColor(Color("ColorTextTertiary"))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            
            // 24px spacing to footer
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Preview

#if DEBUG
/// Preview version of FreeTrialScreen that shows mock data
/// (Real version depends on RevenueCat packages which aren't available in previews)
private struct FreeTrialScreenPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            // 14px below title
            Spacer().frame(height: 14)
            
            // Text/Body/Emphasis - ColorTextPrimary
            Text("Then $39.99 per year")
                .onboardingTypography(.bodyLarge)
                .foregroundColor(Color("ColorTextPrimary"))
                .multilineTextAlignment(.center)
            
            // 8px
            Spacer().frame(height: 8)
            
            // Text/Supporting/Medium - ColorTextTertiary
            Text("($3.33 per month)")
                .onboardingTypography(.supporting)
                .foregroundColor(Color("ColorTextTertiary"))
                .multilineTextAlignment(.center)
            
            Spacer()
            
            SenseiView(style: .ready)
            
            Spacer()
            
            // Bottom content
            VStack(spacing: 14) {
                // Text/Heading/Large - ColorTextSecondary
                Text("Train with clarity\nMeasure your growth")
                    .onboardingTypography(.subtitle)
                    .foregroundColor(Color("ColorTextSecondary"))
                    .multilineTextAlignment(.center)
                
                // Text/Body/Primary - ColorTextTertiary (custom line spacing)
                Text("Reminder 2 days before it ends. Cancel anytime.")
                    .font(Font.custom("Nunito-Medium", size: 16))
                    .tracking(0.32)
                    .lineSpacing(6)
                    .foregroundColor(Color("ColorTextTertiary"))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            
            // 24px spacing to footer
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 32)
    }
}

struct FreeTrialScreen_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPreviewContainer(step: .freeTrial) {
            FreeTrialScreenPreview()
        }
        .previewDisplayName("Free Trial Screen")
    }
}
#endif
