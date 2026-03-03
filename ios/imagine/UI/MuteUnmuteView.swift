//
//  MuteUnmuteView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-03-XX
//

import SwiftUI
import UIKit

struct MuteUnmuteButton: View {
    @ObservedObject var musicController = GeneralBackgroundMusicController.shared
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            musicController.toggleMute()
        }) {
            Image(systemName: musicController.isMuted ? "speaker.slash" : "speaker.2")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
        }
        .accessibilityLabel(musicController.isMuted ? "Play background music" : "Stop background music")
    }
}

struct MuteUnmuteView: View {
    var body: some View {
        MuteUnmuteButton()
            .padding(.top, 63)
            .padding(.trailing, 37)
            .ignoresSafeArea(edges: .top)
    }
}

struct MuteUnmuteView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MuteUnmuteView()
                .background(Color.backgroundDarkPurple)
                .previewLayout(.sizeThatFits)
            
            MuteUnmuteButton()
                .background(Color.backgroundDarkPurple)
                .previewLayout(.sizeThatFits)
        }
    }
}
