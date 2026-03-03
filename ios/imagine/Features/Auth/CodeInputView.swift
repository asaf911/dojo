//
//  CodeInputView.swift
//  imagine
//
//  Created by Asaf Shamir on 2026-02-12
//

import SwiftUI
import UIKit

/// A 4-digit code input with individual digit boxes.
/// Supports auto-fill from email via `.oneTimeCode` content type.
struct CodeInputView: View {
    @Binding var code: String
    var onComplete: (() -> Void)? = nil

    let codeLength = 4
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden TextField overlays digit boxes so long-press shows Paste in context menu.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: code) { _, newValue in
                    // Keep only digits and cap at codeLength
                    let filtered = String(newValue.filter(\.isNumber).prefix(codeLength))
                    if filtered != newValue {
                        code = filtered
                    }
                    // Auto-submit when all digits entered
                    if filtered.count == codeLength {
                        onComplete?()
                    }
                }

            // Visual digit boxes (fixed frame prevents deformation)
            HStack(spacing: 14) {
                ForEach(0..<codeLength, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .frame(width: 266, height: 56)
        }
        .frame(width: 266, height: 56)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .contextMenu {
            Button("Paste") {
                if let string = UIPasteboard.general.string {
                    let digits = String(string.filter(\.isNumber).prefix(codeLength))
                    code = digits
                    if digits.count == codeLength {
                        onComplete?()
                    }
                }
            }
            .disabled(!UIPasteboard.general.hasStrings)
        }
        .onAppear { isFocused = true }
    }

    // MARK: - Digit Box

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        let digit = digitCharacter(at: index)
        let isCurrentIndex = index == code.count && isFocused

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("inputFieldBackground"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isCurrentIndex ? Color.dojoTurquoise : Color.clear,
                            lineWidth: 1.5
                        )
                )

            if let digit = digit {
                Text(String(digit))
                    .font(Font.nunito(size: 28, style: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 56, height: 56)
    }

    private func digitCharacter(at index: Int) -> Character? {
        guard index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        Color.backgroundDarkPurple.ignoresSafeArea()
        CodeInputView(code: .constant("12"))
    }
}
#endif
