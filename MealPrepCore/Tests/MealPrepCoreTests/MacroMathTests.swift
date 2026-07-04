import Testing
@testable import MealPrepCore

@Suite("Macro math")
struct MacroMathTests {

    @Test func vectorArithmetic() {
        let a = MacroVector.v(100, 10, 5, 2)
        let b = MacroVector.v(50, 4, 3, 1)
        #expect(a + b == .v(150, 14, 8, 3))
        #expect(a - b == .v(50, 6, 2, 1))
        #expect(a * 2 == .v(200, 20, 10, 4))
    }

    @Test func atwaterEnergy() {
        // 4*30 + 4*40 + 9*10 = 370
        expectClose(MacroVector.v(0, 30, 40, 10).atwaterKcal, 370, 1e-9)
    }

    @Test func fractionalDelta() {
        let d = MacroDelta(target: .v(500, 40, 50, 15), actual: .v(520, 42, 48, 15))
        #expect(d.absolute == .v(20, 2, -2, 0))
        expectClose(d.fractional.kcal, 0.04)     // +4%
        expectClose(d.fractional.protein, 0.05)  // +5%
        expectClose(d.fractional.carbs, -0.04)   // -4%
    }

    @Test func toleranceCheck() {
        let target = MacroVector.v(500, 40, 50, 15)
        // +4% / +5% / -4% / 0% — all within 5%.
        #expect(MacroDelta(target: target, actual: .v(520, 42, 48, 15)).isWithinTolerance(0.05))

        // Protein +10% fails overall, passes if only kcal is enforced.
        let proteinHigh = MacroDelta(target: target, actual: .v(515, 44, 50, 15))
        #expect(!proteinHigh.isWithinTolerance(0.05))
        #expect(proteinHigh.isWithinTolerance(0.05, enforcing: [.kcal]))
    }

    @Test func zeroTargetIsInfiniteError() {
        let d = MacroDelta(target: .zero, actual: .v(10, 0, 0, 0))
        #expect(d.fractional.kcal.isInfinite)
        #expect(!d.isWithinTolerance(0.05))
    }

    @Test func rmsFractionalError() {
        // +10% on every macro -> rms 0.10.
        let d = MacroDelta(target: .v(100, 100, 100, 100), actual: .v(110, 110, 110, 110))
        expectClose(d.rmsFractionalError, 0.10)
        // Restricted to two fields, same 10% each -> still 0.10.
        expectClose(d.rmsFractionalError(over: [.kcal, .protein]), 0.10)
    }
}
