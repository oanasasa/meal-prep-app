import Testing
@testable import MealPrepCore

@Suite("Bundled ingredient database")
struct DatabaseTests {

    func loadDB() throws -> IngredientDatabase { try IngredientDatabase.loadBundled() }

    @Test func bundledSeedLoads() throws {
        #expect(try loadDB().count >= 100)
    }

    @Test func idsAreUnique() throws {
        let ids = try loadDB().all.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test func everySubstitutionSourceGroupHasAlternatives() throws {
        let db = try loadDB()
        let sourceGroups: [SubstitutionGroup] = [
            .leanProtein, .oilyFish, .redMeat, .eggs, .dairyProtein, .cheese,
            .plantProtein, .legume, .starchyCarb, .healthyFat, .vegetable, .fruit
        ]
        for group in sourceGroups {
            #expect(db.ingredients(in: group).count >= 2,
                    "Group \(group) needs ≥2 members to substitute within")
        }
    }

    @Test func macrosArePlausible() throws {
        for ing in try loadDB().all {
            let m = ing.per100g
            #expect(m.protein >= 0, "\(ing.id) negative protein")
            #expect(m.carbs >= 0, "\(ing.id) negative carbs")
            #expect(m.fat >= 0, "\(ing.id) negative fat")
            #expect(m.kcal >= 0, "\(ing.id) negative kcal")
            #expect(m.kcal <= 902, "\(ing.id) kcal exceeds physical max")
            #expect(m.protein + m.carbs + m.fat <= 101, "\(ing.id) mass > 100 g")
        }
    }

    @Test func declaredKcalRoughlyMatchesAtwater() throws {
        // Fibre, sugar alcohols and rounding justify a loose band: 20% or 25 kcal.
        // Spices/condiments (e.g. cinnamon) are mostly indigestible fibre whose
        // label kcal legitimately falls far below 4/4/9 — skip that group.
        for ing in try loadDB().all where ing.group != .condiment {
            let declared = ing.per100g.kcal
            let atwater = ing.per100g.atwaterKcal
            let absOK = abs(declared - atwater) <= 25
            let relOK = atwater > 0 && abs(declared - atwater) / atwater <= 0.20
            #expect(absOK || relOK,
                    "\(ing.id): declared \(declared) vs Atwater \(atwater)")
        }
    }

    @Test func pieceIngredientsHaveGramsPerPiece() throws {
        for ing in try loadDB().all where ing.unit == .piece {
            #expect(ing.gramsPerPiece != nil, "\(ing.id) sold by piece but no gramsPerPiece")
        }
    }
}
