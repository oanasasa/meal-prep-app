import Testing
@testable import MealPrepCore

@Suite("Variant rotation planner")
struct RotationTests {

    func planner() throws -> VariantRotationPlanner {
        let db = try IngredientDatabase.loadBundled()
        let lib = try VariantLibrary.loadBundled()
        return VariantRotationPlanner(library: lib,
                                      portioner: VariantPortioner(calculator: PortionCalculator(database: db)))
    }

    @Test func rotatesFourVariantsAcrossSevenDays() throws {
        let week = try planner().plan(gymThursday: false, startIndex: 0)
        #expect(week.days.count == 7)
        #expect(week.days.map(\.variantID) == ["V1", "V2", "V3", "V4", "V1", "V2", "V3"])
    }

    @Test func mealsRepeatAtMostEveryFourDays() throws {
        let week = try planner().plan(gymThursday: false)
        // Group day offsets by variant; consecutive uses must be ≥4 days apart.
        var lastSeen: [String: Int] = [:]
        for day in week.days {
            if let prev = lastSeen[day.variantID] {
                #expect(day.dayOffset - prev >= 4)
            }
            lastSeen[day.variantID] = day.dayOffset
        }
    }

    @Test func batchSafeMealsAreCookedAheadFreshOnesAreNot() throws {
        let week = try planner().plan(gymThursday: false)
        for day in week.days {
            for m in day.meals {
                if m.meal.batchSafe && day.dayOffset != CookScheduler.tiredDayOffset {
                    #expect(m.cookSessionID != nil, "\(m.meal.id) on day \(day.dayOffset) not assigned")
                    let session = week.cookSessions.first { $0.id == m.cookSessionID }
                    #expect(session?.coversDayOffsets.contains(day.dayOffset) == true)
                }
                if m.meal.freshOnly {
                    #expect(m.cookSessionID == nil)
                }
            }
        }
    }

    @Test func sundayMealsAreMadeFresh() throws {
        let week = try planner().plan(gymThursday: false)
        let sunday = try #require(week.day(CookScheduler.tiredDayOffset))
        #expect(sunday.meals.allSatisfy { $0.cookSessionID == nil })
    }

    @Test func gymThursdayMovesFridaySaturdayToFridaySession() throws {
        let week = try planner().plan(gymThursday: true)
        for offset in [4, 5] {
            let day = try #require(week.day(offset))
            for m in day.meals where m.cookSessionID != nil {
                #expect(m.cookSessionID == "fri")
            }
        }
    }

    @Test func startIndexShiftsRotation() throws {
        let week = try planner().plan(gymThursday: false, startIndex: 2)
        #expect(week.days.first?.variantID == "V3")
    }
}
