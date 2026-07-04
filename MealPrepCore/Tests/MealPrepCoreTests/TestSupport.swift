import Testing
@testable import MealPrepCore

/// Approximate-equality helper (Swift Testing has no built-in accuracy matcher).
func expectClose(_ a: Double, _ b: Double, _ eps: Double = 1e-9,
                 _ comment: Comment? = nil,
                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(a - b) <= eps, comment ?? "\(a) is not within \(eps) of \(b)",
            sourceLocation: sourceLocation)
}

extension MacroVector {
    /// Convenience for building test vectors.
    static func v(_ kcal: Double, _ p: Double, _ c: Double, _ f: Double) -> MacroVector {
        MacroVector(kcal: kcal, protein: p, carbs: c, fat: f)
    }
}
