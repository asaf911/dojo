// ClearCacheView.swift
import SwiftUI

struct ClearCacheView: View {
    @State private var selections: [ClearCacheCategory: Bool] = {
        var dict = [ClearCacheCategory: Bool]()
        for category in ClearCacheCategory.allCases {
            dict[category] = false
        }
        return dict
    }()

    var onConfirm: ([ClearCacheCategory]) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.backgroundNavy.edgesIgnoringSafeArea(.all)

            VStack(spacing: 8) {
                Text("Clear Data")
                    .nunitoFont(size: 20, style: .bold)
                    .foregroundColor(.white)

                Text("Choose what you'd like to remove:")
                    .nunitoFont(size: 14, style: .regular)
                    .foregroundColor(.foregroundLightGray)

                // Toggle list
                VStack(spacing: 6) {
                    ForEach(ClearCacheCategory.allCases.filter { $0 != .onboarding }, id: \.self) { category in
                        Toggle(isOn: Binding(
                            get: { selections[category] ?? false },
                            set: { selections[category] = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.displayName)
                                    .nunitoFont(size: 16, style: .bold)
                                    .foregroundColor(.white)
                                
                                Text(category.description)
                                    .nunitoFont(size: 14, style: .regular)
                                    .foregroundColor(.foregroundLightGray)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.dojoTurquoise))
                        .padding(8)
                        .background(Color.backgroundNavy)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    }
                }
                .padding(.top, 0)

                // Buttons
                HStack(spacing: 16) {
                    Button(action: {
                        onCancel()
                    }) {
                        Text("Cancel")
                            .nunitoFont(size: 16, style: .bold)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(.foregroundLightGray)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.foregroundLightGray, lineWidth: 2)
                            )
                    }

                    Button(action: {
                        let chosenCategories = selections.filter { $0.value }.map { $0.key }
                        onConfirm(chosenCategories)
                    }) {
                        Text("Clear")
                            .nunitoFont(size: 16, style: .bold)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(.textOrange)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.textOrange, lineWidth: 2)
                            )
                    }
                    .disabled(!selections.values.contains(true))
                    .opacity(selections.values.contains(true) ? 1.0 : 0.5)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

// MARK: - Preview
struct ClearCacheView_Previews: PreviewProvider {
    static var previews: some View {
        ClearCacheView(onConfirm: { _ in }, onCancel: {})
            .previewLayout(.sizeThatFits)
    }
}
