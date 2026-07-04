import SwiftUI
import MealPrepCore

enum Fmt {
    static func g(_ v: Double) -> String { String(format: "%.0f", v.rounded()) }
    static func signed(_ v: Double) -> String {
        let r = v.rounded()
        return (r >= 0 ? "+" : "") + String(format: "%.0f", r)
    }
}

/// The four macros as coloured pills. Reused on the home cards and results.
struct MacroSummary: View {
    let macros: MacroVector
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            pill("\(Fmt.g(macros.kcal))", "kcal", .orange)
            pill("\(Fmt.g(macros.protein))g", "protein", .pink)
            pill("\(Fmt.g(macros.carbs))g", "carbs", .blue)
            pill("\(Fmt.g(macros.fat))g", "fat", .yellow)
        }
    }

    private func pill(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            if !compact { Text(label).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 4 : 8)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Signed delta chips, e.g. "−12 kcal  +2 g P". Green when within tolerance.
struct DeltaChips: View {
    let delta: MacroVector
    let ok: Bool

    var body: some View {
        HStack(spacing: 6) {
            chip("\(Fmt.signed(delta.kcal)) kcal")
            chip("\(Fmt.signed(delta.protein)) P")
            chip("\(Fmt.signed(delta.carbs)) C")
            chip("\(Fmt.signed(delta.fat)) F")
        }
        .font(.caption.monospacedDigit())
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((ok ? Color.green : Color.secondary).opacity(0.15),
                       in: Capsule())
            .foregroundStyle(ok ? Color.green : Color.secondary)
    }
}
