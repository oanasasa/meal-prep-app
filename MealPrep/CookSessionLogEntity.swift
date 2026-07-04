import Foundation
import SwiftData

/// Tracks whether a specific week's cook session has actually been cooked.
/// Keyed by week-start date + session id, since the same session id (e.g.
/// "sun-prep") recurs every week. Marking a session cooked lets the evening
/// nudge for its covered days be cancelled locally (see MealNotificationScheduler).
@Model
final class CookSessionLogEntity {
    @Attribute(.unique) var sessionKey: String
    var isCooked: Bool = false
    var cookedAt: Date? = nil

    init(sessionKey: String, isCooked: Bool = false, cookedAt: Date? = nil) {
        self.sessionKey = sessionKey
        self.isCooked = isCooked
        self.cookedAt = cookedAt
    }

    static func key(weekStart: Date, sessionID: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: weekStart)
        return String(format: "%04d-%02d-%02d-%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, sessionID)
    }
}
