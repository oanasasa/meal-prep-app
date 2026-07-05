import SwiftUI

/// A form row where tapping anywhere — the label, the trailing space, or the
/// field itself — starts editing the input. The row gesture only *focuses* the
/// field (it never resigns), and tapping directly on the field still positions
/// the cursor / double-taps to select, because the field consumes its own
/// touches. So this widens the tap target without breaking text selection.
struct TappableFieldRow<Field: View>: View {
    let label: String
    var unit: String? = nil
    @FocusState private var focused: Bool
    @ViewBuilder var field: (FocusState<Bool>.Binding) -> Field

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            field($focused)
            if let unit { Text(unit).foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}
