import Foundation

/// A variant meal placed on a specific day, with her computed macros and the
/// cook session that prepares it (nil = made fresh that day).
public struct PlannedVariantMeal: Identifiable, Equatable, Sendable {
    public let id: String
    public let dayOffset: Int
    public let variantID: String
    public let meal: MealTemplate
    public let herMacros: MacroVector
    public let cookSessionID: String?
}

public struct VariantDay: Identifiable, Equatable, Sendable {
    public var id: Int { dayOffset }
    public let dayOffset: Int          // 0 = Monday … 6 = Sunday
    public let variantID: String
    public let meals: [PlannedVariantMeal]
}

public struct VariantWeek: Equatable, Sendable {
    public let weekStartMonday: Date
    public let gymThursday: Bool
    public let days: [VariantDay]
    public let cookSessions: [CookSession]

    public func day(_ offset: Int) -> VariantDay? { days.first { $0.dayOffset == offset } }
    public func meals(inSession id: String) -> [PlannedVariantMeal] {
        days.flatMap(\.meals).filter { $0.cookSessionID == id }
    }
}

/// Assigns one trainer variant per day, rotating through the ACTIVE variants
/// only (a retired variant is skipped, not deleted — instruction: "deactivate
/// instead of deleting, history stays intact") so any meal repeats at most
/// every N days for N active variants. Batch-safe meals on cooked days are
/// tied to the rolling 2-day cook sessions; fresh/assembly meals (and Sunday,
/// the uncovered day) are made fresh.
public struct VariantRotationPlanner: Sendable {
    public let library: VariantLibrary
    public let portioner: VariantPortioner

    public init(library: VariantLibrary, portioner: VariantPortioner) {
        self.library = library
        self.portioner = portioner
    }

    public func plan(gymThursday: Bool,
                     weekStartMonday: Date = Date(),
                     startIndex: Int = 0) throws -> VariantWeek {
        let variants = library.all.filter(\.isActive)
        guard !variants.isEmpty else {
            return VariantWeek(weekStartMonday: weekStartMonday, gymThursday: gymThursday,
                               days: [], cookSessions: CookScheduler.sessions(gymThursday: gymThursday))
        }

        var days: [VariantDay] = []
        for day in 0...6 {
            let variant = variants[((startIndex + day) % variants.count + variants.count) % variants.count]
            let session = CookScheduler.session(forDayOffset: day, gymThursday: gymThursday)

            let meals = try variant.meals.map { meal -> PlannedVariantMeal in
                let cookSessionID = (meal.batchSafe && !meal.freshOnly) ? session?.id : nil
                return PlannedVariantMeal(
                    id: "d\(day)-\(meal.id)",
                    dayOffset: day,
                    variantID: variant.id,
                    meal: meal,
                    herMacros: try portioner.macros(for: meal, multiplier: 1.0),
                    cookSessionID: cookSessionID
                )
            }
            days.append(VariantDay(dayOffset: day, variantID: variant.id, meals: meals))
        }

        return VariantWeek(weekStartMonday: weekStartMonday, gymThursday: gymThursday,
                           days: days, cookSessions: CookScheduler.sessions(gymThursday: gymThursday))
    }
}
