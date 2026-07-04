import Testing
@testable import MealPrepCore

@Suite("Restock planner: affected meals & variant fallback")
struct RestockPlannerTests {

    func makeWeek(startIndex: Int = 0) throws -> VariantWeek {
        let db = try IngredientDatabase.loadBundled()
        let lib = try VariantLibrary.loadBundled()
        let port = VariantPortioner(calculator: PortionCalculator(database: db))
        let planner = VariantRotationPlanner(library: lib, portioner: port)
        return try planner.plan(gymThursday: false, startIndex: startIndex)
    }

    @Test func affectedMealsFindsEveryTemplateUsingTheIngredient() throws {
        let week = try makeWeek()
        // chicken-breast is used by v1-m2 (Chicken pasta) and v4-m4 (Chicken & sweet potato).
        let affected = RestockPlanner.affectedMeals(missingIngredientID: "chicken-breast", in: week)
        let ids = Set(affected.map(\.id))
        #expect(ids.contains("v1-m2"))
        #expect(ids.contains("v4-m4"))
    }

    @Test func affectedMealsDedupesRepeatedRotationDays() throws {
        // With startIndex 0, V1 lands on both Monday (day0) and Friday (day4) — a
        // single AffectedMeal entry should list both days, not appear twice.
        let week = try makeWeek(startIndex: 0)
        let affected = RestockPlanner.affectedMeals(missingIngredientID: "chicken-breast", in: week)
        let v1m2 = try #require(affected.first { $0.id == "v1-m2" })
        #expect(v1m2.dayOffsets == [0, 4])
    }

    @Test func affectedMealsIsEmptyForUnusedIngredient() throws {
        let week = try makeWeek()
        #expect(RestockPlanner.affectedMeals(missingIngredientID: "not-a-real-ingredient", in: week).isEmpty)
    }

    // MARK: - Variant fallback

    func fullVariantLibrary() throws -> [DayVariant] { try VariantLibrary.loadBundled().all }

    @Test func fullFridgeScoresEveryVariantAtOne() throws {
        let variants = try fullVariantLibrary()
        // Build a fridge with generous quantities of everything referenced.
        let allLines = variants.flatMap { $0.meals.flatMap(\.lines) }
        let items = Dictionary(grouping: allLines, by: \.ingredientID).map { id, lines in
            FridgeItem(ingredientID: id, quantityGrams: (lines.map(\.baseRawGrams).max() ?? 0) * 10,
                      addedDate: FridgeExpiry.daysAgo(0))
        }
        let scores = VariantFallback.scoreVariants(variants, against: FridgeInventory(items: items))
        for s in scores { expectClose(s.fitFraction, 1.0, 1e-9) }
    }

    @Test func emptyFridgeScoresEveryVariantAtZero() throws {
        let variants = try fullVariantLibrary()
        let scores = VariantFallback.scoreVariants(variants, against: FridgeInventory(items: []))
        for s in scores { expectClose(s.fitFraction, 0.0, 1e-9) }
    }

    @Test func suggestAlternativeOnlyWhenMeaningfullyBetter() throws {
        let variants = try fullVariantLibrary()
        // Fridge stocked ONLY for V2's ingredients, generously.
        guard let v2 = variants.first(where: { $0.id == "V2" }) else {
            Issue.record("V2 missing from bundled variants")
            return
        }
        let items = Dictionary(grouping: v2.meals.flatMap(\.lines), by: \.ingredientID).map { id, lines in
            FridgeItem(ingredientID: id, quantityGrams: (lines.map(\.baseRawGrams).max() ?? 0) * 10, addedDate: FridgeExpiry.daysAgo(0))
        }
        let fridge = FridgeInventory(items: items)

        // Asking "should I switch away from V1 (poorly stocked)?" should suggest V2.
        let suggestion = VariantFallback.suggestAlternative(to: "V1", among: variants, fridge: fridge)
        #expect(suggestion?.variantID == "V2")

        // Asking "should I switch away from V2 itself?" should find nothing better.
        let noSuggestion = VariantFallback.suggestAlternative(to: "V2", among: variants, fridge: fridge)
        #expect(noSuggestion == nil)
    }

    @Test func suggestAlternativeNeverProposesARetiredVariant() throws {
        let variants = try fullVariantLibrary()
        // Fridge stocked only for V2 — but V2 is retired.
        guard let v2 = variants.first(where: { $0.id == "V2" }) else {
            Issue.record("V2 missing from bundled variants")
            return
        }
        let retired = variants.map { v in
            v.id == "V2" ? DayVariant(id: v.id, name: v.name, meals: v.meals, isActive: false) : v
        }
        let items = Dictionary(grouping: v2.meals.flatMap(\.lines), by: \.ingredientID).map { id, lines in
            FridgeItem(ingredientID: id, quantityGrams: (lines.map(\.baseRawGrams).max() ?? 0) * 10, addedDate: FridgeExpiry.daysAgo(0))
        }
        let fridge = FridgeInventory(items: items)
        let suggestion = VariantFallback.suggestAlternative(to: "V1", among: retired, fridge: fridge)
        #expect(suggestion?.variantID != "V2")
    }
}
