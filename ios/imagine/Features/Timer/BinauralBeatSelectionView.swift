import SwiftUI

struct BinauralBeatSelectionView: View {
    @Binding var selectedBeat: BinauralBeat
    @ObservedObject var beatManager = BinauralBeatManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Binaural Beats")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.foregroundLightGray)
            
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    Button("None") {
                        selectedBeat = BinauralBeat(id: "None", name: "None", url: "", description: nil)
                    }
                    ForEach(beatManager.beats) { beat in
                        Button(beat.name) {
                            selectedBeat = beat
                        }
                    }
                } label: {
                    CueIndicatorView(
                        text: selectedBeat.name,
                        isSelected: false,
                        action: {},
                        customFontSize: 18,
                        source: "BinauralBeat"
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 10)
        .onAppear {
            if ConnectivityHelper.isConnectedToInternet() {
                beatManager.fetchBinauralBeats()
            }
        }
    }
}


