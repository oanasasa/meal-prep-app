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
/// Uses an adaptive grid rather than a fixed HStack so it reflows to 2 columns
/// at larger accessibility text sizes instead of clipping or overflowing.
struct MacroSummary: View {
    let macros: MacroVector
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var minPillWidth: CGFloat { typeSize.isAccessibilitySize ? 140 : 60 }
    private var gap: CGFloat { compact ? 6 : 10 }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minPillWidth), spacing: gap)], spacing: gap) {
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
/// Same adaptive-grid reflow as `MacroSummary`, for the same reason.
struct DeltaChips: View {
    let delta: MacroVector
    let ok: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var minChipWidth: CGFloat { typeSize.isAccessibilitySize ? 120 : 70 }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minChipWidth), spacing: 6)], spacing: 6) {
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

/// Three-tier tolerance colour used by the plan editor's live "day total vs
/// target" feedback: green within ±5%, orange within ±10%, red beyond.
enum ToleranceTier {
    case good, warn, bad

    init(_ delta: MacroDelta, on field: MacroField = .kcal) {
        let frac = abs(delta.fractional[field])
        if frac <= 0.05 { self = .good }
        else if frac <= 0.10 { self = .warn }
        else { self = .bad }
    }

    var color: Color {
        switch self {
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }
}

/// "Day total: 1,940 kcal, +40 vs target" — live feedback while editing a meal
/// or macro targets, colour-coded by how far the day total has drifted.
struct DayTotalBanner: View {
    let label: String
    let actual: MacroVector
    let target: MacroVector

    private var delta: MacroDelta { MacroDelta(target: target, actual: actual) }
    private var tier: ToleranceTier { ToleranceTier(delta) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("\(Fmt.g(actual.kcal)) kcal").font(.headline).foregroundStyle(tier.color)
            }
            Spacer()
            Text("\(Fmt.signed(delta.absolute.kcal)) vs target")
                .font(.subheadline.weight(.semibold)).foregroundStyle(tier.color)
        }
        .padding()
        .background(tier.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
