import Foundation
import SwiftData
import MealPrepCore

/// Tracks whether a specific week's cook session has actually been cooked.
/// Keyed by week-start date + session id, since the same session id (e.g.
/// "sun-prep") recurs every week. Marking a session cooked lets the evening
/// nudge for its covered days be cancelled locally (see MealNotificationScheduler).
///
/// `snapshotData` freezes exactly which meals (and their grams/macros) were
/// cooked at that moment — so if the underlying variant is edited afterward,
/// this already-committed record doesn't silently change. Edits only affect
/// weeks that haven't been cooked yet.
@Model
final class CookSessionLogEntity {
    @Attribute(.unique) var sessionKey: String
    var isCooked: Bool = false
    var cookedAt: Date? = nil
    var snapshotData: Data = Data()

    init(sessionKey: String, isCooked: Bool = false, cookedAt: Date? = nil) {
        self.sessionKey = sessionKey
        self.isCooked = isCooked
        self.cookedAt = cookedAt
    }

    static func key(weekStart: Date, sessionID: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: weekStart)
        return String(format: "%04d-%02d-%02d-%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, sessionID)
    }

    var snapshot: [MealTemplate] {
        (try? JSONDecoder().decode([MealTemplate].self, from: snapshotData)) ?? []
    }

    func recordSnapshot(_ meals: [MealTemplate]) {
        snapshotData = (try? JSONEncoder().encode(meals)) ?? Data()
    }
}
