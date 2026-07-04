import Foundation

/// Portions a trainer variant meal for a profile.
///
/// Husband rule (trainer instruction 4): the multiplier scales *weighed*
/// ingredients (meat, carbs, sauces) but NOT piece items — a protein pudding or
/// a piece of fruit stays 1 for both of them. So `.piece`-unit lines are left at
/// her grams; everything else is multiplied.
public struct VariantPortioner: Sendable {
    public let calculator: PortionCalculator
    public init(calculator: PortionCalculator) { self.calculator = calculator }

    /// Scaled RAW lines for a profile. `multiplier` = 1.0 for her.
    public func lines(for meal: MealTemplate, multiplier: Double) -> [RecipeLine] {
        meal.lines.map { line in
            let isPiece = calculator.database.ingredient(id: line.ingredientID)?.unit == .piece
            let grams = isPiece ? line.baseRawGrams : line.baseRawGrams * multiplier
            return RecipeLine(ingredientID: line.ingredientID, baseRawGrams: grams)
        }
    }

    public func macros(for meal: MealTemplate, multiplier: Double = 1.0) throws -> MacroVector {
        try calculator.baseMacros(for: lines(for: meal, multiplier: multiplier))
    }

    public func dayMacros(for variant: DayVariant, multiplier: Double = 1.0) throws -> MacroVector {
        try MacroVector.sum(variant.meals.map { try macros(for: $0, multiplier: multiplier) })
    }
}

public extension SubstitutionEngine {
    /// The trainer's explicit free swap (rule 3 / instruction 1): chicken breast
    /// ↔ turkey breast (or any 1:1 category swap), re-gram'd for EQUAL protein.
    /// Returns the grams of `substitute` that match `grams` of `original`.
    func equalProteinGrams(from original: Ingredient, to substitute: Ingredient, grams: Double) -> Double {
        guard substitute.per100g.protein > 0 else { return grams }
        return grams * original.per100g.protein / substitute.per100g.protein
    }
}
