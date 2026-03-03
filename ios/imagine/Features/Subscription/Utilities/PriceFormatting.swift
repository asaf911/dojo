//
//  PriceFormatting.swift
//  imagine
//
//  Created by Cursor on 1/20/26.
//
//  Shared utility for formatting subscription prices.
//

import Foundation
import RevenueCat

enum PriceFormatting {
    
    /// Calculates the monthly price from an annual package
    /// - Parameter package: The RevenueCat package to calculate monthly price from
    /// - Returns: Formatted monthly price string, or nil if formatting fails
    static func monthlyPrice(from package: Package) -> String? {
        let price = package.storeProduct.price as Decimal
        let monthlyPrice = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = package.storeProduct.priceFormatter?.locale
        return formatter.string(from: monthlyPrice as NSDecimalNumber)
    }
    
    /// Calculates the monthly price with a "/month" suffix
    /// - Parameter package: The RevenueCat package to calculate monthly price from
    /// - Returns: Formatted monthly price string with "/month" suffix
    static func monthlyPriceWithSuffix(from package: Package) -> String {
        if let monthlyPriceString = monthlyPrice(from: package) {
            return monthlyPriceString + "/month"
        }
        return package.localizedPriceString + "/month"
    }
    
    /// Calculates the discount percentage of an annual plan compared to paying monthly for a year
    /// - Parameters:
    ///   - annualPackage: The annual subscription package
    ///   - monthlyPackage: The monthly subscription package
    /// - Returns: Discount percentage as an integer (e.g., 67 for 67% off), or nil if calculation fails
    static func discountPercentage(annualPackage: Package, monthlyPackage: Package) -> Int? {
        let annualPrice = annualPackage.storeProduct.price as Decimal
        let monthlyPrice = monthlyPackage.storeProduct.price as Decimal
        let yearlyAtMonthlyRate = monthlyPrice * 12
        
        guard yearlyAtMonthlyRate > 0 else { return nil }
        
        let savings = yearlyAtMonthlyRate - annualPrice
        let discountDecimal = (savings / yearlyAtMonthlyRate) * 100
        
        return NSDecimalNumber(decimal: discountDecimal).intValue
    }
}
