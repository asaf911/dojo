//
//  CueConfigurationView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import SwiftUI

private enum RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Create-screen step row layout (matches design spec: full-width card, fixed height, insets).
private enum CreateStepRowMetrics {
    static let rowHeight: CGFloat = 60
    static let horizontalInset: CGFloat = 8
    static let handleSide: CGFloat = 24
    static let handleToModuleGap: CGFloat = 8
    static let trailingControlGap: CGFloat = 8
    static let interRowSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 10
}

/// Steps: modules play in list order (durations stack on the practice timeline). Bells/other cues still pick Start / minute / End.
struct CueConfigurationView: View {
    /// Practice length from the create screen (derived from module durations).
    let practiceMinutes: Int
    @Binding var cueSettings: [CueSetting]
    /// While dragging a step handle, disables the parent `ScrollView` so the drag wins over vertical scrolling.
    @Binding var disableParentVerticalScroll: Bool

    @State private var dragSourceIndex: Int?
    @State private var dragTranslation: CGSize = .zero
    @State private var rowFramesByIndex: [Int: CGRect] = [:]
    @State private var rowFramesAtDragStart: [Int: CGRect] = [:]

    private let maxCues = 10
    @ObservedObject var catalogsManager = CatalogsManager.shared

    init(
        practiceMinutes: Int,
        cueSettings: Binding<[CueSetting]>,
        disableParentVerticalScroll: Binding<Bool> = .constant(false)
    ) {
        self.practiceMinutes = practiceMinutes
        self._cueSettings = cueSettings
        self._disableParentVerticalScroll = disableParentVerticalScroll
    }

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
    
