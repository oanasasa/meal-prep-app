import Foundation

/// A wall-clock time, calendar-agnostic (used to build daily notification triggers).
public struct TimeOfDay: Codable, Equatable, Sendable {
    public let hour: Int
    public let minute: Int
    public init(_ hour: Int, _ minute: Int) { self.hour = hour; self.minute = minute }
}

/// When a supplement fires. Creatine differs on gym vs rest days.
public enum ReminderCadence: Equatable, Sendable {
    case daily(TimeOfDay)
    case gymVsRest(gym: TimeOfDay, rest: TimeOfDay)
}

public struct SupplementReminder: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let note: String
    public let cadence: ReminderCadence
}

/// The trainer's supplement + hydration schedule (Vitabolic brand). Times are
/// defaults; the app lets the user adjust them in Settings.
public enum Reminders {
    public static let supplements: [SupplementReminder] = [
        SupplementReminder(id: "multivitamin", name: "Daily Sport Multivitamin",
                           note: "With breakfast — take with food for absorption.",
                           cadence: .daily(TimeOfDay(7, 30))),
        SupplementReminder(id: "top-minerals", name: "Top Minerals",
                           note: "With breakfast (can go with the multivitamin).",
                           cadence: .daily(TimeOfDay(7, 30))),
        SupplementReminder(id: "krill-oil", name: "Antarctic Krill Oil (omega-3)",
                           note: "With a main meal that contains fat.",
                           cadence: .daily(TimeOfDay(13, 0))),
        SupplementReminder(id: "creatine", name: "Creatine (micronized)",
                           note: "~5 g with water. Consistency matters more than timing.",
                           cadence: .gymVsRest(gym: TimeOfDay(18, 45), rest: TimeOfDay(9, 0))),
        SupplementReminder(id: "magnesium", name: "Magnesium Bisglycinate",
                           note: "Evening, before bed — supports sleep & recovery.",
                           cadence: .daily(TimeOfDay(21, 30)))
    ]

    // MARK: Hydration
    public static let hydrationGoalMilliliters = 3000
    public static let hydrationTimes: [TimeOfDay] = [TimeOfDay(10, 0), TimeOfDay(14, 0), TimeOfDay(17, 0)]

    // MARK: Gym days (Monday = 0 … Sunday = 6). Mon/Wed/Fri, + optional Thursday.
    public static func gymDayOffsets(thursday: Bool) -> [Int] {
        [0, 2, 4] + (thursday ? [3] : [])
    }

    /// The time a supplement fires for a given day offset, honouring the
    /// gym-vs-rest split for creatine.
    public static func time(for reminder: SupplementReminder,
                            dayOffset: Int, thursdayGym: Bool) -> TimeOfDay {
        switch reminder.cadence {
        case .daily(let t):
            return t
        case .gymVsRest(let gym, let rest):
            return gymDayOffsets(thursday: thursdayGym).contains(dayOffset) ? gym : rest
        }
    }
}
