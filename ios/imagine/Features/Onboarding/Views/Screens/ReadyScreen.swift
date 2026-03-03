//
//  ReadyScreen.swift
//  imagine
//
//  Created by Cursor on 1/15/26.
//
//  Ready screen - "Your Path Is Ready"
//  Shows social proof and CTA to start trial.
//
//  NOTE: Content only - header, footer, and background are provided by container.
//

import SwiftUI

struct ReadyScreen: View {
    
    @ObservedObject var viewModel: OnboardingViewModel
    
    /// Randomly selected reviews (2 from the full list)
    @State private var selectedReviews: [ReadyReview] = []
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ═══════════════════════════════════════════════
            // FLEXIBLE SPACE (title is in unified header)
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(minHeight: 20, maxHeight: 40)
            
            // ═══════════════════════════════════════════════
            // SENSEI WITH AURA
            // ═══════════════════════════════════════════════
            SenseiView(style: .listening, topSpacing: 50)
            
            // ═══════════════════════════════════════════════
            // SPACING BEFORE CONTENT
            // ═══════════════════════════════════════════════
            Spacer()
                .frame(height: 4)
            
            // ═══════════════════════════════════════════════
            // BOTTOM CONTENT (above footer)
            // ═══════════════════════════════════════════════
            
            // SUBTITLE
            Text("Real practice. Real results.")
                .onboardingSubtitleStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 12px
            Spacer().frame(height: 12)
            
            // CUSTOMER REVIEWS (randomized)
            VStack(spacing: 12) {
                ForEach(selectedReviews) { review in
                    ReadyCustomerReview(
                        quote: review.quote,
                        author: review.author
                    )
                }
            }
            .onAppear {
                if selectedReviews.isEmpty {
                    selectedReviews = ReadyReview.randomSelection(count: 2)
                }
            }
            
            // 12px
            Spacer().frame(height: 12)
            
            // DIVIDER (ColorTextTertiary at 35% opacity)
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(height: 1)
            
            // 24px
            Spacer().frame(height: 24)
            
            // 5 STAR APP STORE RATING
            ReadyAppStoreRating()
            
            // Bottom spacer above footer
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Customer Review

private struct ReadyCustomerReview: View {
    let quote: String
    let author: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Quote (no quotation marks)
            Text(quote)
                .onboardingQuoteStyle()
                .multilineTextAlignment(.leading)
            
            // Author with stars (4px below quote)
            HStack(spacing: 24) {
                Text("- \(author)")
                    .onboardingQuoteStyle()
                
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image("socialStar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - App Store Rating

private struct ReadyAppStoreRating: View {
    private let laurelHeight: CGFloat = 75
    
    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            // Left laurel
            Image("laurelLeft")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: laurelHeight)
            
            // Rating content (centered between laurels)
            VStack(alignment: .center, spacing: 4) {
                Text("Rated 5 stars")
                    .nunitoFont(size: 16, style: .bold)
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 12))
                    }
                }
            }
            
            // Right laurel
            Image("laurelRight")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: laurelHeight)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Review Model

private struct ReadyReview: Identifiable {
    let id = UUID()
    let quote: String
    let author: String
    
    /// Full list of App Store reviews
    static let allReviews: [ReadyReview] = [
        ReadyReview(
            quote: "Finally a meditation app that does it right",
            author: "Matan G"
        ),
        ReadyReview(
            quote: "Been using it daily for the past two weeks and loving it!",
            author: "Dr Nir"
        ),
        ReadyReview(
            quote: "Finally something that helps me develop a good meditation habit!",
            author: "Bishotzil"
        ),
        ReadyReview(
            quote: "The only app that lets me build my own meditation and I can actually know how well I'm doing",
            author: "jvalansi"
        ),
        ReadyReview(
            quote: "I've tried many similar apps, finally found one that is simple and straightforward to use",
            author: "IlanBr"
        ),
        ReadyReview(
            quote: "Unlike other meditation apps, this one offers modules you can perfectly tailor to what you need",
            author: "basez99"
        ),
        ReadyReview(
            quote: "It has become an essential part of my daily routine, helping me cope with anxiety and sleep better",
            author: "Lena S"
        ),
        ReadyReview(
            quote: "The guided sessions are thoughtful and well-paced. Helped me stay more focused and grounded",
            author: "LameNok"
        ),
        ReadyReview(
            quote: "Simple, effective. The exercises are now a part of my daily life that I look forward to",
            author: "eilsel888"
        )
    ]
    
    /// Returns a random selection of reviews
    static func randomSelection(count: Int) -> [ReadyReview] {
        Array(allReviews.shuffled().prefix(count))
    }
}

// MARK: - Preview

#if DEBUG
struct ReadyScreen_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingPreviewContainer(step: .ready) {
            ReadyScreen(viewModel: OnboardingViewModel())
        }
    }
}
#endif
