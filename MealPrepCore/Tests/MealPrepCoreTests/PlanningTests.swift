import Testing
@testable import MealPrepCore

@Suite("Trainer plan split")
struct PlanningTests {

    let daily = MacroVector.v(1600, 130, 150, 50)

    @Test func splitNormalisesFractionsAndSumsToDaily() {
        let plan = TrainerPlan.split(daily: daily,
                                     mealTypes: [.breakfast, .lunch, .dinner],
                                     fractions: [2, 3, 3])   // not normalised
        #expect(plan.mealsPerDay == 3)
        let sum = MacroVector.sum(plan.mealTargets)
        expectClose(sum.kcal, daily.kcal, 1e-6)
        expectClose(sum.protein, daily.protein, 1e-6)
        // 2:3:3 → breakfast is 25% of kcal.
        expectClose(plan.mealTargets[0].kcal, daily.kcal * 0.25, 1e-6)
    }

    @Test func defaultSplitsSumToDaily() {
        for n in [3, 4, 5] {
            let plan = TrainerPlan.defaultSplit(daily: daily, mealsPerDay: n)
            #expect(plan.mealsPerDay == n)
            let sum = MacroVector.sum(plan.mealTargets)
            expectClose(sum.kcal, daily.kcal, 1e-6)
            expectClose(sum.protein, daily.protein, 1e-6)
            expectClose(sum.carbs, daily.carbs, 1e-6)
            expectClose(sum.fat, daily.fat, 1e-6)
        }
    }

    @Test func mealTypesAlignWithTargets() {
        let plan = TrainerPlan.defaultSplit(daily: daily, mealsPerDay: 4)
        #expect(plan.mealTypes.count == plan.mealTargets.count)
        #expect(plan.mealTypes.contains(.dinner))
        #expect(plan.mealTypes.contains(.breakfast))
    }
}
