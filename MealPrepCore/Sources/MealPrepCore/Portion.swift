import Foundation

/// An eater. "Her" holds the trainer's macros with multiplier 1.0; "Husband"
/// either scales her portions by a multiplier (1.3–1.5) or carries his own
/// daily targets.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Daily targets from the trainer (or his own).
    public let dailyTarget: MacroVector
    /// Uniform scaling applied to her base recipe grams. 1.0 for her.
    public let portionMultiplier: Double

    public init(id: String, name: String, dailyTarget: MacroVector, portionMultiplier: Double = 1.0) {
        self.id = id
        self.name = name
        self.dailyTarget = dailyTarget
        self.portionMultiplier = portionMultiplier
    }
}

/// One line of a recipe: an ingredient reference plus the base (her) RAW grams.
public struct RecipeLine: Codable, Equatable, Sendable {
    public let ingredientID: String
    public let baseRawGrams: Double

    public init(ingredientID: String, baseRawGrams: Double) {
        self.ingredientID = ingredientID
        self.baseRawGrams = baseRawGrams
    }
}

/// The fully-resolved amount of one ingredient for one profile, ready to show
/// in the recipe card and cook mode.
public struct PortionedLine: Equatable, Sendable {
    public let ingredient: Ingredient
    public let rawGrams: Double
    public let cookedGrams: Double
    public let macros: MacroVector
}

/// Pure calculator over the ingredient database. No persistence, no UI — this is
/// the piece the unit tests hammer.
public struct PortionCalculator: Sendable {
    public let database: IngredientDatabase

    public init(database: IngredientDatabase) {
        self.database = database
    }

    /// Resolve every recipe line for a given profile (applies the profile's
    /// portion multiplier), returning per-line grams + macros.
    public func portionedLines(for recipe: [RecipeLine], profile: Profile) throws -> [PortionedLine] {
        try recipe.map { line in
            guard let ingredient = database.ingredient(id: line.ingredientID) else {
                throw MealPrepError.unknownIngredient(line.ingredientID)
            }
            let rawGrams = line.baseRawGrams * profile.portionMultiplier
            return PortionedLine(
                ingredient: ingredient,
                rawGrams: rawGrams,
                cookedGrams: ingredient.cookedGrams(forRawGrams: rawGrams),
                macros: ingredient.macros(forGrams: rawGrams)
            )
        }
    }

    /// Total macros for a recipe as eaten by a profile.
    public func totalMacros(for recipe: [RecipeLine], profile: Profile) throws -> MacroVector {
        try MacroVector.sum(portionedLines(for: recipe, profile: profile).map(\.macros))
    }

    /// Macros of a recipe at its base ("Her" reference) grams, no multiplier.
    /// Used by the weekly generator to scale a recipe toward a meal target.
    public func baseMacros(for recipe: [RecipeLine]) throws -> MacroVector {
        try MacroVector.sum(recipe.map { line in
            guard let ing = database.ingredient(id: line.ingredientID) else {
                throw MealPrepError.unknownIngredient(line.ingredientID)
            }
            return ing.macros(forGrams: line.baseRawGrams)
        })
    }

    /// Total RAW grams to cook for a whole batch session: base recipe × all
    /// profiles × number of days. Feeds cook mode's "cook this much" and the
    /// per-person container split.
    public func batchRawGrams(for recipe: [RecipeLine],
                              profiles: [Profile],
                              days: Int) throws -> [String: Double] {
        var totals: [String: Double] = [:]
        for profile in profiles {
            for line in try portionedLines(for: recipe, profile: profile) {
                totals[line.ingredient.id, default: 0] += line.rawGrams * Double(days)
            }
        }
        return totals
    }
}

public enum MealPrepError: Error, Equatable {
    case unknownIngredient(String)
    case emptyRecipe
}
