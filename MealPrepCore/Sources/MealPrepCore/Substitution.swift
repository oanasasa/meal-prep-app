import Foundation

// MARK: - The model
//
// A meal is a set of ingredient lines whose macros sum to (approximately) a
// per-meal TARGET set by the trainer. When one ingredient is missing we keep
// every other line fixed and solve for the grams of a substitute so the whole
// meal lands back on target.
//
// Let:
//   R   = macros of the meal MINUS the missing line          ("remainder", fixed)
//   T   = the meal's macro target                            (trainer's per-meal split)
//   N   = T − R                                              ("need": what the substitute must supply)
//   v   = the substitute's per-100g macro vector
//   g   = grams of substitute  (the unknown)
//
// The substitute contributes  v · (g / 100).  We want  v · (g/100) ≈ N.
// One scalar g cannot generally hit a 4-vector N exactly, so we minimise a
// WEIGHTED squared error and take the closed-form least-squares optimum. The
// weighting is relative to the target (so a 10 kcal miss on a 500 kcal target
// counts like a 0.2 g miss on a 10 g target) with an extra emphasis on protein,
// because a macro plan lives and dies by protein.
//
//   minimise  Σ_i  w_i · ( a_i · g − N_i )²        where a_i = v_i / 100
//   ⇒  g* = ( Σ_i w_i a_i N_i ) / ( Σ_i w_i a_i² )
//
// g* is clamped to ≥ 0. We then report the resulting whole-meal macros, the
// signed delta vs target, and whether every macro is within ±5%.
//
// Note: when the original meal was exactly on target, N equals the missing
// ingredient's own contribution, so "match the meal target" and "match what was
// removed" coincide — but targeting T is self-correcting if the meal had drifted.

/// Relative importance of each macro in the least-squares fit. Defaults put
/// double weight on protein. These are *priorities*; the solver also divides by
/// target² to make the fit scale-invariant.
public struct MacroWeights: Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    /// kcal is excluded from the *fit* by default (weight 0) because it is a
    /// linear function of P/C/F — fitting it too would double-count energy.
    /// It is still checked against the ±5% tolerance afterwards.
    public static let `default` = MacroWeights(kcal: 0, protein: 2, carbs: 1, fat: 1)

    func value(for field: MacroField) -> Double {
        switch field {
        case .kcal: return kcal
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }
}

/// One ranked substitution offer.
public struct SubstitutionSuggestion: Equatable, Sendable {
    public let substitute: Ingredient
    /// Recommended RAW grams of the substitute.
    public let grams: Double
    /// Whole-meal macros after the swap (remainder + substitute).
    public let resultingMeal: MacroVector
    /// Comparison of `resultingMeal` against the target.
    public let delta: MacroDelta
    /// True when every enforced macro is within tolerance (default ±5%).
    public let withinTolerance: Bool

    /// Lower is better — RMS fractional error over the enforced macros, used to
    /// rank offers. `tiebreakScore` breaks ties using all four macros so the
    /// overall-closest option wins when two score equally on the enforced ones.
    public let score: Double
    public let tiebreakScore: Double
}

public struct SubstitutionEngine {
    public let database: IngredientDatabase
    public var weights: MacroWeights
    public var tolerance: Double
    /// Which macros must be within tolerance for `withinTolerance` to be true.
    /// Trainer cares hardest about kcal + protein; carbs/fat are shown but soft.
    public var enforced: Set<MacroField>

    public init(database: IngredientDatabase,
                weights: MacroWeights = .default,
                tolerance: Double = 0.05,
                enforced: Set<MacroField> = [.kcal, .protein]) {
        self.database = database
        self.weights = weights
        self.tolerance = tolerance
        self.enforced = enforced
    }

    // MARK: - The 1-D solver (pure, deterministic, directly unit-tested)

