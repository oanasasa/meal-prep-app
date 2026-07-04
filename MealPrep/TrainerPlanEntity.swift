import Foundation
import SwiftData
import MealPrepCore

/// The user's editable settings, persisted with SwiftData (local-first, offline).
/// The weekly plan itself is regenerated deterministically from this + a seed,
/// so we only need to persist the inputs, not the whole generated week.
@Model
final class TrainerPlanEntity {
    var dailyKcal: Double
    var dailyProtein: Double
    var dailyCarbs: Double
    var dailyFat: Double
    var mealsPerDay: Int
    /// Week-by-week toggle: if she hits Thursday gym, the 3rd cook session moves
    /// from Thursday to Friday.
    var gymThursday: Bool
    /// Husband eats the same meals, scaled up (1.3–1.5×).
    var husbandMultiplier: Double
    /// Reroll handle — bump to regenerate a different (still valid) week.
    var planSeed: Int

    init(dailyKcal: Double = 1600, dailyProtein: Double = 130,
         dailyCarbs: Double = 150, dailyFat: Double = 50,
         mealsPerDay: Int = 4, gymThursday: Bool = false,
         husbandMultiplier: Double = 1.4, planSeed: Int = 42) {
        self.dailyKcal = dailyKcal
        self.dailyProtein = dailyProtein
        self.dailyCarbs = dailyCarbs
        self.dailyFat = dailyFat
        self.mealsPerDay = mealsPerDay
        self.gymThursday = gymThursday
        self.husbandMultiplier = husbandMultiplier
        self.planSeed = planSeed
    }

    // MARK: - Bridges to MealPrepCore value types

    var daily: MacroVector {
        MacroVector(kcal: dailyKcal, protein: dailyProtein, carbs: dailyCarbs, fat: dailyFat)
    }

    var trainerPlan: TrainerPlan {
        TrainerPlan.defaultSplit(daily: daily, mealsPerDay: mealsPerDay)
    }

    var herProfile: Profile {
        Profile(id: "her", name: "Her", dailyTarget: daily)
    }

    var husbandProfile: Profile {
        Profile(id: "him", name: "Husband",
                dailyTarget: daily * husbandMultiplier,
                portionMultiplier: husbandMultiplier)
    }
}
