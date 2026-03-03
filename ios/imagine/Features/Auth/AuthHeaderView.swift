//
//  AuthHeaderView.swift
//  imagine
//
//  Created by Asaf Shamir on 4/1/25.
//
import SwiftUI

struct AuthHeaderView: View {
    // The subtitle text that will differ between sign in and sign up.
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dojo")
                .allenoireFont(size: 36)
                .foregroundColor(.foregroundLightGray)
                .padding(.top, 0)
                .baselineOffset(-2)
            Text(subtitle)
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.textForegroundGray)
                .padding(.top, 0)
        }
    }
}

struct AuthHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AuthHeaderView(subtitle: "Welcome back, practitioner")
            AuthHeaderView(subtitle: "Create your account")
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}

