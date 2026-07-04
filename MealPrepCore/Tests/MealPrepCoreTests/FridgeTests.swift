import Testing
@testable import MealPrepCore

// Note: no `import Foundation` here — under Command Line Tools, importing
// Foundation alongside Testing pulls in the unavailable `_Testing_Foundation`
// overlay (see GeneratorTests.swift). We never spell `Date`/`Calendar`
// ourselves; `FridgeExpiry.daysAgo` (which lives in MealPrepCore, which does
// import Foundation) does the date arithmetic and we just use its result via
// type inference.
@Suite("Fridge expiry & inventory")
struct FridgeTests {

    let chicken = Ingredient(id: "chicken-breast", name: "Chicken breast", section: .meatAndSeafood,
                             group: .leanProtein, per100g: .v(110, 23, 0, 1.5), isPerishableProtein: true)
    let rice = Ingredient(id: "white-rice-dry", name: "White rice", section: .grainsAndBakery,
                          group: .starchyCarb, per100g: .v(360, 7, 79, 0.6))

    @Test func exactlyTwoDaysOldIsNotYetExpired() {
        let item = FridgeItem(ingredientID: "chicken-breast", quantityGrams: 200, addedDate: FridgeExpiry.daysAgo(2))
        #expect(!FridgeExpiry.isExpired(item: item, ingredient: chicken, asOf: FridgeExpiry.daysAgo(0)))
    }

    @Test func threeDaysOldIsExpired() {
        let item = FridgeItem(ingredientID: "chicken-breast", quantityGrams: 200, addedDate: FridgeExpiry.daysAgo(3))
        #expect(FridgeExpiry.isExpired(item: item, ingredient: chicken, asOf: FridgeExpiry.daysAgo(0)))
    }

    @Test func nonPerishableNeverExpires() {
        let item = FridgeItem(ingredientID: "white-rice-dry", quantityGrams: 500, addedDate: FridgeExpiry.daysAgo(30))
        #expect(!FridgeExpiry.isExpired(item: item, ingredient: rice, asOf: FridgeExpiry.daysAgo(0)))
    }

    @Test func inventoryLookupsAndSufficiency() {
        let inv = FridgeInventory(items: [
            FridgeItem(ingredientID: "chicken-breast", quantityGrams: 150, addedDate: FridgeExpiry.daysAgo(0))
        ])
        #expect(inv.quantity(of: "chicken-breast") == 150)
        #expect(inv.quantity(of: "salmon") == 0)
        #expect(inv.hasEnough(ingredientID: "chicken-breast", grams: 100))
        #expect(!inv.hasEnough(ingredientID: "chicken-breast", grams: 200))
    }

    @Test func freshIngredientsExcludesExpiredAndEmpty() throws {
        let db = IngredientDatabase(ingredients: [chicken, rice])
        let inv = FridgeInventory(items: [
            FridgeItem(ingredientID: "chicken-breast", quantityGrams: 150, addedDate: FridgeExpiry.daysAgo(5)),
            FridgeItem(ingredientID: "white-rice-dry", quantityGrams: 0, addedDate: FridgeExpiry.daysAgo(0))
        ])
        #expect(inv.freshIngredients(database: db).isEmpty)

        let inv2 = FridgeInventory(items: [
            FridgeItem(ingredientID: "chicken-breast", quantityGrams: 150, addedDate: FridgeExpiry.daysAgo(0)),
            FridgeItem(ingredientID: "white-rice-dry", quantityGrams: 300, addedDate: FridgeExpiry.daysAgo(0))
        ])
        let fresh = inv2.freshIngredients(database: db)
        let freshIDs: Set<String> = Set(fresh.map { $0.id })
        #expect(freshIDs == ["chicken-breast", "white-rice-dry"])
    }
}
