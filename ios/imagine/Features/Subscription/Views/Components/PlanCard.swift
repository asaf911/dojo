//
//  PlanCard.swift
//  imagine
//
//  Created by Cursor on 1/20/26.
//
//  Reusable subscription plan selection card component.
//  Displays plan details with glass-morphism styling and selection state.
//

import SwiftUI
import RevenueCat

struct PlanCard: View {
    let package: Package?
    let title: String
    let subtitle: String
    let priceText: String
    let secondaryPriceText: String?
    let isSelected: Bool
    let discountPercentage: Int?
    let action: () -> Void
    
    /// Standard initializer with RevenueCat package
    init(
        package: Package,
        title: String,
        subtitle: String,
        priceText: String,
        secondaryPriceText: String? = nil,
        isSelected: Bool,
        discountPercentage: Int?,
        action: @escaping () -> Void
    ) {
        self.package = package
        self.title = title
        self.subtitle = subtitle
        self.priceText = priceText
        self.secondaryPriceText = secondaryPriceText
        self.isSelected = isSelected
        self.discountPercentage = discountPercentage
        self.action = action
    }
    
    /// Preview initializer without RevenueCat dependency
    init(
        title: String,
        subtitle: String,
        priceText: String,
        secondaryPriceText: String? = nil,
        isSelected: Bool,
        discountPercentage: Int?,
        action: @escaping () -> Void
    ) {
        self.package = nil
        self.title = title
        self.subtitle = subtitle
        self.priceText = priceText
        self.secondaryPriceText = secondaryPriceText
        self.isSelected = isSelected
        self.discountPercentage = discountPercentage
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    // Plan Name - Text/Heading/Card title
                    Text(title)
                        .onboardingTypography(.cardTitle)
                        .foregroundColor(Color("ColorTextPrimary"))
                    // Description
                    Text(subtitle)
                        .font(Font.custom("Nunito-Medium", size: 14))
                        .foregroundColor(Color("ColorTextPrimary"))
                }
                Spacer()
                // Price
                VStack(alignment: .trailing, spacing: 4) {
                    Text(priceText)
                        .font(Font.custom("Nunito", size: 16))
                        .foregroundColor(Color("ColorTextPrimary"))
                    
                    if let secondaryPrice = secondaryPriceText {
                        Text(secondaryPrice)
                            .font(Font.custom("Nunito", size: 12))
                            .foregroundColor(Color("ColorTextSecondary"))
                    }
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    // Blur/Glass base using ultraThinMaterial
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                    
                    // Purple color tint gradient
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: Color(red: 0.18, green: 0.18, blue: 0.3), location: 0.00),
                                    Gradient.Stop(color: Color(red: 0.08, green: 0.08, blue: 0.14), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.55)
                    
                    // Glass shine/reflection at top
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: Color.white.opacity(0.12), location: 0.00),
                                    Gradient.Stop(color: Color.white.opacity(0.03), location: 0.40),
                                    Gradient.Stop(color: Color.clear, location: 0.60)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                // Inner border glow
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            stops: [
                                Gradient.Stop(color: Color.white.opacity(0.25), location: 0.00),
                                Gradient.Stop(color: Color.white.opacity(0.08), location: 0.50),
                                Gradient.Stop(color: Color.white.opacity(0.03), location: 1.00)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                // Selection border
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isSelected ?
                            AnyShapeStyle(LinearGradient(
                                gradient: Gradient(colors: [Color.last7DaysDarkPurple, Color.last7DaysLightPurple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Color.clear),
                        lineWidth: 2
                    )
            )
            // Discount tag overlay
            .overlay(
                Group {
                    if let discount = discountPercentage {
                        ZStack {
                            Image("planDiscount")
                                .resizable()
                                .frame(width: 75, height: 17)
                            Text("\(discount)% OFF")
                                .nunitoFont(size: 9, style: .extraBold)
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .offset(x: -7, y: -7)
                    }
                },
                alignment: .topLeading
            )
            // Checkmark overlay when selected
            .overlay(
                Group {
                    if isSelected {
                        Image("planCheckmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 23, height: 23)
                            .padding(8)
                            .offset(x: 12, y: -12)
                    }
                },
                alignment: .topTrailing
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#if DEBUG
struct PlanCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 14) {
                PlanCard(
                    title: "Annual",
                    subtitle: "7 day free trial",
                    priceText: "$39.99",
                    secondaryPriceText: "$3.33/mo",
                    isSelected: true,
                    discountPercentage: 67
                ) {
                    print("Annual tapped")
                }
                
                PlanCard(
                    title: "Monthly",
                    subtitle: "Billed monthly",
                    priceText: "$9.99/mo",
                    isSelected: false,
                    discountPercentage: nil
                ) {
                    print("Monthly tapped")
                }
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
