import Foundation
import Observation
import MealPrepCore

/// App-wide, read-only resources loaded once: the ingredient DB, recipe library,
/// and the engines built on them. The editable state (the trainer plan) lives in
/// SwiftData; the weekly plan is regenerated from it on demand.
@Observable
final class AppModel {
    let database: IngredientDatabase
    let library: RecipeLibrary
    let variants: VariantLibrary
    let calculator: PortionCalculator
    let engine: SubstitutionEngine
    let generator: WeeklyPlanGenerator
    let portioner: VariantPortioner
    let planner: VariantRotationPlanner
    let loadError: String?

    init() {
        do {
            let db = try IngredientDatabase.loadBundled()
            let lib = try RecipeLibrary.loadBundled()
            let vars = try VariantLibrary.loadBundled()
            let calc = PortionCalculator(database: db)
            let port = VariantPortioner(calculator: calc)
            self.database = db
            self.library = lib
            self.variants = vars
            self.calculator = calc
            self.engine = SubstitutionEngine(database: db)
            self.generator = WeeklyPlanGenerator(library: lib, calculator: calc)
            self.portioner = port
            self.planner = VariantRotationPlanner(library: vars, portioner: port)
            self.loadError = nil
        } catch {
            let empty = IngredientDatabase(ingredients: [])
            let calc = PortionCalculator(database: empty)
            let port = VariantPortioner(calculator: calc)
            self.database = empty
            self.library = RecipeLibrary(recipes: [])
            self.variants = VariantLibrary(variants: [])
            self.calculator = calc
            self.engine = SubstitutionEngine(database: empty)
            self.generator = WeeklyPlanGenerator(library: RecipeLibrary(recipes: []), calculator: calc)
            self.portioner = port
            self.planner = VariantRotationPlanner(library: VariantLibrary(variants: []), portioner: port)
            self.loadError = String(describing: error)
        }
    }

    // MARK: - Variant plan (the trainer's actual "Oana 1900" plan)

    func variantWeek(for plan: TrainerPlanEntity) -> VariantWeek? {
        try? planner.plan(gymThursday: plan.gymThursday,
                          weekStartMonday: Self.currentMonday(),
                          startIndex: plan.planSeed)
    }

    func todaysVariantDay(for plan: TrainerPlanEntity) -> VariantDay? {
        variantWeek(for: plan)?.day(Self.todayOffset())
    }

    func recipe(_ id: String) -> Recipe? { library.recipe(id: id) }
    func ingredient(_ id: String) -> Ingredient? { database.ingredient(id: id) }

    /// Substitutes for a missing ingredient in a specific meal, targeting that
    /// meal's per-plan macro target.
    func suggestions(forMissing id: String,
                     lines: [RecipeLine],
                     target: MacroVector) -> [SubstitutionSuggestion] {
        (try? engine.suggestions(forMissing: id, in: lines, target: target, limit: 5)) ?? []
    }

    // MARK: - Calendar helpers (Monday = 0 … Sunday = 6)

    static func todayOffset(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        // Calendar weekday: 1 = Sunday … 7 = Saturday. Map to Monday-based.
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func currentMonday(_ date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -todayOffset(date, calendar: calendar), to: start) ?? start
    }
}
