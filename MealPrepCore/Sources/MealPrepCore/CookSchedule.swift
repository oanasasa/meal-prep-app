import Foundation

/// One batch-cooking session in the rolling 2-day rhythm. Day offsets are
/// relative to the week's Monday (Monday = 0 … Sunday = 6); the Sunday prep
/// session sits at offset −1 (the Sunday before the week begins).
public struct CookSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Day the cooking happens, relative to Monday. May be −1 (Sunday before).
    public let cookDayOffset: Int
    /// Day offsets this session cooks food for.
    public let coversDayOffsets: [Int]

    public init(id: String, title: String, cookDayOffset: Int, coversDayOffsets: [Int]) {
        self.id = id
        self.title = title
        self.cookDayOffset = cookDayOffset
        self.coversDayOffsets = coversDayOffsets
    }
}

/// Builds the rolling 2-day cook schedule around her fixed calendar (work 9–5,
/// gym Mon/Wed/Fri 6 PM, optional Thursday gym). Never more than 2 days per
/// session; Sunday is the no-cook "tired day".
public enum CookScheduler {

    /// Day offsets (Mon…Sat) that are batch-cooked. Sunday (6) is the tired day.
    public static let cookedDayOffsets: [Int] = [0, 1, 2, 3, 4, 5]
    public static let tiredDayOffset = 6   // Sunday

    /// The three sessions. If she hits Thursday gym, the third session shifts
    /// from Thursday to Friday (she can't cook right after the 6 PM workout).
    public static func sessions(gymThursday: Bool) -> [CookSession] {
        [
            CookSession(id: "sun-prep", title: "Sunday prep",
                        cookDayOffset: -1, coversDayOffsets: [0, 1]),     // Mon, Tue
            CookSession(id: "tue", title: "Tuesday",
                        cookDayOffset: 1, coversDayOffsets: [2, 3]),      // Wed, Thu
            gymThursday
                ? CookSession(id: "fri", title: "Friday",
                              cookDayOffset: 4, coversDayOffsets: [4, 5]) // Fri, Sat
                : CookSession(id: "thu", title: "Thursday",
                              cookDayOffset: 3, coversDayOffsets: [4, 5]) // Fri, Sat
        ]
    }

    /// The session responsible for a given eating day (nil for the tired day).
    public static func session(forDayOffset day: Int, gymThursday: Bool) -> CookSession? {
        sessions(gymThursday: gymThursday).first { $0.coversDayOffsets.contains(day) }
    }

    /// Weekday name for a Monday-relative offset (−1 = Sunday … 6 = Sunday).
    public static func weekdayName(forOffset offset: Int) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let idx = ((offset % 7) + 7) % 7
        return names[idx]
    }

    /// Concrete date for an offset given the week's Monday.
    public static func date(forOffset offset: Int, weekStartMonday: Date,
                            calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: weekStartMonday) ?? weekStartMonday
    }
}
