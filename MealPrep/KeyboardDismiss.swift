import SwiftUI
import UIKit

extension UIApplication {
    /// Resigns the current first responder, closing the keyboard anywhere.
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Adds a plain "Done" button to the keyboard toolbar. Essential for numeric
    /// pads (`.decimalPad`/`.numberPad`), which have no return key to dismiss with.
    /// Deliberately just a small trailing text button — no background tap gesture,
    /// so native tap/double-tap text selection keeps working normally.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.endEditing() }
            }
        }
    }
}
