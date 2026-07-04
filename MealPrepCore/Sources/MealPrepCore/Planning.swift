import Foundation

/// The kind of meal in a day. Breakfast/snack are made fresh daily; lunch/dinner
/// are the batch-cooked meals that get assigned to cook sessions.
public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    /// Only these are batch-cooked ahead and belong to a cook session.
    public var isBatchCooked: Bool { self == .lunch || self == .dinner }

    public var displayName: String { rawValue.capitalized }
}

/// The trainer's plan: a daily macro target split into per-meal targets. This is
/// what the user enters manually (Feature 1) and what the generator matches.
public struct TrainerPlan: Codable, Equatable, Sendable {
    public let daily: MacroVector
    /// Per-meal targets, in the order they occur through the day.
    public let mealTargets: [MacroVector]
    public let mealTypes: [MealType]

    public var mealsPerDay: Int { mealTargets.count }

    public init(daily: MacroVector, mealTargets: [MacroVector], mealTypes: [MealType]) {
        precondition(mealTargets.count == mealTypes.count, "targets/types count mismatch")
        self.daily = daily
        self.mealTargets = mealTargets
        self.mealTypes = mealTypes
    }

    /// Build a plan by splitting the daily target across meals with the given
    /// fractions (same fraction applied to every macro). Fractions are
    /// normalised so they need not sum to exactly 1.
    public static func split(daily: MacroVector,
                             mealTypes: [MealType],
                             fractions: [Double]) -> TrainerPlan {
        precondition(mealTypes.count == fractions.count && !fractions.isEmpty,
                     "types/fractions must be non-empty and equal length")
        let total = fractions.reduce(0, +)
        let norm = total > 0 ? fractions.map { $0 / total } : fractions.map { _ in 1.0 / Double(fractions.count) }
        let targets = norm.map { daily * $0 }
        return TrainerPlan(daily: daily, mealTargets: targets, mealTypes: mealTypes)
    }

    /// Sensible default distribution for common meal counts, so onboarding can
    /// offer a starting point the user then tweaks.
    public static func defaultSplit(daily: MacroVector, mealsPerDay: Int) -> TrainerPlan {
        switch mealsPerDay {
        case 3:
            return split(daily: daily,
                         mealTypes: [.breakfast, .lunch, .dinner],
                         fractions: [0.30, 0.35, 0.35])
        case 4:
            return split(daily: daily,
                         mealTypes: [.breakfast, .lunch, .snack, .dinner],
                         fractions: [0.25, 0.32, 0.13, 0.30])
        case 5:
            return split(daily: daily,
                         mealTypes: [.breakfast, .snack, .lunch, .snack, .dinner],
                         fractions: [0.22, 0.10, 0.30, 0.10, 0.28])
        default:
            // Even split across N generic meals.
            let types = (0..<max(1, mealsPerDay)).map { i -> MealType in
                switch i {
                case 0: return .breakfast
                case mealsPerDay - 1: return .dinner
                default: return .lunch
                }
            }
            return split(daily: daily, mealTypes: types,
                         fractions: Array(repeating: 1.0, count: max(1, mealsPerDay)))
        }
    }
}
