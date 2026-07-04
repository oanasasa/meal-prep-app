import Foundation
import UserNotifications
import MealPrepCore

/// Schedules the meal-plan notifications: grocery-ready, cook-session reminders
/// (deep-linking to Cook Mode), morning meal summaries, and evening-before
/// nudges. Mirrors ReminderScheduler's approach — pure MealPrepCore functions
/// compute the content; this just turns it into weekly-repeating local
/// notifications and only ever touches its own "meal-" prefixed identifiers.
enum MealNotificationScheduler {

    // Fixed defaults matching the spec text; only the *time* is user-adjustable
    // for now (via TrainerPlanEntity), not which day each fires on.
    private static let groceryDayOffset = 5   // Saturday
    private static let sessionTimes: [String: TimeOfDay] = [
        "sun-prep": TimeOfDay(14, 0),   // Sunday afternoon
        "tue": TimeOfDay(19, 30),       // Tuesday ~7:30 PM
        "thu": TimeOfDay(19, 0),
        "fri": TimeOfDay(19, 0)
    ]

    static func reschedule(model: AppModel, plan: TrainerPlanEntity) async {
        guard let week = model.variantWeek(for: plan) else { return }
        let center = UNUserNotificationCenter.current()

        var ownIDs = ["meal-grocery"]
        ownIDs += (0...6).map { "meal-morning-\($0)" }
        ownIDs += week.cookSessions.map { "meal-cook-\($0.id)" }
        ownIDs += (0...6).map { "meal-nudge-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ownIDs)

        let profiles = [plan.herProfile, plan.husbandProfile]

        // Grocery list ready.
        let groceryCount = GroceryListBuilder.build(for: week, profiles: profiles,
                                                     portioner: model.portioner, database: model.database).count
        var groceryDC = DateComponents(hour: plan.groceryHour, minute: plan.groceryMinute)
        groceryDC.weekday = weekday(fromMondayOffset: groceryDayOffset)
        ReminderScheduler.add(id: "meal-grocery", title: "Grocery list ready",
                             body: NotificationPlanBuilder.groceryNotificationBody(itemCount: groceryCount),
                             dateComponents: groceryDC, center: center, userInfo: ["route": "grocery"])

        // Morning meal summary, every day.
        for summary in NotificationPlanBuilder.morningSummaries(for: week) {
            var dc = DateComponents(hour: plan.morningSummaryHour, minute: plan.morningSummaryMinute)
            dc.weekday = weekday(fromMondayOffset: summary.dayOffset)
            ReminderScheduler.add(id: "meal-morning-\(summary.dayOffset)", title: summary.title,
                                 body: summary.body, dateComponents: dc, center: center)
        }

        // Cook-session reminders, deep-linking to Cook Mode.
        for reminder in NotificationPlanBuilder.cookSessionReminders(for: week) {
            let t = sessionTimes[reminder.session.id] ?? TimeOfDay(18, 0)
            var dc = DateComponents(hour: t.hour, minute: t.minute)
            dc.weekday = weekday(fromMondayOffset: reminder.session.cookDayOffset)
            ReminderScheduler.add(id: "meal-cook-\(reminder.session.id)", title: reminder.title,
                                 body: reminder.body, dateComponents: dc, center: center,
                                 userInfo: ["route": "cookMode", "sessionID": reminder.session.id])
        }

        // Evening-before nudges (also deep-link to Cook Mode for that session).
        for nudge in NotificationPlanBuilder.eveningNudges(for: week) {
            var dc = DateComponents(hour: plan.eveningNudgeHour, minute: plan.eveningNudgeMinute)
            dc.weekday = weekday(fromMondayOffset: nudge.nudgeDayOffset)
            let dayName = CookScheduler.weekdayName(forOffset: nudge.forDayOffset)
            ReminderScheduler.add(id: "meal-nudge-\(nudge.forDayOffset)", title: "Cooked yet?",
                                 body: "Tomorrow (\(dayName))'s food — have you batch-cooked it?",
                                 dateComponents: dc, center: center,
                                 userInfo: ["route": "cookMode", "sessionID": nudge.sessionID])
        }
    }

    /// Local notifications can't re-check server state, so cancel the specific
    /// evening nudges tied to a session the moment it's marked cooked.
    static func cancelNudges(for sessionID: String, week: VariantWeek) {
        let ids = NotificationPlanBuilder.eveningNudges(for: week)
            .filter { $0.sessionID == sessionID }
            .map { "meal-nudge-\($0.forDayOffset)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
