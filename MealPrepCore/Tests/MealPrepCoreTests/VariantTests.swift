import Testing
@testable import MealPrepCore

@Suite("Trainer day-variants")
struct VariantTests {

    func db() throws -> IngredientDatabase { try IngredientDatabase.loadBundled() }
    func variants() throws -> VariantLibrary { try VariantLibrary.loadBundled() }
    func portioner() throws -> VariantPortioner {
        VariantPortioner(calculator: PortionCalculator(database: try db()))
    }

    @Test func loadsFourVariantsEachWithFourMeals() throws {
        let lib = try variants()
        #expect(lib.count == 4)
        #expect(Set(lib.all.map(\.id)) == ["V1", "V2", "V3", "V4"])
        for v in lib.all { #expect(v.meals.count == 4) }
    }

    @Test func everyVariantIngredientExistsInDatabase() throws {
        let database = try db()
        for v in try variants().all {
            for meal in v.meals {
                #expect(!meal.lines.isEmpty)
                for line in meal.lines {
                    #expect(database.ingredient(id: line.ingredientID) != nil,
                            "\(meal.id) references missing '\(line.ingredientID)'")
                }
            }
        }
    }

    @Test func batchSafeTaggingMatchesTrainerRule() throws {
        // Rule 5: exactly these meals are batch-safe.
        let expected: Set<String> = ["v1-m2", "v1-m4", "v2-m4", "v3-m2", "v3-m4", "v4-m2", "v4-m4"]
        let actual = Set(try variants().all.flatMap(\.meals).filter(\.batchSafe).map(\.id))
        #expect(actual == expected)
        // Breakfasts and assembly snacks/wraps are fresh-only.
        let fresh = Set(try variants().all.flatMap(\.meals).filter(\.freshOnly).map(\.id))
        #expect(fresh.contains("v1-m1"))   // breakfast
        #expect(fresh.contains("v2-m2"))   // wraps
        #expect(fresh.contains("v2-m3"))   // pudding snack
    }

    @Test func variantDailyTotalsAreNearTrainerEstimates() throws {
        // With the trainer's own ingredient values, each day should land close to
        // the document's stated totals (which the app recalculates from the DB).
        let stated: [String: Double] = ["V1": 2260, "V2": 2010, "V3": 2170, "V4": 2060]
        let p = try portioner()
        for v in try variants().all {
            let kcal = try p.dayMacros(for: v).kcal
            let target = stated[v.id]!
            #expect(abs(kcal - target) / target <= 0.10,
                    "\(v.id) daily \(kcal) kcal vs stated \(target)")
        }
    }

    @Test func husbandMultiplierSkipsPieceItems() throws {
        let p = try portioner()
        let v2 = try #require(try variants().variant(id: "V2"))
        // v2-m3 is protein pudding (piece) + apple (piece) — husband eats the same.
        let pudding = try #require(v2.meals.first { $0.id == "v2-m3" })
        let her = try p.macros(for: pudding, multiplier: 1.0)
        let him = try p.macros(for: pudding, multiplier: 1.4)
        expectClose(her.kcal, him.kcal, 1e-6)   // unchanged for the husband

        // v2-m4 is all weighed — husband scales exactly 1.4×.
        let turkeyRice = try #require(v2.meals.first { $0.id == "v2-m4" })
        let herM4 = try p.macros(for: turkeyRice, multiplier: 1.0)
        let himM4 = try p.macros(for: turkeyRice, multiplier: 1.4)
        expectClose(himM4.protein, herM4.protein * 1.4, 1e-6)
        expectClose(himM4.kcal, herM4.kcal * 1.4, 1e-6)
    }

    @Test func chickenToTurkeyIsEqualProteinSwap() throws {
        let database = try db()
        let engine = SubstitutionEngine(database: database)
        let chicken = try #require(database.ingredient(id: "chicken-breast"))
        let turkey = try #require(database.ingredient(id: "turkey-breast"))
        let grams = engine.equalProteinGrams(from: chicken, to: turkey, grams: 170)
        // Protein delivered must match.
        expectClose(chicken.macros(forGrams: 170).protein,
                    turkey.macros(forGrams: grams).protein, 1e-6)
    }
}
