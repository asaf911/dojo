//
//  ChoosePlanScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Choose Plan screen - "Choose Your Plan"
//  Shows all available subscription plans.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI
import RevenueCat

struct ChoosePlanScreen: View {
    
    @ObservedObject var viewModel: SubscriptionViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Autospace above plans
            Spacer()
            
            // Plan options (centered vertically, 14px between)
            VStack(spacing: 14) {
                // Annual
                if let annual = viewModel.annualPackage {
                    let discount: Int? = viewModel.monthlyPackage.flatMap {
                        PriceFormatting.discountPercentage(annualPackage: annual, monthlyPackage: $0)
                    }
                    
                    PlanCard(
                        package: annual,
                        title: "Annual",
                        subtitle: "7 day free trial",
                        priceText: annual.localizedPriceString,
                        secondaryPriceText: PriceFormatting.monthlyPrice(from: annual).map { "\($0)/mo" },
                        isSelected: viewModel.selectedPackage?.identifier == annual.identifier,
                        discountPercentage: discount
                    ) {
                        viewModel.selectedPackage = annual
                    }
                }
                
                // Monthly
                if let monthly = viewModel.monthlyPackage {
                    PlanCard(
                        package: monthly,
                        title: "Monthly",
                        subtitle: "Billed monthly",
                        priceText: monthly.localizedPriceString + "/mo",
                        isSelected: viewModel.selectedPackage?.identifier == monthly.identifier,
                        discountPercentage: nil
                    ) {
                        viewModel.selectedPackage = monthly
                    }
                }
            }
            .padding(.horizontal, 32)
            
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .nunitoFont(size: 12, style: .medium)
                    .foregroundColor(.red)
                    .padding(.top, 16)
                    .padding(.horizontal, 30)
            }
            
            // Autospace below plans
            Spacer()
            
            // 5 Star Rating component with laurels
            StarRatingBadge()
            
            // 24px
            Spacer().frame(height: 24)
            
            // Review quote - Text/Supporting/Quote/Medium, ColorTextTertiary
            Text("This finally made meditation stick for me")
                .font(Font.custom("Nunito-Italic", size: 16))
                .tracking(0.32)
                .foregroundColor(Color("ColorTextTertiary"))
                .multilineTextAlignment(.center)
            
            // 24px
            Spacer().frame(height: 24)
            
            // Cancel anytime - Text/Supporting/medium, ColorTextTertiary
            Text("Cancel anytime")
                .onboardingTypography(.supporting)
                .foregroundColor(Color("ColorTextTertiary"))
            
            // 14px to footer
            Spacer().frame(height: 14)
        }
    }
}

// MARK: - Preview

#if DEBUG
/// Interactive preview wrapper that manages state and footer
private struct ChoosePlanPreviewWrapper: View {
    
    @State private var selectedPlan: String = "annual"
    
    private var buttonText: String {
        selectedPlan == "annual" ? "Start Your 7-Day Trial" : "Subscribe Now"
    }
    
    private var footerConfig: OnboardingFlowFooterConfig {
        .init(
            primaryButton: .init(
                text: buttonText,
                isEnabled: true,
                action: {}
            ),
            secondaryAction: .init(
                text: "Restore purchases",
                action: {}
            )
        )
    }
    
    var body: some View {
        SubscriptionPreviewContainer(
            step: .choosePlan,
            footerConfig: footerConfig
        ) {
            screenContent
        }
    }
    
    private var screenContent: some View {
        VStack(spacing: 0) {
            // Autospace above plans
            Spacer()
            
            // Plan options (centered vertically, 14px between)
            VStack(spacing: 14) {
                // Annual
                PlanCard(
                    title: "Annual",
                    subtitle: "7 day free trial",
                    priceText: "$39.99",
                    secondaryPriceText: "$3.33/mo",
                    isSelected: selectedPlan == "annual",
                    discountPercentage: 67
                ) {
                    selectedPlan = "annual"
                }
                
                // Monthly
                PlanCard(
                    title: "Monthly",
                    subtitle: "Billed monthly",
                    priceText: "$9.99/mo",
                    isSelected: selectedPlan == "monthly",
                    discountPercentage: nil
                ) {
                    selectedPlan = "monthly"
                }
            }
            .padding(.horizontal, 32)
            
            // Autospace below plans
            Spacer()
            
            // 5 Star Rating component with laurels
            StarRatingBadge()
            
            // 24px
            Spacer().frame(height: 24)
            
            // Review quote - Text/Supporting/Quote/Medium, ColorTextTertiary
            Text("This finally made meditation stick for me")
                .font(Font.custom("Nunito-Italic", size: 16))
                .tracking(0.32)
                .foregroundColor(Color("ColorTextTertiary"))
                .multilineTextAlignment(.center)
            
            // 24px
            Spacer().frame(height: 24)
            
            // Cancel anytime - Text/Supporting/medium, ColorTextTertiary
            Text("Cancel anytime")
                .onboardingTypography(.supporting)
                .foregroundColor(Color("ColorTextTertiary"))
            
            // 14px to footer
            Spacer().frame(height: 14)
        }
    }
}

struct ChoosePlanScreen_Previews: PreviewProvider {
    static var previews: some View {
        ChoosePlanPreviewWrapper()
            .previewDisplayName("Choose Plan Screen")
    }
}
#endif
