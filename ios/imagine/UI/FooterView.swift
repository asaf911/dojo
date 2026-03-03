//
//  FooterView.swift
//  IDojo
//
//  Created by Asaf Shamir on 2025-04-08
//

import SwiftUI

struct FooterView: View {
    var body: some View {
        // Empty footer - no bottom fade needed
        // DojoScreenContainer handles content spacing via HeaderLayout.footerClearance
        Color.clear
            .frame(height: 0)
            .allowsHitTesting(false)
    }
}

struct FooterView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack {
                Spacer()
                FooterView()
            }
        }
        .ignoresSafeArea()
    }
}

