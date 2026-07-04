import Foundation

/// One ingredient's current stock: one row per ingredient, quantity always in
/// raw grams (piece items store their gram-equivalent; the UI converts for
/// display). `addedDate` resets whenever the item is restocked — the app
/// doesn't track FIFO batches, just "how fresh is what I have."
public struct FridgeItem: Identifiable, Equatable, Sendable {
    public var id: String { ingredientID }
    public let ingredientID: String
    public let quantityGrams: Double
    public let addedDate: Date

    public init(ingredientID: String, quantityGrams: Double, addedDate: Date) {
        self.ingredientID = ingredientID
        self.quantityGrams = quantityGrams
        self.addedDate = addedDate
    }
}

/// The trainer's 2-day rule, applied to the fridge: raw perishable proteins and
/// (by the same rule, applied elsewhere to cook sessions) batch-cooked meals
/// older than 2 days are flagged "do not eat" and excluded from planning.
public enum FridgeExpiry {
    public static let maxAgeDays = 2

    public static func ageInDays(addedDate: Date, asOf: Date = Date(), calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: addedDate)
        let to = calendar.startOfDay(for: asOf)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// `n` days before `date` (start-of-day). Handy for seeding/testing fridge
    /// ages without every caller needing to hand-roll Calendar arithmetic.
    public static func daysAgo(_ n: Int, from date: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Only perishable proteins (`Ingredient.isPerishableProtein`) are subject
    /// to the 2-day flag — shelf-stable pantry items (rice, oil, canned goods)
    /// never expire in this model.
    public static func isExpired(item: FridgeItem, ingredient: Ingredient, asOf: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        guard ingredient.isPerishableProtein else { return false }
        return ageInDays(addedDate: item.addedDate, asOf: asOf, calendar: calendar) > maxAgeDays
    }
}

/// Read-only view over the fridge, used by the substitution engine's
/// "replace with something I have" mode and the variant-fit fallback.
public struct FridgeInventory: Sendable {
    public let items: [FridgeItem]

    public init(items: [FridgeItem]) { self.items = items }

    public func quantity(of ingredientID: String) -> Double {
        items.first { $0.ingredientID == ingredientID }?.quantityGrams ?? 0
    }

    public func hasEnough(ingredientID: String, grams: Double) -> Bool {
        quantity(of: ingredientID) >= grams
    }

    /// Ingredients that are both in stock and not expired — the only ones
    /// safe to offer as substitutes or to count toward a variant's fridge fit.
    public func freshIngredients(database: IngredientDatabase, asOf: Date = Date()) -> [Ingredient] {
        items.compactMap { item in
            guard let ing = database.ingredient(id: item.ingredientID), item.quantityGrams > 0 else { return nil }
            return FridgeExpiry.isExpired(item: item, ingredient: ing, asOf: asOf) ? nil : ing
        }
    }
}
