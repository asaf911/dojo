//
//  SettingsButtonView.swift
//  imagine
//
//  Created by Asaf Shamir on 4/12/25.
//

import SwiftUI

struct SettingsButtonView: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
        }
    }
}

#Preview {
    SettingsButtonView(action: {})
}

