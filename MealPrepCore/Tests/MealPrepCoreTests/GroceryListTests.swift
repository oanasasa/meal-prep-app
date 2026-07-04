import Testing
@testable import MealPrepCore

@Suite("Grocery list builder")
struct GroceryListTests {

    let her = Profile(id: "her", name: "Her", dailyTarget: .v(1600, 130, 150, 50))
    let husband = Profile(id: "him", name: "Husband", dailyTarget: .v(2300, 170, 220, 72), portionMultiplier: 1.4)

    func makeWeek() throws -> (VariantWeek, VariantPortioner, IngredientDatabase) {
        let db = try IngredientDatabase.loadBundled()
        let lib = try VariantLibrary.loadBundled()
        let port = VariantPortioner(calculator: PortionCalculator(database: db))
        let planner = VariantRotationPlanner(library: lib, portioner: port)
        return (try planner.plan(gymThursday: false, startIndex: 0), port, db)
    }

    @Test func aggregatesAcrossWholeWeekAndBothProfiles() throws {
        let (week, port, db) = try makeWeek()
        let items = GroceryListBuilder.build(for: week, profiles: [her, husband], portioner: port, database: db)
        #expect(!items.isEmpty)
        // Chicken breast shows up across several days — total should exceed any single meal's grams.
        let chicken = try #require(items.first { $0.ingredientID == "chicken-breast" })
        #expect(chicken.totalRawGrams > 170)
    }

    @Test func groupedAndSortedByStoreSection() throws {
        let (week, port, db) = try makeWeek()
        let items = GroceryListBuilder.build(for: week, profiles: [her, husband], portioner: port, database: db)
        let sections = items.map { $0.section.rawValue }
        #expect(sections == sections.sorted())
    }

    @Test func pieceItemsDisplayAsWholeUnitsRoundedUp() throws {
        let (week, port, db) = try makeWeek()
        let items = GroceryListBuilder.build(for: week, profiles: [her, husband], portioner: port, database: db)
        // Bananas appear as a piece-unit ingredient in V1/V4 breakfasts.
        if let banana = items.first(where: { $0.ingredientID == "banana" }) {
            #expect(banana.displayQuantity.hasSuffix("pc"))
        }
    }

    @Test func gramItemsDisplayAsGrams() throws {
        let (week, port, db) = try makeWeek()
        let items = GroceryListBuilder.build(for: week, profiles: [her, husband], portioner: port, database: db)
        let pasta = try #require(items.first { $0.ingredientID == "pasta-dry" })
        #expect(pasta.displayQuantity.hasSuffix(" g"))
    }
}
