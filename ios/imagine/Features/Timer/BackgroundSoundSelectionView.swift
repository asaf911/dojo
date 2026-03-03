import SwiftUI

struct BackgroundSoundSelectionView: View {
    // Bind to the selected background sound.
    @Binding var selectedSound: BackgroundSound
    @ObservedObject var catalogsManager = CatalogsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Soundscape")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.foregroundLightGray)
            
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    // Provide a "None" option using a default BackgroundSound with an id.
                    Button("None") {
                        selectedSound = BackgroundSound(id: "None", name: "None", url: "")
                    }
                    // List the sounds from the remote JSON, excluding any off/none placeholders.
                    ForEach(catalogsManager.sounds.filter { sound in
                        let lower = sound.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        return lower != "no background music" && lower != "none" && sound.id != "None"
                    }) { sound in
                        Button(sound.name) {
                            selectedSound = sound
                        }
                    }
                } label: {
                                            CueIndicatorView(
                        text: selectedSound.name,
                        isSelected: false,
                        action: {},
                        customFontSize: 18,
                        source: "BackgroundSound"
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 10)
        .onAppear {
            if ConnectivityHelper.isConnectedToInternet() {
                catalogsManager.fetchCatalogs(triggerContext: "BackgroundSoundSelectionView|pull-to-refresh")
            }
        }
    }
}

struct BackgroundSoundSelectionView_Previews: PreviewProvider {
    @State static var selectedSound = BackgroundSound(id: "None", name: "None", url: "")
    
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            BackgroundSoundSelectionView(selectedSound: $selectedSound)
                .padding()
        }
    }
}
