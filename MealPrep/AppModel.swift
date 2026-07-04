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
    let cookPlanBuilder: CookPlanBuilder
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
            self.cookPlanBuilder = CookPlanBuilder(database: db, portioner: port)
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
            self.cookPlanBuilder = CookPlanBuilder(database: empty, portioner: port)
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

    func profiles(for plan: TrainerPlanEntity) -> [Profile] { [plan.herProfile, plan.husbandProfile] }

    /// Cook Mode's merged plan for a specific session in this week.
    func cookPlan(sessionID: String, week: VariantWeek, plan: TrainerPlanEntity) -> CookPlan? {
        guard let session = week.cookSessions.first(where: { $0.id == sessionID }) else { return nil }
        return cookPlanBuilder.plan(for: session, week: week, profiles: profiles(for: plan))
    }

    /// Everything the week needs, aggregated — a lightweight stand-in for the
    /// full fridge/restock grocery flow (Phase 3 remainder).
    func groceryItems(for plan: TrainerPlanEntity) -> [GroceryItem] {
        guard let week = variantWeek(for: plan) else { return [] }
        return GroceryListBuilder.build(for: week, profiles: profiles(for: plan),
                                        portioner: portioner, database: database)
    }

    /// Substitutes for a missing ingredient in a specific meal, targeting that
    /// meal's per-plan macro target. When `useFridge` is true, only fresh
    /// (non-expired) fridge stock is offered instead of the same food-group
    /// default — "replace with something I have."
    func suggestions(forMissing id: String,
                     lines: [RecipeLine],
                     target: MacroVector,
                     fridge: FridgeInventory? = nil) -> [SubstitutionSuggestion] {
        let candidates = fridge.map { $0.freshIngredients(database: database) }
        return (try? engine.suggestions(forMissing: id, in: lines, target: target,
                                        candidates: candidates, limit: 5)) ?? []
    }

    // MARK: - Fridge / restock (Phase 3 remainder)

    func fridgeInventory(from items: [FridgeItemEntity]) -> FridgeInventory {
        FridgeInventory(items: items.map(\.asFridgeItem))
    }

    /// Which meals this week would be affected if `ingredientID` is missing.
    func affectedMeals(missingIngredientID: String, plan: TrainerPlanEntity) -> [AffectedMeal] {
        guard let week = variantWeek(for: plan) else { return [] }
        return RestockPlanner.affectedMeals(missingIngredientID: missingIngredientID, in: week)
    }

    /// "Switch the whole day to a variant that's in the fridge" — the seed
    /// doc's fallback when a substitution alone won't save the plan.
    func variantFallback(awayFrom variantID: String, fridge: FridgeInventory) -> VariantFitScore? {
        VariantFallback.suggestAlternative(to: variantID, among: variants.all, fridge: fridge)
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
