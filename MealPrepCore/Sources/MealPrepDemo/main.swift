import Foundation
import MealPrepCore

// A tiny command-line demo that runs the real substitution engine against the
// bundled database so the "show me the math" numbers are engine output, not
// hand calculations. Run with: swift run mealprep-demo

let db = try IngredientDatabase.loadBundled()
let engine = SubstitutionEngine(database: db)   // enforces kcal + protein within ±5%

// Her lunch: chicken & rice bowl, on the trainer's plan.
let meal: [RecipeLine] = [
    .init(ingredientID: "chicken-breast", baseRawGrams: 150),
    .init(ingredientID: "white-rice-dry", baseRawGrams: 75),
    .init(ingredientID: "broccoli", baseRawGrams: 100),
    .init(ingredientID: "olive-oil", baseRawGrams: 10)
]

func fmt(_ v: Double) -> String { String(format: "%.0f", v) }
func signed(_ v: Double) -> String { (v >= 0 ? "+" : "") + String(format: "%.0f", v) }

func macroLine(_ m: MacroVector) -> String {
    "\(fmt(m.kcal)) kcal · \(fmt(m.protein))P · \(fmt(m.carbs))C · \(fmt(m.fat))F"
}

let calc = PortionCalculator(database: db)
let her = Profile(id: "her", name: "Her", dailyTarget: .init(kcal: 1600, protein: 130, carbs: 150, fat: 50))
let target = try calc.totalMacros(for: meal, profile: her)

print("MEAL: chicken & rice bowl (her portion)")
print("  target: \(macroLine(target))\n")
print("The store had no chicken breast. Substitutes (ranked), each re-gram'd to")
print("hold the whole meal within ±5% on kcal + protein:\n")

let suggestions = try engine.suggestions(forMissing: "chicken-breast", in: meal, limit: 5)
for (i, s) in suggestions.enumerated() {
    let d = s.delta.absolute
    let flag = s.withinTolerance ? "✅ within ±5%" : "⚠︎ outside ±5%"
    print("  \(i + 1). \(s.substitute.name)  →  \(fmt(s.grams)) g raw   [\(flag)]")
    print("       meal now: \(macroLine(s.resultingMeal))")
    print("       delta vs target: \(signed(d.kcal)) kcal, \(signed(d.protein))g protein, "
          + "\(signed(d.carbs))g carb, \(signed(d.fat))g fat")
}

print("\n\"Replace with something I have\" — fridge = { cod, greek yogurt }:")
let fridge = ["cod", "greek-yogurt-0"].compactMap { db.ingredient(id: $0) }
for s in try engine.suggestions(forMissing: "chicken-breast", in: meal, candidates: fridge) {
    let flag = s.withinTolerance ? "✅" : "⚠︎"
    print("  \(flag) \(s.substitute.name): \(fmt(s.grams)) g  → \(macroLine(s.resultingMeal))")
}
