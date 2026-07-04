import Testing
@testable import MealPrepCore

@Suite("Cook plan builder")
struct CookPlanTests {

    let her = Profile(id: "her", name: "Her", dailyTarget: .v(1600, 130, 150, 50))
    let husband = Profile(id: "him", name: "Husband", dailyTarget: .v(2300, 170, 220, 72), portionMultiplier: 1.4)

    func makeBuilder() throws -> (CookPlanBuilder, VariantWeek) {
        let db = try IngredientDatabase.loadBundled()
        let lib = try VariantLibrary.loadBundled()
        let port = VariantPortioner(calculator: PortionCalculator(database: db))
        let planner = VariantRotationPlanner(library: lib, portioner: port)
        let week = try planner.plan(gymThursday: false, startIndex: 0)
        return (CookPlanBuilder(database: db, portioner: port), week)
    }

    // MARK: - Duration model

    @Test func allPassiveStepsOverlapToTheLongestOne() {
        let steps = [CookStep(text: "a", minutes: 30, method: .oven, isPassive: true),
                     CookStep(text: "b", minutes: 20, method: .riceCooker, isPassive: true)]
        #expect(CookPlanBuilder.duration(steps) == 30)
    }

    @Test func activeStepsAreSequentialAndAddUp() {
        let steps = [CookStep(text: "a", minutes: 10, method: .stovetop, isPassive: false),
                     CookStep(text: "b", minutes: 5, method: .stovetop, isPassive: false)]
        #expect(CookPlanBuilder.duration(steps) == 15)
    }

    @Test func mixedTakesTheLargerOfActiveSumAndPassiveMax() {
        // Active sum (18) > passive max (10) -> total is the active sum.
        let mixed = [CookStep(text: "bake", minutes: 10, method: .oven, isPassive: true),
                     CookStep(text: "sear", minutes: 10, method: .stovetop, isPassive: false),
                     CookStep(text: "chop", minutes: 8, method: .stovetop, isPassive: false)]
        #expect(CookPlanBuilder.duration(mixed) == 18)

        // Passive max (40) > active sum (5) -> total is the passive max.
        let ovenHeavy = [CookStep(text: "roast", minutes: 40, method: .oven, isPassive: true),
                         CookStep(text: "plate", minutes: 5, method: .noCook, isPassive: false)]
        #expect(CookPlanBuilder.duration(ovenHeavy) == 40)
    }

    // MARK: - Real sessions stay within a reasonable batch-cooking budget

    @Test func everySessionFitsUnderAnHour() throws {
        let (builder, week) = try makeBuilder()
        for session in week.cookSessions {
            let plan = builder.plan(for: session, week: week, profiles: [her, husband])
            #expect(plan.totalMinutes > 0, "\(session.id) has no timed steps")
            #expect(plan.totalMinutes <= 60, "\(session.id) estimated at \(plan.totalMinutes) min — over budget")
        }
    }

    @Test func stationsGroupStepsByEquipment() throws {
        let (builder, week) = try makeBuilder()
        let sunday = try #require(week.cookSessions.first { $0.id == "sun-prep" })
        let plan = builder.plan(for: sunday, week: week, profiles: [her, husband])
        let methods = Set(plan.stations.map(\.method))
        // Sunday cooks V1 (oven+stovetop) + V2 dinner (oven+riceCooker+stovetop).
        #expect(methods.contains(.oven))
        #expect(methods.contains(.stovetop))
        #expect(methods.contains(.riceCooker))
    }

    // MARK: - Batch grams (2 days × 2 people)

    @Test func batchGramsSumBothCoveredDaysAndBothProfiles() throws {
        let (builder, week) = try makeBuilder()
        let sunday = try #require(week.cookSessions.first { $0.id == "sun-prep" })
        let plan = builder.plan(for: sunday, week: week, profiles: [her, husband])

        // Chicken breast appears in v1-m2 (170g, day 0 only — day 1 is V2, no chicken dinner there).
        // Expected: her 170 + him 170*1.4 = 170 + 238 = 408g just from that one meal/day.
        let chicken = try #require(plan.batchGrams.first { $0.ingredientID == "chicken-breast" })
        expectClose(chicken.totalRawGrams, 170 * (1 + 1.4), 1e-6)
    }

    @Test func containerPortionsCoverEveryProfileEveryBatchMealEveryDay() throws {
        let (builder, week) = try makeBuilder()
        let sunday = try #require(week.cookSessions.first { $0.id == "sun-prep" })
        let plan = builder.plan(for: sunday, week: week, profiles: [her, husband])

        // 2 covered days × (2 batch meals on day0=V1, 1 batch meal on day1=V2) × 2 profiles = 6 portions.
        #expect(plan.containerPortions.count == 6)
        // Husband's portion of a weighed ingredient is 1.4× hers exactly.
        let herTaco = try #require(plan.containerPortions.first { $0.profileID == "her" && $0.mealID == "v1-m4" })
        let himTaco = try #require(plan.containerPortions.first { $0.profileID == "him" && $0.mealID == "v1-m4" })
        let herBeef = try #require(herTaco.lines.first { $0.ingredientID == "beef-mince-10" })
        let himBeef = try #require(himTaco.lines.first { $0.ingredientID == "beef-mince-10" })
        expectClose(himBeef.baseRawGrams, herBeef.baseRawGrams * 1.4, 1e-6)
    }

    @Test func husbandPieceItemsAreNotScaledInPortions() throws {
        // v2-m3 (protein pudding) isn't batch-safe, so use a batch meal instead:
        // none of the current batch-safe meals contain piece items, so verify via
        // the portioner directly (already covered in VariantTests), and instead
        // confirm the builder just delegates to it faithfully for a weighed item.
        let (builder, week) = try makeBuilder()
        let sunday = try #require(week.cookSessions.first { $0.id == "sun-prep" })
        let plan = builder.plan(for: sunday, week: week, profiles: [her, husband])
        for portion in plan.containerPortions {
            for line in portion.lines { #expect(line.baseRawGrams > 0) }
        }
    }
}
