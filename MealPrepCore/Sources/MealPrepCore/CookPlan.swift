import Foundation

/// One step, tagged with which meal it came from, ready to render in a merged
/// per-station column ("Oven", "Stovetop", "Rice cooker", "Assembly").
public struct CookStepInstance: Identifiable, Equatable, Sendable {
    public let id: String
    public let mealName: String
    public let step: CookStep
}

public struct StationPlan: Identifiable, Equatable, Sendable {
    public var id: CookMethod { method }
    public let method: CookMethod
    public let steps: [CookStepInstance]
    /// This station's own duration — all-passive steps overlap (max), any
    /// active step makes the station sequential (sum).
    public let stationMinutes: Int
}

/// Total raw grams of one ingredient to cook for the whole session (every
/// covered day × every profile).
public struct BatchIngredientAmount: Identifiable, Equatable, Sendable {
    public var id: String { ingredientID }
    public let ingredientID: String
    public let name: String
    public let totalRawGrams: Double
    public let unit: MeasureUnit
}

/// How much of each ingredient goes into ONE person's container for ONE meal
/// on ONE day — the actual portioning instruction ("Monday, Her, Chicken
/// pasta: 170g chicken, 90g pasta, 100g sauce…").
public struct ContainerPortion: Identifiable, Equatable, Sendable {
    public var id: String { "\(dayOffset)-\(profileID)-\(mealID)" }
    public let dayOffset: Int
    public let profileID: String
    public let profileName: String
    public let mealID: String
    public let mealName: String
    public let lines: [RecipeLine]
}

public struct CookPlan: Equatable, Sendable {
    public let sessionID: String
    public let stations: [StationPlan]
    /// Wall-clock estimate: max(sum of active-step minutes, longest single
    /// passive step) — active steps need your hands one at a time; passive
    /// steps (oven, rice cooker, simmering) run in the background together.
    public let totalMinutes: Int
    public let batchGrams: [BatchIngredientAmount]
    public let containerPortions: [ContainerPortion]
}

/// Builds a merged, parallelized Cook Mode plan for one cook session from
/// however many batch-safe meals across its covered days share that session.
public struct CookPlanBuilder: Sendable {
    public let database: IngredientDatabase
    public let portioner: VariantPortioner

    public init(database: IngredientDatabase, portioner: VariantPortioner) {
        self.database = database
        self.portioner = portioner
    }

    public func plan(for session: CookSession, week: VariantWeek, profiles: [Profile]) -> CookPlan {
        let sessionMeals: [PlannedVariantMeal] = session.coversDayOffsets
            .compactMap { week.day($0) }
            .flatMap { day in day.meals.map { (day.dayOffset, $0) } }
            .filter { $0.1.cookSessionID == session.id }
            .map { $0.1 }

        // MARK: Stations (grouped by equipment, for the merged parallel view)
        var byMethod: [CookMethod: [CookStepInstance]] = [:]
        for meal in sessionMeals {
            for step in meal.meal.cookSteps {
                let instance = CookStepInstance(id: "\(meal.id)-\(step.text)", mealName: meal.meal.name, step: step)
                byMethod[step.method, default: []].append(instance)
            }
        }
        let stations = CookMethod.allCases.compactMap { method -> StationPlan? in
            guard let steps = byMethod[method], !steps.isEmpty else { return nil }
            return StationPlan(method: method, steps: steps, stationMinutes: Self.duration(steps.map(\.step)))
        }

        // MARK: Total session time (all steps across all stations combined)
        let allSteps = sessionMeals.flatMap { $0.meal.cookSteps }
        let totalMinutes = Self.duration(allSteps)

        // MARK: Batch grams + container portions
        var totals: [String: Double] = [:]
        var portions: [ContainerPortion] = []
        for dayOffset in session.coversDayOffsets {
            guard let day = week.day(dayOffset) else { continue }
            for meal in day.meals where meal.cookSessionID == session.id {
                for profile in profiles {
                    let lines = portioner.lines(for: meal.meal, multiplier: profile.portionMultiplier)
                    for line in lines { totals[line.ingredientID, default: 0] += line.baseRawGrams }
                    portions.append(ContainerPortion(
                        dayOffset: dayOffset, profileID: profile.id, profileName: profile.name,
                        mealID: meal.meal.id, mealName: meal.meal.name, lines: lines
                    ))
                }
            }
        }
        let batchGrams = totals.compactMap { id, grams -> BatchIngredientAmount? in
            guard let ing = database.ingredient(id: id) else { return nil }
            return BatchIngredientAmount(ingredientID: id, name: ing.name, totalRawGrams: grams, unit: ing.unit)
        }.sorted { $0.name < $1.name }

        let sortedPortions = portions.sorted {
            ($0.dayOffset, $0.mealID, $0.profileID) < ($1.dayOffset, $1.mealID, $1.profileID)
        }

        return CookPlan(sessionID: session.id, stations: stations, totalMinutes: totalMinutes,
                        batchGrams: batchGrams, containerPortions: sortedPortions)
    }

    /// All-passive steps overlap (you start them and walk away) — duration is
    /// the longest one. Any active step needs your hands, one at a time, so it
    /// adds to a running total that runs alongside whatever's passively cooking.
    public static func duration(_ steps: [CookStep]) -> Int {
        guard !steps.isEmpty else { return 0 }
        let active = steps.filter { !$0.isPassive }.map(\.minutes).reduce(0, +)
        let passiveMax = steps.filter(\.isPassive).map(\.minutes).max() ?? 0
        return max(active, passiveMax)
    }
}
