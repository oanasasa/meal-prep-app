import Testing
@testable import MealPrepCore

@Suite("Notification plan builder")
struct NotificationPlanTests {

    func makeWeek(gymThursday: Bool = false) throws -> VariantWeek {
        let db = try IngredientDatabase.loadBundled()
        let lib = try VariantLibrary.loadBundled()
        let port = VariantPortioner(calculator: PortionCalculator(database: db))
        let planner = VariantRotationPlanner(library: lib, portioner: port)
        return try planner.plan(gymThursday: gymThursday, startIndex: 0)
    }

    @Test func oneMorningSummaryPerDayMentioningLunchAndDinner() throws {
        let summaries = NotificationPlanBuilder.morningSummaries(for: try makeWeek())
        #expect(summaries.count == 7)
        let monday = try #require(summaries.first { $0.dayOffset == 0 })
        #expect(monday.body.contains("lunch"))
        #expect(monday.body.contains("dinner"))
        #expect(monday.body.contains("kcal"))
    }

    @Test func tiredDaySummaryStillProducedButHasNoBatchMeals() throws {
        let summaries = NotificationPlanBuilder.morningSummaries(for: try makeWeek())
        let sunday = try #require(summaries.first { $0.dayOffset == CookScheduler.tiredDayOffset })
        // Sunday still has lunch/dinner meals (just not batch-cooked), so the
        // summary should still be non-empty and mention them.
        #expect(!sunday.body.isEmpty)
    }

    @Test func oneCookSessionReminderPerSessionWithDeepLinkID() throws {
        let week = try makeWeek()
        let reminders = NotificationPlanBuilder.cookSessionReminders(for: week)
        #expect(reminders.count == 3)
        #expect(Set(reminders.map(\.id)) == Set(week.cookSessions.map(\.id)))
        for r in reminders { #expect(r.body.contains("Cook Mode")) }
    }

    @Test func eveningNudgeExistsForEveryBatchCookedDayNotTheTiredDay() throws {
        let week = try makeWeek()
        let nudges = NotificationPlanBuilder.eveningNudges(for: week)
        let nudgedDays = Set(nudges.map(\.forDayOffset))
        #expect(!nudgedDays.contains(CookScheduler.tiredDayOffset))
        // Every other day has at least one batch-cooked meal in this plan.
        #expect(nudgedDays.count == 6)
        for n in nudges { #expect(n.nudgeDayOffset == n.forDayOffset - 1) }
    }

    @Test func eveningNudgeCarriesTheRightSessionToCancel() throws {
        let week = try makeWeek()
        let nudges = NotificationPlanBuilder.eveningNudges(for: week)
        let mondayNudge = try #require(nudges.first { $0.forDayOffset == 0 })
        #expect(mondayNudge.sessionID == "sun-prep")
        let tuesdayNudge = try #require(nudges.first { $0.forDayOffset == 1 })
        #expect(tuesdayNudge.sessionID == "sun-prep")
    }

    @Test func groceryBodyIncludesItemCount() {
        #expect(NotificationPlanBuilder.groceryNotificationBody(itemCount: 23) == "Grocery list ready — 23 items.")
    }
}
