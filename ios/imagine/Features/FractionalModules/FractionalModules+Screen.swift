//
//  FractionalModules+Screen.swift
//  Dojo
//
//  Dev-only screen for testing fractional module playback.
//

import SwiftUI

extension FractionalModules {

    enum Module: String, CaseIterable {
        case nostrilFocus = "NF_FRAC"
        case iAmMantra = "IM_FRAC"
        case bodyScan = "BS_FRAC"

        var displayName: String {
            switch self {
            case .nostrilFocus: "Nostril Focus"
            case .iAmMantra: "I AM Mantra"
            case .bodyScan: "Body Scan"
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
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .onChange(of: selectedModule) { _, newValue in
                        viewModel.moduleId = newValue.rawValue
                    }
                }

                VStack(spacing: 8) {
                    Text("Duration: \(viewModel.selectedMinutes) min")
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
                    VStack(spacing: 8) {
                        Text("Intro")
                            .nunitoFont(size: 16, style: .regular)
                            .foregroundColor(.foregroundLightGray)
                        Picker("Intro", selection: $viewModel.introStyle) {
                            Text("Short").tag(FractionalModules.IntroStyle.short)
                            Text("Long").tag(FractionalModules.IntroStyle.long)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }
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
