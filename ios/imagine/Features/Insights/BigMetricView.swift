//
//  BigMetricView.swift
//  Dojo
//
//  Created by Asaf Shamir on 12/13/24.
//

import SwiftUI

struct BigMetricView: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text(value)
                .allenoireFont(size: 52)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct BigMetricView_Previews: PreviewProvider {
    static var previews: some View {
        BigMetricView(title: "Overall Practice Time", value: "5h 30m")
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.backgroundDarkPurple)
    }
}
