import Foundation

/// The morning meal-summary notification for one day.
public struct MorningSummaryContent: Equatable, Sendable {
    public let dayOffset: Int
    public let title: String
    public let body: String
}

/// A cook-session reminder, carrying the session id so the app can deep-link
/// straight into Cook Mode for it.
public struct CookSessionReminderPlan: Identifiable, Equatable, Sendable {
    public var id: String { session.id }
    public let session: CookSession
    public let title: String
    public let body: String
}

/// "Have you cooked tomorrow's food yet?" — fires the evening before a
/// batch-cooked day. `sessionID` is the session that must be marked cooked to
/// cancel this specific reminder (local notifications can't re-check server
/// state, so the app cancels it directly when the session is completed).
public struct EveningNudgePlan: Identifiable, Equatable, Sendable {
    public var id: String { "nudge-\(forDayOffset)" }
    public let nudgeDayOffset: Int
    public let forDayOffset: Int
    public let sessionID: String
}

/// Pure computation of what meal-plan notifications a week implies. Actual
/// scheduling (UNUserNotificationCenter) lives in the app layer, mirroring how
/// Reminders/ReminderScheduler split for supplements.
public enum NotificationPlanBuilder {

    public static func morningSummaries(for week: VariantWeek) -> [MorningSummaryContent] {
        week.days.map { day in
            let mains = day.meals.filter { $0.meal.mealType == .lunch || $0.meal.mealType == .dinner }
            let parts = mains.map {
                "\($0.meal.mealType.displayName.lowercased()) = \($0.meal.name) (\(Int($0.herMacros.kcal.rounded())) kcal)"
            }
            let body = parts.isEmpty ? "No batch meals today — enjoy your rest day." : parts.joined(separator: ", ")
            return MorningSummaryContent(dayOffset: day.dayOffset,
                                         title: "Today · \(CookScheduler.weekdayName(forOffset: day.dayOffset))",
                                         body: body)
        }
    }

    public static func cookSessionReminders(for week: VariantWeek) -> [CookSessionReminderPlan] {
        week.cookSessions.map { session in
            let covered = session.coversDayOffsets.map { CookScheduler.weekdayName(forOffset: $0) }.joined(separator: " + ")
            return CookSessionReminderPlan(session: session,
                                           title: "Cook session: \(session.title)",
                                           body: "Batch-cook for \(covered) — tap to start Cook Mode.")
        }
    }

    /// One nudge per batch-cooked day (the tired day has nothing pre-cooked to
    /// check on, so it's excluded).
    public static func eveningNudges(for week: VariantWeek) -> [EveningNudgePlan] {
        week.days.compactMap { day in
            guard let sessionID = day.meals.compactMap(\.cookSessionID).first else { return nil }
            return EveningNudgePlan(nudgeDayOffset: day.dayOffset - 1, forDayOffset: day.dayOffset, sessionID: sessionID)
        }
    }

    public static func groceryNotificationBody(itemCount: Int) -> String {
        "Grocery list ready — \(itemCount) items."
    }
}
