import Testing
@testable import MealPrepCore

@Suite("Portion & cooked/raw math")
struct PortionTests {

    let db = IngredientDatabase(ingredients: [
        Ingredient(id: "chicken-breast", name: "Chicken breast", section: .meatAndSeafood,
                   group: .leanProtein, per100g: .v(165, 31, 0, 3.6),
                   cookedYieldFactor: 0.72, isPerishableProtein: true),
        Ingredient(id: "white-rice-dry", name: "White rice, dry", section: .grainsAndBakery,
                   group: .starchyCarb, per100g: .v(360, 7, 79, 0.9),
                   cookedYieldFactor: 2.7)
    ])

    let her = Profile(id: "her", name: "Her",
                      dailyTarget: .v(1600, 130, 150, 50), portionMultiplier: 1.0)
    let husband = Profile(id: "him", name: "Husband",
                          dailyTarget: .v(2400, 180, 240, 75), portionMultiplier: 1.4)

    var recipe: [RecipeLine] {
        [RecipeLine(ingredientID: "chicken-breast", baseRawGrams: 150),
         RecipeLine(ingredientID: "white-rice-dry", baseRawGrams: 75)]
    }

    @Test func macrosForGrams() {
        let m = db.ingredient(id: "chicken-breast")!.macros(forGrams: 150)
        expectClose(m.kcal, 247.5)
        expectClose(m.protein, 46.5)
        expectClose(m.fat, 5.4)
    }

    @Test func cookedRawWeights() {
        // Chicken loses water: 150g raw -> 108g cooked.
        expectClose(db.ingredient(id: "chicken-breast")!.cookedGrams(forRawGrams: 150), 108)
        // Rice absorbs water: 75g dry -> 202.5g cooked.
        expectClose(db.ingredient(id: "white-rice-dry")!.cookedGrams(forRawGrams: 75), 202.5)
    }

    @Test func portionMultiplierScalesHusband() throws {
        let calc = PortionCalculator(database: db)
        let herLines = try calc.portionedLines(for: recipe, profile: her)
        let himLines = try calc.portionedLines(for: recipe, profile: husband)

        expectClose(herLines[0].rawGrams, 150)
        expectClose(himLines[0].rawGrams, 210) // 150 * 1.4

        let herTotal = try calc.totalMacros(for: recipe, profile: her)
        let himTotal = try calc.totalMacros(for: recipe, profile: husband)
        expectClose(himTotal.protein, herTotal.protein * 1.4, 1e-6)
        expectClose(himTotal.kcal, herTotal.kcal * 1.4, 1e-6)
    }

    @Test func batchRawGramsForTwoDaysTwoPeople() throws {
        let calc = PortionCalculator(database: db)
        let chickenOnly = [RecipeLine(ingredientID: "chicken-breast", baseRawGrams: 150)]
        // 2 days x (her 150 + him 210) = 720g raw chicken.
        let batch = try calc.batchRawGrams(for: chickenOnly, profiles: [her, husband], days: 2)
        expectClose(batch["chicken-breast"]!, 720)
    }

    @Test func unknownIngredientThrows() {
        let calc = PortionCalculator(database: db)
        let bad = [RecipeLine(ingredientID: "does-not-exist", baseRawGrams: 100)]
        #expect(throws: MealPrepError.unknownIngredient("does-not-exist")) {
            try calc.totalMacros(for: bad, profile: her)
        }
    }
}
