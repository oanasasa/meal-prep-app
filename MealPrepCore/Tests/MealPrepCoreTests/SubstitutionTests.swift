import Testing
@testable import MealPrepCore

@Suite("Substitution engine")
struct SubstitutionTests {

    // A focused DB: one meal's ingredients, lean-protein swaps, and one
    // deliberately ultra-processed item to prove it's never suggested.
    let db = IngredientDatabase(ingredients: [
        Ingredient(id: "chicken-breast", name: "Chicken breast", section: .meatAndSeafood,
                   group: .leanProtein, per100g: .v(165, 31, 0, 3.6),
                   cookedYieldFactor: 0.72, isPerishableProtein: true),
        Ingredient(id: "turkey-breast", name: "Turkey breast", section: .meatAndSeafood,
                   group: .leanProtein, per100g: .v(135, 29, 0, 1),
                   cookedYieldFactor: 0.72, isPerishableProtein: true),
        Ingredient(id: "cod", name: "Cod", section: .meatAndSeafood,
                   group: .leanProtein, per100g: .v(82, 18, 0, 0.7),
                   cookedYieldFactor: 0.82, isPerishableProtein: true),
        Ingredient(id: "shrimp", name: "Shrimp", section: .meatAndSeafood,
                   group: .leanProtein, per100g: .v(99, 24, 0.2, 0.3),
                   cookedYieldFactor: 0.85, isPerishableProtein: true),
        Ingredient(id: "pork-loin", name: "Pork loin", section: .meatAndSeafood,
                   group: .leanProtein, per100g: .v(143, 26, 0, 3.5),
                   cookedYieldFactor: 0.74, isPerishableProtein: true),
        // Ultra-processed: must never be suggested.
        Ingredient(id: "breaded-nuggets", name: "Breaded chicken nuggets", section: .frozen,
                   group: .leanProtein, per100g: .v(250, 14, 15, 16),
                   isWholeFood: false, isPerishableProtein: true),
        // Rest of the plate.
        Ingredient(id: "white-rice-dry", name: "White rice", section: .grainsAndBakery,
                   group: .starchyCarb, per100g: .v(360, 7, 79, 0.9), cookedYieldFactor: 2.7),
        Ingredient(id: "broccoli", name: "Broccoli", section: .produce,
                   group: .vegetable, per100g: .v(34, 2.8, 7, 0.4)),
        Ingredient(id: "olive-oil", name: "Olive oil", section: .pantry,
                   group: .healthyFat, per100g: .v(884, 0, 0, 100), unit: .milliliter),
        // For the "from my fridge" cross-group test.
        Ingredient(id: "greek-yogurt-0", name: "Greek yogurt 0%", section: .dairyAndEggs,
                   group: .dairyProtein, per100g: .v(59, 10, 3.6, 0.4), isPerishableProtein: true)
    ])

    let meal = [
        RecipeLine(ingredientID: "chicken-breast", baseRawGrams: 150),
        RecipeLine(ingredientID: "white-rice-dry", baseRawGrams: 75),
        RecipeLine(ingredientID: "broccoli", baseRawGrams: 100),
        RecipeLine(ingredientID: "olive-oil", baseRawGrams: 10)
    ]

    var engine: SubstitutionEngine { SubstitutionEngine(database: db) }

    // MARK: - The 1-D solver in isolation

    @Test func solverHitsCollinearNeedExactly() {
        // Pure-protein "ingredient" (100 g protein / 100 g). Need of 30 g protein
        // must be met by exactly 30 g.
        let pureProtein = Ingredient(id: "x", name: "x", section: .pantry,
                                     group: .leanProtein, per100g: .v(400, 100, 0, 0))
        let grams = engine.solveGrams(substitute: pureProtein,
                                      need: .v(120, 30, 0, 0),
                                      target: .v(500, 40, 50, 15))
        expectClose(grams, 30, 1e-6)
    }

    @Test func solverNeverReturnsNegativeGrams() {
        let turkey = db.ingredient(id: "turkey-breast")!
        let grams = engine.solveGrams(substitute: turkey,
                                      need: .v(-100, -20, 0, -5),
                                      target: .v(500, 40, 50, 15))
        expectClose(grams, 0)
    }

    // MARK: - Suggestions

    @Test func suggestionsStayWithinFivePercent() throws {
        let suggestions = try engine.suggestions(forMissing: "chicken-breast", in: meal)
        let best = try #require(suggestions.first)
        #expect(best.withinTolerance)
        #expect(abs(best.delta.fractional.kcal) <= 0.05)
        #expect(abs(best.delta.fractional.protein) <= 0.05)
    }

    @Test func resultingMealIsRemainderPlusSubstitute() throws {
        let suggestions = try engine.suggestions(forMissing: "chicken-breast", in: meal)
        let remainder = db.ingredient(id: "white-rice-dry")!.macros(forGrams: 75)
            + db.ingredient(id: "broccoli")!.macros(forGrams: 100)
            + db.ingredient(id: "olive-oil")!.macros(forGrams: 10)
        for s in suggestions {
            let expected = remainder + s.substitute.macros(forGrams: s.grams)
            expectClose(s.resultingMeal.kcal, expected.kcal, 1e-6)
            expectClose(s.resultingMeal.protein, expected.protein, 1e-6)
        }
    }

    @Test func onlyWholeFoodSameGroupSuggested() throws {
        let suggestions = try engine.suggestions(forMissing: "chicken-breast", in: meal)
        let ids = suggestions.map(\.substitute.id)
        #expect(!ids.contains("breaded-nuggets"))  // ultra-processed excluded
        #expect(!ids.contains("chicken-breast"))   // the missing item excluded
        for s in suggestions {
            #expect(s.substitute.group == .leanProtein)
            #expect(s.substitute.isWholeFood)
        }
    }

    @Test func rankingPrefersInToleranceThenScore() throws {
        let suggestions = try engine.suggestions(forMissing: "chicken-breast", in: meal)
        let flags = suggestions.map(\.withinTolerance)
        let firstFalse = flags.firstIndex(of: false) ?? flags.count
        #expect(!flags[..<firstFalse].contains(false)) // all-true block first
        #expect(!flags[firstFalse...].contains(true))   // no true after a false
        let inTol = suggestions.filter(\.withinTolerance).map(\.score)
        #expect(inTol == inTol.sorted())                // score non-decreasing
    }

    @Test func limitCapsResults() throws {
        let three = try engine.suggestions(forMissing: "chicken-breast", in: meal, limit: 3)
        #expect(three.count <= 3)
    }

    @Test func replaceWithSomethingIHave() throws {
        // Fridge has only cod and greek yogurt — cross-group allowed here.
        let fridge = [db.ingredient(id: "cod")!, db.ingredient(id: "greek-yogurt-0")!]
        let suggestions = try engine.suggestions(forMissing: "chicken-breast",
                                                 in: meal, candidates: fridge)
        #expect(Set(suggestions.map(\.substitute.id)) == ["cod", "greek-yogurt-0"])
    }

    @Test func explicitTargetIsRespected() throws {
        // Higher-protein target should push the solver to more grams.
        let higherProtein = MacroVector.v(640, 65, 66, 16)
        let suggestions = try engine.suggestions(forMissing: "chicken-breast",
                                                 in: meal, target: higherProtein)
        let best = try #require(suggestions.first)
        #expect(best.resultingMeal.protein > 55)
    }

    @Test func missingIngredientNotInMealThrows() {
        #expect(throws: (any Error).self) {
            try engine.suggestions(forMissing: "cod", in: meal)
        }
    }
}