    private static let reorderCoordinateSpaceName = "CueReorderSpace"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Steps")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.foregroundLightGray)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: CreateStepRowMetrics.interRowSpacing) {
                ForEach(Array(cueSettings.enumerated()), id: \.element.id) { index, _ in
                    cueStepRow(at: index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .coordinateSpace(name: Self.reorderCoordinateSpaceName)
            .onPreferenceChange(RowFramePreferenceKey.self) { rowFramesByIndex = $0 }

            if cueSettings.count < maxCues {
                HStack {
                    Group {
                        if catalogsManager.cues.isEmpty {
                            addStepIndicatorView(menuLabel: false)
                        } else {
                            Menu {
                                catalogCueMenuButtons { cue in
                                    appendNewStep(with: cue)
                                }
                            } label: {
                                addStepIndicatorView(menuLabel: true)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, cueSettings.isEmpty ? 8 : CreateStepRowMetrics.interRowSpacing)
                .padding(.horizontal, CreateStepRowMetrics.horizontalInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Same capsule as the per-row sound `Menu` (`CueIndicatorView` + `Cues-Sound`). `menuLabel: true` for `Menu` label only (no nested `Button`).
    @ViewBuilder
    private func addStepIndicatorView(menuLabel: Bool) -> some View {
        CueIndicatorView(
            text: "+ Add Step",
            isSelected: false,
            action: menuLabel ? nil : {
                appendNewStep(with: Cue(id: "None", name: "None", url: ""))
            },
            customFontSize: 16,
            source: "Cues-Sound",
            isMenuButton: menuLabel
        )
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    /// Catalog entries for a sound `Menu` (existing row or add step).
    @ViewBuilder
    private func catalogCueMenuButtons(onSelect: @escaping (Cue) -> Void) -> some View {
        ForEach(catalogsManager.cues) { cue in
            Button(cue.name) {
                onSelect(cue)
            }
        }
    }

    @ViewBuilder
    private func cueStepRow(at index: Int) -> some View {
        let isDraggingThisRow = dragSourceIndex == index
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: CreateStepRowMetrics.handleToModuleGap) {
                StepDragHandleView()
                    .frame(width: CreateStepRowMetrics.handleSide, height: CreateStepRowMetrics.handleSide)
                    .contentShape(Rectangle())
                    .highPriorityGesture(reorderDragGesture(sourceRowIndex: index))
                    .accessibilityLabel("Reorder step")

                cueNameMenu(index: index)
            }

            Spacer(minLength: CreateStepRowMetrics.handleToModuleGap)

            HStack(alignment: .center, spacing: CreateStepRowMetrics.trailingControlGap) {
                rowTrailingControls(index: index)
                cueStepDeleteButton(index: index)
            }
        }
        .padding(.horizontal, CreateStepRowMetrics.horizontalInset)
        .frame(height: CreateStepRowMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CreateStepRowMetrics.cornerRadius, style: .continuous)
                .fill(Color.foregroundLightGray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CreateStepRowMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .offset(y: isDraggingThisRow ? dragTranslation.height : 0)
        .zIndex(isDraggingThisRow ? 1 : 0)
        .shadow(color: .black.opacity(isDraggingThisRow ? 0.35 : 0), radius: isDraggingThisRow ? 10 : 0, y: isDraggingThisRow ? 4 : 0)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowFramePreferenceKey.self,
                    value: [index: geo.frame(in: .named(Self.reorderCoordinateSpaceName))]
                )
            }
            .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func rowTrailingControls(index: Int) -> some View {
        if cueSettings[index].isCreateSequentialModule || cueSettings[index].cue.id == "INT_FRAC" {
            fractionalOrAutoRow(index: index)
        } else {
            standardTriggerRow(index: index)
        }
    }

    private func cueStepDeleteButton(index: Int) -> some View {
        Button(action: {
            removeCue(at: index)
        }) {
            Text("x")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.white)
        }
        .fixedSize()
    }

    private func reorderDragGesture(sourceRowIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .named(Self.reorderCoordinateSpaceName))
            .onChanged { value in
                if dragSourceIndex == nil {
                    dragSourceIndex = sourceRowIndex
                    rowFramesAtDragStart = rowFramesByIndex
                    disableParentVerticalScroll = true
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                let fromIndex = dragSourceIndex ?? sourceRowIndex
                let location = value.location
                let frames = rowFramesAtDragStart
                let destination = reorderTargetIndex(
                    for: location,
                    frames: frames,
                    rowCount: cueSettings.count,
                    fallback: fromIndex
                )
                dragSourceIndex = nil
                dragTranslation = .zero
                disableParentVerticalScroll = false

                guard fromIndex != destination,
                      cueSettings.indices.contains(fromIndex),
                      cueSettings.indices.contains(destination)
                else { return }
                reorderSteps(from: fromIndex, to: destination)
            }
    }

    /// Picks the row under the release point; falls back to the nearest row by midY, then `fallback`.
    private func reorderTargetIndex(for location: CGPoint, frames: [Int: CGRect], rowCount: Int, fallback: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        if let hit = frames.first(where: { $0.value.contains(location) })?.key,
           hit >= 0, hit < rowCount {
            return hit
        }
        guard !frames.isEmpty else { return min(max(0, fallback), rowCount - 1) }
        let nearest = frames.min(by: { a, b in
            abs(a.value.midY - location.y) < abs(b.value.midY - location.y)
        })
        return min(max(0, nearest?.key ?? fallback), rowCount - 1)
    }

    private func reorderSteps(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              cueSettings.indices.contains(fromIndex),
              cueSettings.indices.contains(toIndex)
        else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
            cueSettings.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }

    @ViewBuilder
    private func cueNameMenu(index: Int) -> some View {
        Menu {
            catalogCueMenuButtons { cue in
                applySelectedCatalogCue(at: index, cue: cue)
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
            // Label is already the module `Menu` (“Intro”); no duplicate text on the trailing side.
            EmptyView()
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

    /// Applies a catalog cue to an existing row (sound `Menu`).
    private func applySelectedCatalogCue(at index: Int, cue: Cue) {
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

    /// Next trigger slot for a new step (same rules as before; cue is chosen separately).
    private func triggerAssignmentForNewStep() -> (CueTriggerType, Int?) {
        if !cueSettings.contains(where: { $0.triggerType == .start }) {
            return (.start, nil)
        }
        guard practiceMinutes > 1 else {
            if !cueSettings.contains(where: { $0.triggerType == .end }) {
                return (.end, nil)
            }
            return (.minute, nil)
        }
        for minute in 1..<practiceMinutes {
            if !cueSettings.contains(where: { $0.triggerType == .minute && $0.minute == minute }) {
                return (.minute, minute)
            }
        }
        if !cueSettings.contains(where: { $0.triggerType == .end }) {
            return (.end, nil)
        }
        return (.minute, nil)
    }

    private func appendNewStep(with cue: Cue) {
        let assign = triggerAssignmentForNewStep()
        cueSettings.append(CueSetting(triggerType: assign.0, minute: assign.1, cue: cue))
        applySelectedCatalogCue(at: cueSettings.count - 1, cue: cue)
    }

    private func removeCue(at index: Int) {
        if index < cueSettings.count {
            cueSettings.remove(at: index)
        }
    }
}

/// Six-dot grip (2×3) sized for a **24×24** create-step drag affordance.
private struct StepDragHandleView: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        .frame(width: CreateStepRowMetrics.handleSide, height: CreateStepRowMetrics.handleSide)
        .contentShape(Rectangle())
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
