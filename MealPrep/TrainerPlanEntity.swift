import Foundation
import SwiftData
import MealPrepCore

/// The user's editable settings, persisted with SwiftData (local-first, offline).
/// The weekly plan itself is regenerated deterministically from this + a seed,
/// so we only need to persist the inputs, not the whole generated week.
@Model
final class TrainerPlanEntity {
    var dailyKcal: Double = 1600
    var dailyProtein: Double = 130
    var dailyCarbs: Double = 150
    var dailyFat: Double = 50
    var mealsPerDay: Int = 4
    /// Week-by-week toggle: if she hits Thursday gym, the 3rd cook session moves
    /// from Thursday to Friday.
    var gymThursday: Bool = false
    /// Husband eats the same meals, scaled up (1.3–1.5×).
    var husbandMultiplier: Double = 1.4
    /// Reroll handle — bump to regenerate a different (still valid) week.
    var planSeed: Int = 42

    // MARK: - Adjustable notification times (Settings)
    // Inline defaults are required here (not just in the initializer) so
    // SwiftData's lightweight migration can backfill these columns for
    // stores created before this phase — without them, migration fails with
    // "missing attribute values on mandatory destination attribute".
    var groceryHour: Int = 9
    var groceryMinute: Int = 0
    var morningSummaryHour: Int = 7
    var morningSummaryMinute: Int = 0
    var eveningNudgeHour: Int = 20
    var eveningNudgeMinute: Int = 0

    init(dailyKcal: Double = 1600, dailyProtein: Double = 130,
         dailyCarbs: Double = 150, dailyFat: Double = 50,
         mealsPerDay: Int = 4, gymThursday: Bool = false,
         husbandMultiplier: Double = 1.4, planSeed: Int = 42,
         groceryHour: Int = 9, groceryMinute: Int = 0,
         morningSummaryHour: Int = 7, morningSummaryMinute: Int = 0,
         eveningNudgeHour: Int = 20, eveningNudgeMinute: Int = 0) {
        self.dailyKcal = dailyKcal
        self.dailyProtein = dailyProtein
        self.dailyCarbs = dailyCarbs
        self.dailyFat = dailyFat
        self.mealsPerDay = mealsPerDay
        self.gymThursday = gymThursday
        self.husbandMultiplier = husbandMultiplier
        self.planSeed = planSeed
        self.groceryHour = groceryHour
        self.groceryMinute = groceryMinute
        self.morningSummaryHour = morningSummaryHour
        self.morningSummaryMinute = morningSummaryMinute
        self.eveningNudgeHour = eveningNudgeHour
        self.eveningNudgeMinute = eveningNudgeMinute
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
