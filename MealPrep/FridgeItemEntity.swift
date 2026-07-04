import Foundation
import SwiftData
import MealPrepCore

/// One row per ingredient in the fridge/pantry. Quantity is always raw grams
/// (piece items store their gram-equivalent; the UI converts for display).
/// Inline defaults on every property — SwiftData's lightweight migration needs
/// them on the declaration itself to backfill existing rows when new fields
/// are added later (a Phase-4 store-migration bug taught this the hard way).
@Model
final class FridgeItemEntity {
    @Attribute(.unique) var ingredientID: String = ""
    var quantityGrams: Double = 0
    var addedDate: Date = Date.distantPast

    init(ingredientID: String, quantityGrams: Double, addedDate: Date = Date()) {
        self.ingredientID = ingredientID
        self.quantityGrams = quantityGrams
        self.addedDate = addedDate
    }

    var asFridgeItem: FridgeItem {
        FridgeItem(ingredientID: ingredientID, quantityGrams: quantityGrams, addedDate: addedDate)
    }
}
