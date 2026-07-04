import Foundation
import SwiftData

/// Per-day tracking (local-first): which supplements were taken and how much
/// water was drunk. Keyed by a "yyyy-MM-dd" string so there's one row per day.
@Model
final class DailyLogEntity {
    @Attribute(.unique) var dayKey: String
    var takenSupplementIDs: [String] = []
    var waterMilliliters: Int = 0

    init(dayKey: String, takenSupplementIDs: [String] = [], waterMilliliters: Int = 0) {
        self.dayKey = dayKey
        self.takenSupplementIDs = takenSupplementIDs
        self.waterMilliliters = waterMilliliters
    }

    static func key(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func isTaken(_ supplementID: String) -> Bool { takenSupplementIDs.contains(supplementID) }

    func toggle(_ supplementID: String) {
        if let idx = takenSupplementIDs.firstIndex(of: supplementID) {
            takenSupplementIDs.remove(at: idx)
        } else {
            takenSupplementIDs.append(supplementID)
        }
    }
}
