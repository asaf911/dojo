//
//  CueConfigurationView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-24
//

import SwiftUI

/// Create-screen step row layout (matches design spec: full-width card, fixed height, insets).
private enum CreateStepRowMetrics {
    /// Inner band height: space for **two** lines of module title at `Nunito` 16 heavy (default size). Every row uses this height so single-line titles match wrapped titles.
    static let innerContentHeight: CGFloat = 48
    static let verticalPadding: CGFloat = 16
    /// Card height: two-line title band + 16pt top + 16pt bottom.
    static let rowHeight: CGFloat = innerContentHeight + verticalPadding * 2
    static let horizontalInset: CGFloat = 8
    static let dragHandleHorizontalPadding: CGFloat = 8
    /// Matches `CreateStepDragHandleIcon` width + `.padding(.horizontal, dragHandleHorizontalPadding)` for column alignment.
    static let dragHandleColumnWidth: CGFloat = (4 + 3 + 4) + 2 * dragHandleHorizontalPadding
    static let moduleToTrailingMinGap: CGFloat = 12
    /// Space between duration capsule / trigger UI and the delete control.
    static let trailingControlGap: CGFloat = 14
    static let interRowSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 10
    /// Leading edge accent; matches `CreateStepModuleNameLabel` text color.
    static let leadingBorderWidth: CGFloat = 2
    static let moduleTitleForeground: Color = .white
}

/// Module title on a step row (no capsule).
private struct CreateStepModuleNameLabel: View {
    let name: String

    var body: some View {
        Text(name)
            .font(Font.custom("Nunito", size: 16).weight(.heavy))
            .foregroundColor(CreateStepRowMetrics.moduleTitleForeground)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(name)
    }
}

/// Capsule style for `Menu` labels and “+ Add Step” (not the step module title).
private struct CreateStepPillLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .nunitoFont(size: 16, style: .regular)
            .kerning(0.07)
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .padding(.vertical, 4)
            .padding(.horizontal, 13)
            .frame(minWidth: 63)
            .background(Color.backgroundDarkPurple.opacity(0.5))
            .cornerRadius(23)
            .overlay(
                RoundedRectangle(cornerRadius: 23)
                    .inset(by: 0.5)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(text)
    }
}

/// Full-width “+ Add step” (Create screen): same glass capsule as `FractionalDurationStepper`, same height as `OnboardingPrimaryButton` (46pt, corner 23).
private struct CreateAddStepButton: View {
    let action: () -> Void

    private static let cornerRadius: CGFloat = 23
    private static let height: CGFloat = 46

