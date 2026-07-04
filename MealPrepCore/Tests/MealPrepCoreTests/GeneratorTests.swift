import Testing
@testable import MealPrepCore

// Note: no `import Foundation` here on purpose — under Command Line Tools,
// importing Foundation alongside Testing pulls in the unavailable
// `_Testing_Foundation` overlay. `Date` is supplied by the generator's default
// argument, so tests never name it.
@Suite("Weekly plan generator")
struct GeneratorTests {

    func makeGenerator() throws -> WeeklyPlanGenerator {
        let db = try IngredientDatabase.loadBundled()
        let lib = try RecipeLibrary.loadBundled()
        return WeeklyPlanGenerator(library: lib, calculator: PortionCalculator(database: db))
    }

    let plan = TrainerPlan.defaultSplit(daily: .v(1600, 130, 150, 50), mealsPerDay: 4)

    @Test func generatesFullWeek() throws {
        let week = try makeGenerator().generate(plan: plan, gymThursday: false)
        #expect(week.meals.count == 7 * plan.mealsPerDay)
        // Every recipe id resolves.
        let lib = try RecipeLibrary.loadBundled()
        for m in week.meals { #expect(lib.recipe(id: m.recipeID) != nil) }
    }

    @Test func deterministicForSameSeed() throws {
        let g = try makeGenerator()
        let a = try g.generate(plan: plan, gymThursday: false, seed: 7)
        let b = try g.generate(plan: plan, gymThursday: false, seed: 7)
        #expect(a.meals == b.meals)
    }

    @Test func cookedMealsAreBatchSafeAndAssignedToASession() throws {
        let g = try makeGenerator()
        let lib = try RecipeLibrary.loadBundled()
        let week = try g.generate(plan: plan, gymThursday: false)

        for m in week.meals where m.mealType.isBatchCooked && m.dayOffset != CookScheduler.tiredDayOffset {
            let r = lib.recipe(id: m.recipeID)!
            #expect(r.batchSafe2Days, "\(r.id) on day \(m.dayOffset) isn't batch-safe")
            #expect(m.cookSessionID != nil, "cooked meal has no session")
            // The session it's assigned to actually covers that day.
            let session = week.cookSessions.first { $0.id == m.cookSessionID }
            #expect(session?.coversDayOffsets.contains(m.dayOffset) == true)
        }
    }

    @Test func sundayIsTheTiredDayWithNoCooking() throws {
        let g = try makeGenerator()
        let lib = try RecipeLibrary.loadBundled()
        let week = try g.generate(plan: plan, gymThursday: false)
        for m in week.meals(onDay: CookScheduler.tiredDayOffset) where m.mealType.isBatchCooked {
            let r = lib.recipe(id: m.recipeID)!
            #expect(r.tiredDay, "Sunday \(m.mealType) '\(r.id)' isn't a tired-day recipe")
            #expect(m.cookSessionID == nil, "Sunday meal shouldn't be batch-cooked")
        }
    }

    @Test func freshDailyMealsHaveNoSession() throws {
        let week = try makeGenerator().generate(plan: plan, gymThursday: false)
        for m in week.meals where !m.mealType.isBatchCooked {
            #expect(m.cookSessionID == nil)
        }
    }

    @Test func husbandCompromiseAppearsOnDesignatedDinners() throws {
        let g = try makeGenerator()
        let lib = try RecipeLibrary.loadBundled()
        let week = try g.generate(plan: plan, gymThursday: false)
        // Wednesday (2) and Saturday (5) dinners should be husband-compromise.
        for day in [2, 5] {
            let dinner = week.meals(onDay: day).first { $0.mealType == .dinner }
            let r = try #require(dinner.flatMap { lib.recipe(id: $0.recipeID) })
            #expect(r.husbandCompromise, "day \(day) dinner '\(r.id)' isn't a husband compromise")
        }
    }

    @Test func husbandCompromiseIsLimitedToDesignatedSlots() throws {
        let g = try makeGenerator()
        let lib = try RecipeLibrary.loadBundled()
        let week = try g.generate(plan: plan, gymThursday: false)
        let husbandMeals = week.meals.filter { lib.recipe(id: $0.recipeID)?.husbandCompromise == true }
        // Reserved for Wednesday + Saturday dinners — exactly twice a week.
        #expect(husbandMeals.count == 2)
        #expect(Set(husbandMeals.map(\.dayOffset)) == [2, 5])
        #expect(husbandMeals.allSatisfy { $0.mealType == .dinner })
    }

    @Test func proteinIsMatchedForMainMeals() throws {
        let week = try makeGenerator().generate(plan: plan, gymThursday: false)
        // Protein-anchored scaling should hit protein almost exactly on mains.
        for m in week.meals where m.mealType.isBatchCooked {
            #expect(abs(m.delta.fractional.protein) <= 0.03,
                    "\(m.recipeID) protein off by \(m.delta.fractional.protein)")
        }
    }

    @Test func gymThursdayReschedulesThirdSession() throws {
        let g = try makeGenerator()
        let week = try g.generate(plan: plan, gymThursday: true)
        #expect(week.cookSessions[2].id == "fri")
        // Friday & Saturday meals point at the Friday session.
        for day in [4, 5] {
            for m in week.meals(onDay: day) where m.mealType.isBatchCooked {
                #expect(m.cookSessionID == "fri")
            }
        }
    }
}
