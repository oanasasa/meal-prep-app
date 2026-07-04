import Foundation

/// One meal placed in the week: which recipe, scaled how much, the resulting
/// macros for "Her", the target it was matched to, and which cook session (if
/// any) prepares it.
public struct PlannedMeal: Identifiable, Equatable, Sendable {
    public let id: String
    public let dayOffset: Int          // 0 = Monday … 6 = Sunday
    public let mealType: MealType
    public let recipeID: String
    public let scale: Double           // multiplier on the base recipe for "Her"
    public let herMacros: MacroVector
    public let target: MacroVector
    public let cookSessionID: String?  // nil for fresh-daily meals & the tired day

    public var delta: MacroDelta { MacroDelta(target: target, actual: herMacros) }

    /// Her per-ingredient raw grams for this meal (base × scale).
    public func herLines(base: [RecipeLine]) -> [RecipeLine] {
        base.map { RecipeLine(ingredientID: $0.ingredientID, baseRawGrams: $0.baseRawGrams * scale) }
    }
}

/// A generated week.
public struct WeekPlan: Equatable, Sendable {
    public let weekStartMonday: Date
    public let gymThursday: Bool
    public let meals: [PlannedMeal]
    public let cookSessions: [CookSession]

    public func meals(onDay dayOffset: Int) -> [PlannedMeal] {
        meals.filter { $0.dayOffset == dayOffset }
    }
    public func meals(inSession sessionID: String) -> [PlannedMeal] {
        meals.filter { $0.cookSessionID == sessionID }
    }
}

/// Deterministic PRNG (SplitMix64) so a given seed always yields the same plan —
/// important for testable output and "regenerate = same unless you reroll".
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct WeeklyPlanGenerator {
    public let library: RecipeLibrary
    public let calculator: PortionCalculator

    /// Dinner day offsets that get a "husband compromise" recipe (healthy
    /// fast-food) so both eat the same meal ~twice a week.
    public var husbandCompromiseDinnerDays: Set<Int> = [2, 5]  // Wednesday, Saturday
    /// How strongly to avoid repeating a recipe across the week.
    public var varietyPenalty: Double = 0.6

    public init(library: RecipeLibrary, calculator: PortionCalculator) {
        self.library = library
        self.calculator = calculator
    }

    public func generate(plan: TrainerPlan,
                         gymThursday: Bool,
                         weekStartMonday: Date = Date(),
                         seed: UInt64 = 42) throws -> WeekPlan {
        var rng = SeededGenerator(seed: seed)
        let sessions = CookScheduler.sessions(gymThursday: gymThursday)

        // Cache base macros per recipe.
        var baseMacros: [String: MacroVector] = [:]
        for r in library.all { baseMacros[r.id] = try calculator.baseMacros(for: r.lines) }

        var usage: [String: Int] = [:]
        var meals: [PlannedMeal] = []

        for day in 0...6 {                       // Monday … Sunday
            let isTiredDay = (day == CookScheduler.tiredDayOffset)
            for (slotIndex, mealType) in plan.mealTypes.enumerated() {
                let target = plan.mealTargets[slotIndex]
                let cooked = mealType.isBatchCooked && !isTiredDay
                let needHusband = mealType == .dinner
                    && husbandCompromiseDinnerDays.contains(day) && !isTiredDay

                let recipe = pickRecipe(mealType: mealType,
                                        isTiredDay: isTiredDay,
                                        requireBatchSafe: cooked,
                                        requireHusband: needHusband,
                                        target: target,
                                        baseMacros: baseMacros,
                                        usage: &usage,
                                        rng: &rng)

                let base = baseMacros[recipe.id] ?? .zero
                let scale = scaleFactor(base: base, target: target)
                let her = base * scale
                let sessionID = mealType.isBatchCooked && !isTiredDay
                    ? sessions.first { $0.coversDayOffsets.contains(day) }?.id
                    : nil

                meals.append(PlannedMeal(
                    id: "d\(day)-s\(slotIndex)",
                    dayOffset: day,
                    mealType: mealType,
                    recipeID: recipe.id,
                    scale: scale,
                    herMacros: her,
                    target: target,
                    cookSessionID: sessionID
                ))
            }
        }

        return WeekPlan(weekStartMonday: weekStartMonday,
                        gymThursday: gymThursday,
                        meals: meals,
                        cookSessions: sessions)
    }

    // MARK: - Scaling

    /// Anchor on protein (a macro plan's non-negotiable); fall back to kcal for
    /// (rare) near-zero-protein recipes. Clamp to a sane portion range.
    func scaleFactor(base: MacroVector, target: MacroVector) -> Double {
        let raw: Double
        if base.protein > 1 && target.protein > 0 {
            raw = target.protein / base.protein
        } else if base.kcal > 0 {
            raw = target.kcal / base.kcal
        } else {
            raw = 1
        }
        return min(max(raw, 0.4), 3.0)
    }

    // MARK: - Selection

    private func pickRecipe(mealType: MealType,
                            isTiredDay: Bool,
                            requireBatchSafe: Bool,
                            requireHusband: Bool,
                            target: MacroVector,
                            baseMacros: [String: MacroVector],
                            usage: inout [String: Int],
                            rng: inout SeededGenerator) -> Recipe {
        let all = library.recipes(for: mealType)

        // Husband-compromise recipes are RESERVED for the designated dinners so
        // they show up only ~twice a week: required on a husband slot, excluded
        // from every other slot (until the last-ditch fallback tier).
        let husbandOK: (Recipe) -> Bool = { r in
            requireHusband ? r.husbandCompromise : !r.husbandCompromise
        }

        // Graded filters: try strict, then progressively relax so we never fail
        // to fill a slot even if the library is thin.
        let candidateSets: [[Recipe]] = [
            all.filter { husbandOK($0) && (!isTiredDay || $0.tiredDay) && (!requireBatchSafe || $0.batchSafe2Days) },
            all.filter { husbandOK($0) && (!requireBatchSafe || $0.batchSafe2Days) },
            all.filter { !requireBatchSafe || $0.batchSafe2Days },
            all
        ]
        let candidates = candidateSets.first { !$0.isEmpty } ?? all
        guard !candidates.isEmpty else {
            // Absolute fallback: any recipe at all (keeps the generator total).
            return library.all.randomElement(using: &rng) ?? library.all[0]
        }

        // Score = relative kcal error after protein-anchored scaling + a variety
        // penalty for recipes already used this week. Shuffle first so ties are
        // broken deterministically-but-varied by the seed.
        let pool = candidates.shuffled(using: &rng)
        func score(_ r: Recipe) -> Double {
            let base = baseMacros[r.id] ?? .zero
            let scale = scaleFactor(base: base, target: target)
            let kcal = base.kcal * scale
            let kcalErr = target.kcal > 0 ? abs(kcal - target.kcal) / target.kcal : 0
            return kcalErr + Double(usage[r.id, default: 0]) * varietyPenalty
        }
        let chosen = pool.min { score($0) < score($1) } ?? pool[0]
        usage[chosen.id, default: 0] += 1
        return chosen
    }
}
