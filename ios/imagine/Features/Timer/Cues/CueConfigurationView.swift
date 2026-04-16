//
//  CueConfigurationView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import SwiftUI

/// Steps: modules play in list order (durations stack on the practice timeline). Bells/other cues still pick Start / minute / End.
struct CueConfigurationView: View {
    /// Practice length from the create screen (derived from module durations).
    let practiceMinutes: Int
    @Binding var cueSettings: [CueSetting]
    
    private let maxCues = 10
    @ObservedObject var catalogsManager = CatalogsManager.shared
    
    // Helper function to display the current trigger as text.
    private func displayText(for setting: CueSetting) -> String {
        switch setting.triggerType {
        case .start:
            return "Start"
        case .end:
            return "End"
        case .minute:
            if let min = setting.minute {
                return "\(min) min"
            } else {
                return "Select minute"
            }
        case .second:
            if let sec = setting.minute {
                return "\(sec)s"
            } else {
                return "Select second"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Steps")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.foregroundLightGray)
            
            ForEach(cueSettings.indices, id: \.self) { index in
                HStack(alignment: .center, spacing: 6) {
                    cueNameMenu(index: index)

                    if cueSettings[index].isCreateSequentialModule || cueSettings[index].cue.id == "INT_FRAC" {
                        fractionalOrAutoRow(index: index)
                    } else {
                        standardTriggerRow(index: index)
                    }

                    Spacer(minLength: 0)

                    Button(action: {
                        removeCue(at: index)
                    }) {
                        Text("x")
                            .nunitoFont(size: 18, style: .medium)
                            .foregroundColor(.white)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 8)
            }
            
            if cueSettings.count < maxCues {
                Button(action: addCue) {
                    Text("+ Add Step")
                        .nunitoFont(size: 18, style: .medium)
                        .kerning(0.07)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.foregroundLightGray)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 13)
                        .frame(minWidth: 63)
                        .background(Color.foregroundLightGray.opacity(0.1))
                        .cornerRadius(23)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .onAppear {
            if ConnectivityHelper.isConnectedToInternet() {
                catalogsManager.fetchCatalogs(triggerContext: "CueConfigurationView|pull-to-refresh")
            }
        }
    }

    /// Default minutes when picking a fractional module: match the nearest **earlier** timed module, or **5** if none.
    private func referenceFractionalMinutesForNewModule(beforeIndex index: Int) -> Int {
        var i = index - 1
        while i >= 0 {
            let cs = cueSettings[i]
            if cs.isCreateSequentialModule {
                let d = [CueSetting].createSequentialModuleDurationMinutes(cs)
                return Swift.max(1, Swift.min([CueSetting].createFlowMaxPracticeMinutes, d))
            }
            i -= 1
        }
        return 5
    }
    
    // MARK: - Row Builders

    @ViewBuilder
    private func cueNameMenu(index: Int) -> some View {
        Menu {
            ForEach(catalogsManager.cues) { cue in
                Button(cue.name) {
                    cueSettings[index].cue = cue
                    if cue.isMonolithicBodyScanCatalogCue {
                        let fromCatalog = CatalogsManager.shared.bodyScanDurations[cue.id]
                        let parsed = Int(cue.id.dropFirst(2)).flatMap { $0 > 0 ? $0 : nil }
                        let base = fromCatalog ?? parsed ?? 5
                        let sumOthers = cueSettings.sumFractionalPracticeMinutes(excludingIndex: index)
                        let cap = Swift.max(1, [CueSetting].createFlowMaxPracticeMinutes - sumOthers)
                        cueSettings[index].fractionalDuration = Swift.min(base, cap)
                    } else if CueSetting(cue: cue).isFractional {
                        if cue.id == "INT_FRAC" {
                            cueSettings[index].fractionalDuration = nil
                            cueSettings[index].triggerType = .start
                            cueSettings[index].minute = nil
                        } else {
                            let sumOthers = cueSettings.sumFractionalPracticeMinutes(excludingIndex: index)
                            let cap = Swift.max(1, [CueSetting].createFlowMaxPracticeMinutes - sumOthers)
                            let reference = referenceFractionalMinutesForNewModule(beforeIndex: index)
                            cueSettings[index].fractionalDuration = Swift.min(Swift.max(1, reference), cap)
                        }
                    } else {
                        cueSettings[index].fractionalDuration = nil
                    }
                }
            }
        } label: {
            CueIndicatorView(
                text: cueSettings[index].cue.name,
                isSelected: false,
                action: nil,
                customFontSize: 16,
                source: "Cues-Sound",
                isMenuButton: true
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        }
    }

    @ViewBuilder
    private func fractionalOrAutoRow(index: Int) -> some View {
        if cueSettings[index].cue.id == "INT_FRAC" {
            Text("Intro")
                .nunitoFont(size: 16, style: .medium)
                .foregroundColor(.foregroundLightGray.opacity(0.9))
        } else if cueSettings[index].cue.isMonolithicBodyScanCatalogCue {
            let d = [CueSetting].createSequentialModuleDurationMinutes(cueSettings[index])
            Text("\(d) min")
                .nunitoFont(size: 16, style: .bold)
                .foregroundColor(.foregroundLightGray)
                .monospacedDigit()
        } else if cueSettings[index].allowsManualFractionalDuration {
            let sumOthers = cueSettings.sumFractionalPracticeMinutes(excludingIndex: index)
            let maxForThis = max(1, min([CueSetting].createFlowMaxPracticeMinutes, [CueSetting].createFlowMaxPracticeMinutes - sumOthers))
            FractionalDurationStepper(
                duration: Binding(
                    get: {
                        let cap = maxForThis
                        return min(cueSettings[index].fractionalDuration ?? cap, cap)
                    },
                    set: { cueSettings[index].fractionalDuration = min($0, maxForThis) }
                ),
                range: 1...maxForThis
            )
        } else {
            Text("length from session")
                .nunitoFont(size: 14, style: .regular)
                .foregroundColor(.foregroundLightGray.opacity(0.9))
        }
    }

    @ViewBuilder
    private func standardTriggerRow(index: Int) -> some View {
        triggerMenu(index: index)
    }

    @ViewBuilder
    private func triggerMenu(index: Int) -> some View {
        Menu {
            // Intro uses `INT_FRAC` @ Start (prelude). Other modules may use Start for meditation 00:00.
            let isStartTaken = cueSettings.enumerated().contains { (i, cs) in
                i != index && cs.triggerType == .start && cs.cue.id != "INT_FRAC"
            }
            Button("Start") {
                cueSettings[index].triggerType = .start
                cueSettings[index].minute = nil
            }
            .disabled(isStartTaken)
            .foregroundColor(isStartTaken ? Color.black : Color.primary)

            ForEach(practiceMinutes > 1 ? Array(1..<practiceMinutes) : [], id: \.self) { value in
                let isMinuteTaken = cueSettings.enumerated().contains { (i, cs) in
                    i != index && cs.triggerType == .minute && cs.minute == value
                }
                Button("\(value) min") {
                    cueSettings[index].triggerType = .minute
                    cueSettings[index].minute = value
                }
                .disabled(isMinuteTaken)
                .foregroundColor(isMinuteTaken ? Color.black : Color.primary)
            }

            let isEndTaken = cueSettings.enumerated().contains { (i, cs) in
                i != index && cs.triggerType == .end
            }
            Button("End") {
                cueSettings[index].triggerType = .end
                cueSettings[index].minute = nil
            }
            .disabled(isEndTaken)
            .foregroundColor(isEndTaken ? Color.black : Color.primary)
        } label: {
            CueIndicatorView(
                text: displayText(for: cueSettings[index]),
                isSelected: false,
                action: nil,
                customFontSize: 16,
                source: "Cues-Trigger",
                isMenuButton: true
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        }
    }

    // MARK: - Cue Management
    
    private func addCue() {
        // Default to the first available cue if present; otherwise fallback.
        let defaultCue: Cue = !catalogsManager.cues.isEmpty ? catalogsManager.cues.first! : Cue(id: "None", name: "None", url: "")
        
        // Determine the next available trigger:
        // 1. If no cue is set to Start, assign Start.
        if !cueSettings.contains(where: { $0.triggerType == .start }) {
            let newCueSetting = CueSetting(triggerType: .start, minute: nil, cue: defaultCue)
            cueSettings.append(newCueSetting)
            return
        }
        
        // 2. Else, try to assign the smallest available minute value.
        guard practiceMinutes > 1 else {
            if !cueSettings.contains(where: { $0.triggerType == .end }) {
                let newCueSetting = CueSetting(triggerType: .end, minute: nil, cue: defaultCue)
                cueSettings.append(newCueSetting)
            } else {
                let fallbackCueSetting = CueSetting(triggerType: .minute, minute: nil, cue: defaultCue)
                cueSettings.append(fallbackCueSetting)
            }
            return
        }
        for minute in 1..<practiceMinutes {
            if !cueSettings.contains(where: { $0.triggerType == .minute && $0.minute == minute }) {
                let newCueSetting = CueSetting(triggerType: .minute, minute: minute, cue: defaultCue)
                cueSettings.append(newCueSetting)
                return
            }
        }
        
        // 3. Else, if End is not taken, assign End.
        if !cueSettings.contains(where: { $0.triggerType == .end }) {
            let newCueSetting = CueSetting(triggerType: .end, minute: nil, cue: defaultCue)
            cueSettings.append(newCueSetting)
            return
        }
        
        // 4. Fallback: assign a minute trigger with no specific minute (user must select manually).
        let fallbackCueSetting = CueSetting(triggerType: .minute, minute: nil, cue: defaultCue)
        cueSettings.append(fallbackCueSetting)
    }
    
    private func removeCue(at index: Int) {
        if index < cueSettings.count {
            cueSettings.remove(at: index)
        }
    }
}

struct CueConfigurationView_Previews: PreviewProvider {
    @State static var cueSettings: [CueSetting] = [
        CueSetting(triggerType: .minute, minute: 5, cue: Cue(id: "GB", name: "Gentle Bell", url: "gs://..."))
    ]
    
    static var previews: some View {
        ZStack {
            Color.backgroundDarkPurple.ignoresSafeArea()
            CueConfigurationView(practiceMinutes: 20, cueSettings: $cueSettings)
                .padding()
        }
    }
}
