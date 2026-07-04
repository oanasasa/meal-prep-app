import Testing
@testable import MealPrepCore

@Suite("Recipe library")
struct RecipeLibraryTests {

    func lib() throws -> RecipeLibrary { try RecipeLibrary.loadBundled() }
    func db() throws -> IngredientDatabase { try IngredientDatabase.loadBundled() }

    @Test func bundledRecipesLoadWithUniqueIDs() throws {
        let ids = try lib().all.map(\.id)
        #expect(ids.count >= 12)
        #expect(ids.count == Set(ids).count)
    }

    @Test func everyRecipeIngredientExistsInDatabase() throws {
        let library = try lib()
        let database = try db()
        for recipe in library.all {
            #expect(!recipe.lines.isEmpty, "\(recipe.id) has no ingredients")
            for line in recipe.lines {
                #expect(database.ingredient(id: line.ingredientID) != nil,
                        "\(recipe.id) references missing ingredient '\(line.ingredientID)'")
                #expect(line.baseRawGrams > 0, "\(recipe.id) has non-positive grams")
            }
        }
    }

    @Test func coverageForEverySlotType() throws {
        let library = try lib()
        // Lunch & dinner need batch-safe options and tired-day options.
        for type in [MealType.lunch, .dinner] {
            let forType = library.recipes(for: type)
            #expect(forType.contains { $0.batchSafe2Days }, "no batch-safe \(type)")
            #expect(forType.contains { $0.tiredDay }, "no tired-day \(type)")
        }
        // At least one husband-compromise dinner and one breakfast/snack.
        #expect(library.recipes(for: .dinner).contains { $0.husbandCompromise })
        #expect(!library.recipes(for: .breakfast).isEmpty)
        #expect(!library.recipes(for: .snack).isEmpty)
    }

    @Test func noCookRecipesAreTaggedNoCook() throws {
        for r in try lib().all where r.tiredDay {
            // Tired-day meals should be genuinely low effort.
            #expect(r.prepMinutes <= 12, "\(r.id) tagged tiredDay but prep \(r.prepMinutes) min")
        }
    }
}
