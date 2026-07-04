import Foundation

/// One meal template affected by a missing ingredient, plus every day this
/// week it's actually scheduled on (a template can repeat via the rotation).
public struct AffectedMeal: Identifiable, Equatable, Sendable {
    public var id: String { meal.id }
    public let meal: MealTemplate
    public let variantID: String
    public let dayOffsets: [Int]
}

/// Connects a missing grocery item back to the specific meals it would break
/// this week, so the restock flow can trigger a substitution exactly where
/// it's needed instead of a generic "something's missing" prompt.
public enum RestockPlanner {
    public static func affectedMeals(missingIngredientID: String, in week: VariantWeek) -> [AffectedMeal] {
        var byMealID: [String: (meal: MealTemplate, variantID: String, days: [Int])] = [:]
        for day in week.days {
            for planned in day.meals where planned.meal.lines.contains(where: { $0.ingredientID == missingIngredientID }) {
                if var existing = byMealID[planned.meal.id] {
                    existing.days.append(day.dayOffset)
                    byMealID[planned.meal.id] = existing
                } else {
                    byMealID[planned.meal.id] = (planned.meal, planned.variantID, [day.dayOffset])
                }
            }
        }
        return byMealID.values
            .map { AffectedMeal(meal: $0.meal, variantID: $0.variantID, dayOffsets: $0.days.sorted()) }
            .sorted { $0.dayOffsets.first ?? 0 < $1.dayOffsets.first ?? 0 }
    }
}

/// How well a whole day-variant matches what's actually in the fridge right
/// now — the basis for "switch the whole day to a variant that's in the
/// fridge" when a substitution alone can't save the plan.
public struct VariantFitScore: Identifiable, Equatable, Sendable {
    public var id: String { variantID }
    public let variantID: String
    /// Fraction (0...1) of this variant's ingredient lines that are fully
    /// covered by current fridge stock.
    public let fitFraction: Double
    public let missingIngredientIDs: [String]
}

public enum VariantFallback {
    public static func scoreVariants(_ variants: [DayVariant], against fridge: FridgeInventory) -> [VariantFitScore] {
        variants.map { variant in
            let lines = variant.meals.flatMap(\.lines)
            guard !lines.isEmpty else {
                return VariantFitScore(variantID: variant.id, fitFraction: 1, missingIngredientIDs: [])
            }
            let missing = lines.filter { !fridge.hasEnough(ingredientID: $0.ingredientID, grams: $0.baseRawGrams) }
            let fit = Double(lines.count - missing.count) / Double(lines.count)
            return VariantFitScore(variantID: variant.id, fitFraction: fit,
                                   missingIngredientIDs: Array(Set(missing.map(\.ingredientID))).sorted())
        }.sorted { $0.fitFraction > $1.fitFraction }
    }

    /// The best alternative to `currentVariantID`, but only if it's a
    /// meaningfully better fridge fit — otherwise nil (don't suggest
    /// disruptive whole-day swaps for a marginal improvement).
    public static func suggestAlternative(to currentVariantID: String, among variants: [DayVariant],
                                          fridge: FridgeInventory,
                                          minimumImprovement: Double = 0.15) -> VariantFitScore? {
        let scores = scoreVariants(variants, against: fridge)
        let currentFit = scores.first { $0.variantID == currentVariantID }?.fitFraction ?? 0
        guard let best = scores.first(where: { $0.variantID != currentVariantID }) else { return nil }
        return (best.fitFraction - currentFit) >= minimumImprovement ? best : nil
    }
}
