import Foundation
import SwiftData
import MealPrepCore

/// A user-added ingredient not in the bundled database (the trainer introduced
/// a new food). Merged with the bundled catalogue at runtime — see
/// `AppModel.reload`.
@Model
final class IngredientEntity {
    @Attribute(.unique) var ingredientID: String = ""
    var name: String = ""
    var sectionRaw: String = "pantry"
    var groupRaw: String = "vegetable"
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var unitRaw: String = "grams"
    var gramsPerPiece: Double?
    var isPerishableProtein: Bool = false
    var isWholeFood: Bool = true
    var cookedYieldFactor: Double = 1.0
    var createdAt: Date = Date()

    init(ingredientID: String, name: String, sectionRaw: String, groupRaw: String,
         kcal: Double, protein: Double, carbs: Double, fat: Double,
         unitRaw: String = "grams", gramsPerPiece: Double? = nil,
         isPerishableProtein: Bool = false, isWholeFood: Bool = true,
         cookedYieldFactor: Double = 1.0) {
        self.ingredientID = ingredientID
        self.name = name
        self.sectionRaw = sectionRaw
        self.groupRaw = groupRaw
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.unitRaw = unitRaw
        self.gramsPerPiece = gramsPerPiece
        self.isPerishableProtein = isPerishableProtein
        self.isWholeFood = isWholeFood
        self.cookedYieldFactor = cookedYieldFactor
    }

    func asIngredient() -> Ingredient {
        Ingredient(id: ingredientID, name: name,
                  section: StoreSection(rawValue: sectionRaw) ?? .pantry,
                  group: SubstitutionGroup(rawValue: groupRaw) ?? .vegetable,
                  per100g: MacroVector(kcal: kcal, protein: protein, carbs: carbs, fat: fat),
                  cookedYieldFactor: cookedYieldFactor, isWholeFood: isWholeFood,
                  unit: MeasureUnit(rawValue: unitRaw) ?? .grams,
                  gramsPerPiece: gramsPerPiece, isPerishableProtein: isPerishableProtein)
    }

    /// Kebab-case slug from a display name, e.g. "Turkey Bacon" -> "turkey-bacon".
    static func slug(from name: String) -> String {
        let lowered = name.lowercased()
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: " -"))
        let cleaned = String(lowered.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.split(separator: " ").joined(separator: "-")
    }
}