    /// Least-squares grams of `substitute` to best supply the macro vector `need`,
    /// given the meal `target` used to make the fit scale-invariant. Clamped ≥ 0.
    public func solveGrams(substitute: Ingredient,
                           need: MacroVector,
                           target: MacroVector) -> Double {
        var numerator = 0.0
        var denominator = 0.0
        for field in MacroField.allCases {
            let priority = weights.value(for: field)
            if priority == 0 { continue }
            // Scale-invariant weight: priority / target² (guard against 0 target).
            let t = target[field]
            let scale = t == 0 ? 1.0 : (1.0 / (t * t))
            let w = priority * scale
            let a = substitute.per100g[field] / 100.0   // macro per gram
            numerator += w * a * need[field]
            denominator += w * a * a
        }
        guard denominator > 0 else { return 0 }
        return max(0, numerator / denominator)
    }

    // MARK: - Suggestions

    /// Rank substitutes for a missing ingredient in a meal.
    ///
    /// - Parameters:
    ///   - missingID: the ingredient that's unavailable.
    ///   - meal: the full recipe lines (base/her grams). `missingID` must be one.
    ///   - target: the meal's macro target. If nil, the meal's own current total
    ///             is used as target (i.e. "keep it as it was").
    ///   - candidates: restrict the search (e.g. to fridge contents for
    ///                 "replace with something I have"). If nil, uses the whole
    ///                 database filtered to the missing ingredient's group.
    ///   - limit: max offers to return (spec: 3–5).
    public func suggestions(forMissing missingID: String,
                            in meal: [RecipeLine],
                            target: MacroVector? = nil,
                            candidates: [Ingredient]? = nil,
                            limit: Int = 5) throws -> [SubstitutionSuggestion] {
        guard let missing = database.ingredient(id: missingID) else {
            throw MealPrepError.unknownIngredient(missingID)
        }
        guard let missingLine = meal.first(where: { $0.ingredientID == missingID }) else {
            throw MealPrepError.unknownIngredient(missingID)
        }

        // Remainder R: every line except the missing one.
        let remainder = try MacroVector.sum(
            meal.filter { $0.ingredientID != missingID }.map { line in
                guard let ing = database.ingredient(id: line.ingredientID) else {
                    throw MealPrepError.unknownIngredient(line.ingredientID)
                }
                return ing.macros(forGrams: line.baseRawGrams)
            }
        )

        // Target T: explicit, else reconstruct the meal's original total.
        let effectiveTarget: MacroVector
        if let target {
            effectiveTarget = target
        } else {
            effectiveTarget = remainder + missing.macros(forGrams: missingLine.baseRawGrams)
        }
        let need = effectiveTarget - remainder

        // Candidate pool.
        let pool: [Ingredient]
        if let candidates {
            // Explicit pool ("from my fridge"): still exclude the missing item
            // itself and any ultra-processed entries.
            pool = candidates.filter { $0.id != missingID && $0.isWholeFood }
        } else {
            // Same functional group, whole-food, excluding the missing item.
            pool = database.ingredients(in: missing.group)
                .filter { $0.id != missingID && $0.isWholeFood }
        }

        let offers = pool.map { candidate -> SubstitutionSuggestion in
            let grams = solveGrams(substitute: candidate, need: need, target: effectiveTarget)
            let resulting = remainder + candidate.macros(forGrams: grams)
            let delta = MacroDelta(target: effectiveTarget, actual: resulting)
            return SubstitutionSuggestion(
                substitute: candidate,
                grams: grams,
                resultingMeal: resulting,
                delta: delta,
                withinTolerance: delta.isWithinTolerance(tolerance, enforcing: enforced),
                score: delta.rmsFractionalError(over: enforced),
                tiebreakScore: delta.rmsFractionalError
            )
        }

        // Rank: in-tolerance first, then by enforced-macro fit, then overall fit.
        return offers
            .sorted { lhs, rhs in
                if lhs.withinTolerance != rhs.withinTolerance {
                    return lhs.withinTolerance && !rhs.withinTolerance
                }
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.tiebreakScore < rhs.tiebreakScore
            }
            .prefix(limit)
            .map { $0 }
    }
}
