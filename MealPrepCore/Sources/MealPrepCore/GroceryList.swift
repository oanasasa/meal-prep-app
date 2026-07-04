import Foundation

/// One line of the shopping list: everything of this ingredient needed across
/// the whole week, for both profiles, aggregated into one amount.
public struct GroceryItem: Identifiable, Equatable, Sendable {
    public var id: String { ingredientID }
    public let ingredientID: String
    public let name: String
    public let section: StoreSection
    public let totalRawGrams: Double
    public let unit: MeasureUnit
    public let gramsPerPiece: Double?

    /// Display quantity: whole pieces for piece-unit ingredients, grams otherwise.
    public var displayQuantity: String {
        if unit == .piece, let perPiece = gramsPerPiece, perPiece > 0 {
            let pieces = Int((totalRawGrams / perPiece).rounded(.up))
            return "\(pieces) pc"
        }
        return "\(Int(totalRawGrams.rounded())) g"
    }
}

/// Builds the week's shopping list purely from what the plan needs — this is a
/// lightweight stand-in for the full Phase-3 grocery flow (fridge inventory +
/// restock checklist aren't wired up yet, so nothing is subtracted here; it's
/// "everything the week needs," not "what's still missing").
public enum GroceryListBuilder {
    public static func build(for week: VariantWeek, profiles: [Profile],
                             portioner: VariantPortioner, database: IngredientDatabase) -> [GroceryItem] {
        var totals: [String: Double] = [:]
        for day in week.days {
            for meal in day.meals {
                for profile in profiles {
                    for line in portioner.lines(for: meal.meal, multiplier: profile.portionMultiplier) {
                        totals[line.ingredientID, default: 0] += line.baseRawGrams
                    }
                }
            }
        }
        return totals.compactMap { id, grams -> GroceryItem? in
            guard let ing = database.ingredient(id: id) else { return nil }
            return GroceryItem(ingredientID: id, name: ing.name, section: ing.section,
                               totalRawGrams: grams, unit: ing.unit, gramsPerPiece: ing.gramsPerPiece)
        }.sorted { $0.section.rawValue == $1.section.rawValue ? $0.name < $1.name : $0.section.rawValue < $1.section.rawValue }
    }
}
