import SwiftUI

struct CustomWheelPicker: UIViewRepresentable {
    @Binding var minutes: Int

    func makeUIView(context: Context) -> UIPickerView {
        let pickerView = UIPickerView()
        pickerView.delegate = context.coordinator
        pickerView.dataSource = context.coordinator
        pickerView.backgroundColor = UIColor.clear
        pickerView.selectRow(minutes - 1, inComponent: 0, animated: false)
        return pickerView
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        uiView.selectRow(minutes - 1, inComponent: 0, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        let parent: CustomWheelPicker

        init(_ parent: CustomWheelPicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            1
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            60
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            "\(row + 1)"
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.minutes = row + 1
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = UILabel()
            label.text = "\(row + 1)"
            label.textAlignment = .center
            label.font = UIFont(name: "Nunito", size: 24) // Apply desired font and size
            label.textColor = .white
            return label
        }

        // MARK: - Adjust Row Height
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            return 42 // Increase the row height
        }
    }
}
