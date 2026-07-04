import Foundation

/// A 4-dimensional nutrition vector. Every quantity in the app — an ingredient's
/// per-100g profile, a meal total, a daily target — is represented the same way,
/// which keeps the substitution math to plain vector arithmetic.
///
/// `kcal` is stored explicitly (from the source database) rather than always
/// derived, because real food labels don't exactly obey the 4/4/9 Atwater rule
/// (fibre, sugar alcohols, rounding). `atwaterKcal` is available when you want
/// the derived value.
public struct MacroVector: Equatable, Hashable, Codable, Sendable {
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

    public static let zero = MacroVector(kcal: 0, protein: 0, carbs: 0, fat: 0)

    /// Atwater factors: protein 4, carbs 4, fat 9 kcal/g.
    public var atwaterKcal: Double { protein * 4 + carbs * 4 + fat * 9 }

    // MARK: - Vector arithmetic

    public static func + (lhs: MacroVector, rhs: MacroVector) -> MacroVector {
        MacroVector(kcal: lhs.kcal + rhs.kcal,
                    protein: lhs.protein + rhs.protein,
                    carbs: lhs.carbs + rhs.carbs,
                    fat: lhs.fat + rhs.fat)
    }

    public static func - (lhs: MacroVector, rhs: MacroVector) -> MacroVector {
        MacroVector(kcal: lhs.kcal - rhs.kcal,
                    protein: lhs.protein - rhs.protein,
                    carbs: lhs.carbs - rhs.carbs,
                    fat: lhs.fat - rhs.fat)
    }

    public static func * (lhs: MacroVector, scalar: Double) -> MacroVector {
        MacroVector(kcal: lhs.kcal * scalar,
                    protein: lhs.protein * scalar,
                    carbs: lhs.carbs * scalar,
                    fat: lhs.fat * scalar)
    }

    /// The four components in a fixed order, handy for iterating in the solver.
    public var components: [Double] { [kcal, protein, carbs, fat] }

    public static func sum(_ vectors: [MacroVector]) -> MacroVector {
        vectors.reduce(.zero, +)
    }
}

/// The comparison of an achieved meal against a target, expressed both in
/// absolute deltas (for the "−12 kcal, +2g protein" chips) and as signed
/// fractions of the target (for the ±5% tolerance check).
public struct MacroDelta: Equatable, Sendable {
    public let target: MacroVector
    public let actual: MacroVector

    public init(target: MacroVector, actual: MacroVector) {
        self.target = target
        self.actual = actual
    }

    /// actual − target. Positive = over target.
    public var absolute: MacroVector { actual - target }

    /// Signed fractional error per macro (actual − target) / target.
    /// A zero target maps to 0 when actual is also 0, otherwise `.infinity`
    /// so it is always treated as out-of-tolerance.
    public var fractional: MacroVector {
        func frac(_ a: Double, _ t: Double) -> Double {
            if t == 0 { return a == 0 ? 0 : .infinity }
            return (a - t) / t
        }
        return MacroVector(kcal: frac(actual.kcal, target.kcal),
                           protein: frac(actual.protein, target.protein),
                           carbs: frac(actual.carbs, target.carbs),
                           fat: frac(actual.fat, target.fat))
    }

    /// Root-mean-square of the fractional errors over `fields` — a single
    /// "how far off" number used to rank substitution candidates. Lower is
    /// better. Restricting to the enforced macros (kcal + protein) keeps the
    /// ranking focused on what the trainer pins, rather than the fat dimension
    /// that every lean swap misses.
    public func rmsFractionalError(over fields: Set<MacroField>) -> Double {
        guard !fields.isEmpty else { return 0 }
        let f = fractional
        let mean = fields.map { f[$0] * f[$0] }.reduce(0, +) / Double(fields.count)
        return mean.squareRoot()
    }

    /// RMS over all four macros.
    public var rmsFractionalError: Double {
        rmsFractionalError(over: MacroField.all)
    }

    /// True when every enforced macro is within `tolerance` (default 5%) of target.
    /// By default all four macros are enforced; pass a subset to relax (e.g. the
    /// trainer only pins kcal + protein hard).
    public func isWithinTolerance(_ tolerance: Double = 0.05,
                                   enforcing macros: Set<MacroField> = MacroField.all) -> Bool {
        let f = fractional
        return macros.allSatisfy { abs(f[$0]) <= tolerance }
    }
}

/// Selector for a single macro field, so callers can enforce a subset.
public enum MacroField: CaseIterable, Sendable {
    case kcal, protein, carbs, fat
    public static let all: Set<MacroField> = Set(MacroField.allCases)
}

public extension MacroVector {
    subscript(_ field: MacroField) -> Double {
        switch field {
        case .kcal: return kcal
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        }
    }
}