    var body: some View {
        Button(action: action) {
            Group {
                if #available(iOS 26.0, *) {
                    labelCore
                        .liquidGlass(cornerRadius: Self.cornerRadius, style: .secondary)
                } else {
                    labelCore
                        .background(Color.foregroundLightGray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("+ Add step")
    }

    private var labelCore: some View {
        Text("+ Add step")
            .onboardingButtonTextStyle()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
    }
}

/// Reorder affordance (six dots); row reorder still uses the list’s long-press drag gesture.
private struct CreateStepDragHandleIcon: View {
    private let dotSize: CGFloat = 4
    private let dotGap: CGFloat = 3

    var body: some View {
        VStack(spacing: dotGap) {
            HStack(spacing: dotGap) { dot; dot }
            HStack(spacing: dotGap) { dot; dot }
            HStack(spacing: dotGap) { dot; dot }
        }
        .accessibilityHidden(true)
    }

    private var dot: some View {
        Circle()
            .fill(Color.white.opacity(0.42))
            .frame(width: dotSize, height: dotSize)
    }
}

/// Steps: modules play in list order (durations stack on the practice timeline). Bells/other cues still pick Start / minute / End.
struct CueConfigurationView: View {
    /// Practice length from the create screen (derived from module durations).
    let practiceMinutes: Int
    @Binding var cueSettings: [CueSetting]

    private let maxCues = 10
    @ObservedObject var catalogsManager = CatalogsManager.shared
    @State private var addStepModuleDialogPresented = false

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
    
    /// `List` + `.fixedSize(vertical: true)` caches intrinsic height at first layout — new rows stay off-screen. Drive height from `count` instead.
    private var stepsListLayoutHeight: CGFloat {
        let n = cueSettings.count
        guard n > 0 else { return 0 }
        return CGFloat(n) * CreateStepRowMetrics.rowHeight + CGFloat(n - 1) * CreateStepRowMetrics.interRowSpacing
    }

    /// First row is fixed when it is Intro (`INT_FRAC`); reorder applies only to steps after it.
    private var movableSectionStartIndex: Int {
        (cueSettings.first?.cue.id == "INT_FRAC") ? 1 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Steps")
                .nunitoFont(size: 18, style: .medium)
                .foregroundColor(.foregroundLightGray)
                .padding(.horizontal, 8)

            List {
                if cueSettings.first?.cue.id == "INT_FRAC" {
                    cueStepRow(at: 0, showsDragHandle: false)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if cueSettings.count > movableSectionStartIndex {
                    ForEach(Array(cueSettings.enumerated().filter { $0.offset >= movableSectionStartIndex }), id: \.element.id) { index, _ in
                        cueStepRow(at: index, showsDragHandle: true)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove(perform: moveMovableCueSteps)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .listRowSpacing(CreateStepRowMetrics.interRowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: stepsListLayoutHeight)
            .environment(\.defaultMinListRowHeight, CreateStepRowMetrics.rowHeight)
            .id(cueSettings.map(\.id))

            if cueSettings.count < maxCues {
                Group {
                    if catalogsManager.cues.isEmpty {
                        CreateAddStepButton {
                            AnalyticsManager.shared.logEvent("cue_capsule_tap", parameters: [
                                "cue_content": "+ Add step",
                                "source": "Cues-Sound"
                            ])
                            appendNewStep(with: Cue(id: "None", name: "None", url: ""))
                        }
                    } else {
                        // `Menu` inside `List` + parent `ScrollView` often drops selections; use system `confirmationDialog` (reliable).
                        CreateAddStepButton {
                            #if DEBUG
                            print("AI_debug [CueAdd] +AddStep tapped catalogCount=\(catalogsManager.cues.count) currentSteps=\(cueSettings.count)")
                            #endif
                            addStepModuleDialogPresented = true
                        }
                    }
                }
                // Anchor dialog on the container so presentation is not tied to the inner glass `Button` layer.
                .confirmationDialog("Choose module", isPresented: $addStepModuleDialogPresented, titleVisibility: .visible) {
                    Button("Quiet time") {
                        let quietId = CuePlaybackManager.quietTimeCueId
                        let cue = catalogsManager.cues.first(where: { $0.id == quietId })
                            ?? Cue(id: quietId, name: "Quiet time", url: "")
                        appendNewStep(with: cue)
                    }
                    ForEach(catalogsManager.cues.filter { $0.id != CuePlaybackManager.quietTimeCueId }) { cue in
                        Button(cue.name) {
                            #if DEBUG
                            print("AI_debug [CueAdd] dialog picked cueId=\(cue.id) name=\(cue.name)")
                            #endif
                            appendNewStep(with: cue)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        #if DEBUG
                        print("AI_debug [CueAdd] dialog cancel")
                        #endif
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, cueSettings.isEmpty ? 8 : CreateStepRowMetrics.interRowSpacing)
                .padding(.horizontal, CreateStepRowMetrics.horizontalInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .onAppear {
            ensureIntroPinnedToHead()
            if ConnectivityHelper.isConnectedToInternet() {
                catalogsManager.fetchCatalogs(triggerContext: "CueConfigurationView|pull-to-refresh")
            }
        }
        .onChange(of: cueSettings.map(\.id)) { _, _ in
            ensureIntroPinnedToHead()
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
    private func cueStepRow(at index: Int, showsDragHandle: Bool = true) -> some View {
        if cueSettings.indices.contains(index) {
            cueStepRowContent(at: index, showsDragHandle: showsDragHandle)
        }
    }

    @ViewBuilder
    private func cueStepRowContent(at index: Int, showsDragHandle: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if showsDragHandle {
                CreateStepDragHandleIcon()
                    .padding(.horizontal, CreateStepRowMetrics.dragHandleHorizontalPadding)
            } else {
                Color.clear
                    .frame(width: CreateStepRowMetrics.dragHandleColumnWidth)
            }

            CreateStepModuleNameLabel(name: cueSettings[index].cue.name)

            Spacer(minLength: CreateStepRowMetrics.moduleToTrailingMinGap)

            HStack(alignment: .center, spacing: CreateStepRowMetrics.trailingControlGap) {
                rowTrailingControls(index: index)
                cueStepDeleteButton(index: index)
            }
        }
        .padding(.horizontal, CreateStepRowMetrics.horizontalInset)
        .frame(height: CreateStepRowMetrics.innerContentHeight)
        .padding(.vertical, CreateStepRowMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: CreateStepRowMetrics.cornerRadius,
                topTrailingRadius: CreateStepRowMetrics.cornerRadius,
                style: .continuous
            )
            .fill(Color(red: 0.11, green: 0.12, blue: 0.22))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(CreateStepRowMetrics.moduleTitleForeground)
                .frame(width: CreateStepRowMetrics.leadingBorderWidth)
        }
    }

    /// Keeps Intro (`INT_FRAC`) at index 0 whenever it exists in the list.
    private func ensureIntroPinnedToHead() {
        guard let idx = cueSettings.firstIndex(where: { $0.cue.id == "INT_FRAC" }), idx != 0 else { return }
        var next = cueSettings
        let intro = next.remove(at: idx)
        next.insert(intro, at: 0)
        cueSettings = next
    }

    /// Reorder only the tail after a pinned Intro row (if any).
    private func moveMovableCueSteps(from source: IndexSet, to destination: Int) {
        ensureIntroPinnedToHead()
        let start = movableSectionStartIndex
        guard cueSettings.count > start else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            var next = cueSettings
            var tail = Array(next[start..<next.endIndex])
            tail.move(fromOffsets: source, toOffset: destination)
            next.replaceSubrange(start..<next.endIndex, with: tail)
            cueSettings = next
        }
        ensureIntroPinnedToHead()
    }

    @ViewBuilder
    private func rowTrailingControls(index: Int) -> some View {
        if cueSettings.indices.contains(index),
           cueSettings[index].isCreateSequentialModule || cueSettings[index].cue.id == "INT_FRAC" {
            fractionalOrAutoRow(index: index)
        } else if cueSettings.indices.contains(index) {
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
        .buttonStyle(.borderless)
        .fixedSize()
    }

    @ViewBuilder
    private func fractionalOrAutoRow(index: Int) -> some View {
        if !cueSettings.indices.contains(index) {
            EmptyView()
        } else if cueSettings[index].cue.id == "INT_FRAC" {
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
                        guard cueSettings.indices.contains(index) else { return 1 }
                        let cap = max(1, min([CueSetting].createFlowMaxPracticeMinutes, [CueSetting].createFlowMaxPracticeMinutes - cueSettings.sumFractionalPracticeMinutes(excludingIndex: index)))
                        return min(cueSettings[index].fractionalDuration ?? cap, cap)
                    },
                    set: { newValue in
                        guard cueSettings.indices.contains(index) else { return }
                        var next = cueSettings
                        guard next.indices.contains(index) else { return }
                        let cap = max(1, min([CueSetting].createFlowMaxPracticeMinutes, [CueSetting].createFlowMaxPracticeMinutes - next.sumFractionalPracticeMinutes(excludingIndex: index)))
                        next[index].fractionalDuration = min(newValue, cap)
                        cueSettings = next
                    }
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
            CreateStepPillLabel(text: displayText(for: cueSettings[index]))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Cue Management

    /// Applies a catalog cue to an existing row (after add). Writes back a **new array** so `List` + `@Binding` refresh reliably.
    private func applySelectedCatalogCue(at index: Int, cue: Cue) {
        guard cueSettings.indices.contains(index) else {
            #if DEBUG
            print("AI_debug [CueAdd] applySelectedCatalogCue skip badIndex=\(index) count=\(cueSettings.count)")
            #endif
            return
        }
        var next = cueSettings
        next[index].cue = cue

        if cue.isMonolithicBodyScanCatalogCue {
            let fromCatalog = CatalogsManager.shared.bodyScanDurations[cue.id]
            let parsed = Int(cue.id.dropFirst(2)).flatMap { $0 > 0 ? $0 : nil }
            let base = fromCatalog ?? parsed ?? 5
            let sumOthers = next.sumFractionalPracticeMinutes(excludingIndex: index)
            let cap = Swift.max(1, [CueSetting].createFlowMaxPracticeMinutes - sumOthers)
            next[index].fractionalDuration = Swift.min(base, cap)
        } else if next[index].isFractional {
            if cue.id == "INT_FRAC" {
                next[index].fractionalDuration = nil
                next[index].triggerType = .start
                next[index].minute = nil
            } else {
                let sumOthers = next.sumFractionalPracticeMinutes(excludingIndex: index)
                let cap = Swift.max(1, [CueSetting].createFlowMaxPracticeMinutes - sumOthers)
                let reference = referenceFractionalMinutesForNewModule(beforeIndex: index)
                next[index].fractionalDuration = Swift.min(Swift.max(1, reference), cap)
            }
        } else {
            next[index].fractionalDuration = nil
        }
        cueSettings = next
        ensureIntroPinnedToHead()
        #if DEBUG
        print("AI_debug [CueAdd] applySelectedCatalogCue done index=\(index) cueId=\(cue.id) count=\(cueSettings.count)")
        #endif
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
        #if DEBUG
        print("AI_debug [CueAdd] appendNewStep enter cueId=\(cue.id) name=\(cue.name) stepsBefore=\(cueSettings.count) practiceMinutes=\(practiceMinutes)")
        #endif
        let assign = triggerAssignmentForNewStep()
        #if DEBUG
        print("AI_debug [CueAdd] trigger assign trigger=\(String(describing: assign.0)) minute=\(String(describing: assign.1))")
        #endif
        var next = cueSettings
        next.append(CueSetting(triggerType: assign.0, minute: assign.1, cue: cue))
        cueSettings = next
        #if DEBUG
        print("AI_debug [CueAdd] appendNewStep after append count=\(cueSettings.count)")
        #endif
        let newIndex = cueSettings.count - 1
        applySelectedCatalogCue(at: newIndex, cue: cue)
        ensureIntroPinnedToHead()
        #if DEBUG
        print("AI_debug [CueAdd] appendNewStep exit count=\(cueSettings.count)")
        #endif
    }

    private func removeCue(at index: Int) {
        guard cueSettings.indices.contains(index) else { return }
        var next = cueSettings
        next.remove(at: index)
        cueSettings = next
        ensureIntroPinnedToHead()
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
                .onAppear {
                    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                        SharedUserStorage.save(value: true, forKey: .useDevServer)
                    }
                }
        }
    }
}
