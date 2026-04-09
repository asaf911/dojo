//
//  FractionalModules+Screen.swift
//  Dojo
//
//  Dev-only: UI for `FractionalModules.ViewModel` (module, duration, body-scan toggles). All actions → VM.
//  Body scan behavior: `docs/body-scan-tier-composer.md`.
//

import SwiftUI

extension FractionalModules {

    enum Module: String, CaseIterable {
        case nostrilFocus = "NF_FRAC"
        case iAmMantra = "IM_FRAC"
        case bodyScan = "BS_FRAC"
        case perfectBreath = "PB_FRAC"
        case intro = "INT_FRAC"

        var displayName: String {
            switch self {
            case .nostrilFocus: "Nostril Focus"
            case .iAmMantra: "I AM Mantra"
            case .bodyScan: "Body Scan"
            case .perfectBreath: "Perfect Breath"
            case .intro: "Intro"
            }
        }
    }

    struct Screen: View {
        @State private var viewModel: ViewModel
        @State private var selectedModule: Module = .nostrilFocus
        @State private var pendingConfig: TimerSessionConfig?
        @EnvironmentObject var navigationCoordinator: NavigationCoordinator
        @Environment(\.dismiss) private var dismiss

        init(viewModel: ViewModel = ViewModel()) {
            _viewModel = State(initialValue: viewModel)
        }

        var body: some View {
            VStack(spacing: 24) {
                Text("Fractional Modules")
                    .nunitoFont(size: 20, style: .bold)
                    .foregroundColor(.foregroundLightGray)

                VStack(spacing: 8) {
                    Text("Module")
                        .nunitoFont(size: 16, style: .regular)
                        .foregroundColor(.foregroundLightGray)

                    Picker("Module", selection: $selectedModule) {
                        ForEach(Module.allCases, id: \.self) { module in
                            Text(module.displayName).tag(module)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 16)
                    .onChange(of: selectedModule) { _, newValue in
                        viewModel.moduleId = newValue.rawValue
                    }
                }

                VStack(spacing: 8) {
                    Text("Session: \(viewModel.selectedMinutes) min")
                        .nunitoFont(size: 16, style: .regular)
                        .foregroundColor(.foregroundLightGray)

                    Picker("Minutes", selection: $viewModel.selectedMinutes) {
                        ForEach(1...10, id: \.self) { min in
                            Text("\(min)m").tag(min)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }

                if selectedModule == .perfectBreath {
                    Text("Uses measured clip durations from the Perfect Breath fractional catalog.")
                        .nunitoFont(size: 13, style: .regular)
                        .foregroundColor(.foregroundLightGray.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if selectedModule == .intro {
                    Text("Intro length is chosen from total session time (shortest for 1m, up to 90s for 10m+).")
                        .nunitoFont(size: 13, style: .regular)
                        .foregroundColor(.foregroundLightGray.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if selectedModule == .bodyScan {
                    VStack(spacing: 8) {
                        Text("Scan direction")
                            .nunitoFont(size: 16, style: .regular)
                            .foregroundColor(.foregroundLightGray)
                        Picker("Direction", selection: $viewModel.bodyScanDirection) {
                            Text("Up (feet → head)").tag(FractionalModules.BodyScanDirection.up)
                            Text("Down (head → feet)").tag(FractionalModules.BodyScanDirection.down)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Intro clips")
                            .nunitoFont(size: 16, style: .regular)
                            .foregroundColor(.foregroundLightGray)
                            .frame(maxWidth: .infinity)
                        Toggle(isOn: Binding(
                            get: { viewModel.includeIntroShort },
                            set: { newValue in
                                viewModel.includeIntroShort = newValue
                                if !newValue, !viewModel.includeIntroLong {
                                    viewModel.includeIntroLong = true
                                }
                            }
                        )) {
                            Text("Short (\"We will now begin a body scan\")")
                                .nunitoFont(size: 16, style: .regular)
                                .foregroundColor(.foregroundLightGray)
                        }
                        Toggle(isOn: Binding(
                            get: { viewModel.includeIntroLong },
                            set: { newValue in
                                viewModel.includeIntroLong = newValue
                                if !newValue, !viewModel.includeIntroShort {
                                    viewModel.includeIntroShort = true
                                }
                            }
                        )) {
                            Text("Long (full guidance)")
                                .nunitoFont(size: 16, style: .regular)
                                .foregroundColor(.foregroundLightGray)
                        }
                    }
                    .padding(.horizontal, 24)
                    Toggle(isOn: $viewModel.includeBodyScanEntry) {
                        Text("Entry cue")
                            .nunitoFont(size: 16, style: .regular)
                            .foregroundColor(.foregroundLightGray)
                    }
                    .padding(.horizontal, 24)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .nunitoFont(size: 13, style: .regular)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Button {
                    viewModel.play()
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.backgroundDarkPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Play")
                            .nunitoFont(size: 16, style: .bold)
                            .foregroundColor(.backgroundDarkPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Color.dojoTurquoise)
                .cornerRadius(12)
                .disabled(viewModel.isLoading)
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 32)
            .background(Color.backgroundDarkPurple.ignoresSafeArea())
            .onAppear {
                viewModel.onAction = { action in
                    switch action {
                    case .playSession(let config):
                        pendingConfig = config
                        dismiss()
                    }
                }
            }
            .onDisappear {
                guard let config = pendingConfig else { return }
                pendingConfig = nil
                GeneralBackgroundMusicController.shared.fadeOutForPractice()
                navigationCoordinator.showTimerPlayerSheet(timerConfig: config)
            }
        }
    }
}
