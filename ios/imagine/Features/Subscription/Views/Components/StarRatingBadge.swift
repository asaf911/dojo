//
//  StarRatingBadge.swift
//  imagine
//
//  Created by Cursor on 1/20/26.
//
//  5-star rating badge component with laurel decorations.
//  Used to display app store rating on subscription screens.
//

import SwiftUI

struct StarRatingBadge: View {
    
    var title: String = "5 Star Rating"
    var starCount: Int = 5
    
    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            // Left laurel
            Image("laurelLeft")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 75)
            
            // Rating content
            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .nunitoFont(size: 16, style: .bold)
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    ForEach(0..<starCount, id: \.self) { _ in
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
                .frame(height: 75)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Preview

#if DEBUG
struct StarRatingBadge_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                StarRatingBadge()
                
                StarRatingBadge(title: "Top Rated", starCount: 5)
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
