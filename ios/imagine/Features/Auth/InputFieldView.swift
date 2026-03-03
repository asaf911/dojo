import SwiftUI

struct InputFieldView: View {
    var title: String
    var isSecure: Bool
    @Binding var text: String
    var textContentType: UITextContentType?
    var keyboardType: UIKeyboardType
    // Optional icon asset name to be shown on the right side within the field.
    var iconName: String? = nil
    
    // Local focus state to detect when the field is active.
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Text container: expands to fill available space.
            ZStack(alignment: .leading) {
                if text.isEmpty && !isFieldFocused {
                    Text(title)
                        .nunitoFont(size: 14, style: .medium)
                        .foregroundColor(.textForegroundGray)
                        .lineLimit(1)
                }
                Group {
                    if isSecure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .focused($isFieldFocused)
                .autocapitalization(.none)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .font(Font.nunito(size: 18, style: .regular))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Icon container with fixed width of 20.
            if let iconName = iconName {
                Image(iconName)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .frame(width: 20) // Fix container width to 20
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 13)
        .frame(width: 288, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 100)
                .fill(Color("inputFieldBackground"))
        )
    }
}

struct InputFieldView_Previews: PreviewProvider {
    @State static var text = ""
    static var previews: some View {
        VStack(spacing: 20) {
            InputFieldView(title: "Enter your email",
                           isSecure: false,
                           text: $text,
                           textContentType: .username,
                           keyboardType: .emailAddress,
                           iconName: "inputEmail")
            InputFieldView(title: "Enter your password",
                           isSecure: true,
                           text: $text,
                           textContentType: .newPassword,
                           keyboardType: .default,
                           iconName: "inputLock")
            InputFieldView(title: "Confirm Password",
                           isSecure: true,
                           text: $text,
                           textContentType: .newPassword,
                           keyboardType: .default,
                           iconName: "inputLock")
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}
