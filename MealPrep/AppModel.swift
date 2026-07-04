import Foundation
import Observation
import SwiftData
import MealPrepCore

/// App-wide resources: the ingredient DB, recipe library, variant library, and
/// the engines built on them. `database` and `variants` start from the bundled
/// seed but become LIVE once `reload(customIngredients:variantEntities:)` is
/// called (RootView does this on launch and whenever the underlying SwiftData
/// rows change) — from then on every derived engine reflects the user's edits.
@Observable
final class AppModel {
    private(set) var database: IngredientDatabase
    private(set) var library: RecipeLibrary
    private(set) var variants: VariantLibrary
    private(set) var calculator: PortionCalculator
    private(set) var engine: SubstitutionEngine
    private(set) var generator: WeeklyPlanGenerator
    private(set) var portioner: VariantPortioner
    private(set) var planner: VariantRotationPlanner
    private(set) var cookPlanBuilder: CookPlanBuilder
    let loadError: String?

    init() {
        do {
            let db = try IngredientDatabase.loadBundled()
            let lib = try RecipeLibrary.loadBundled()
            let vars = try VariantLibrary.loadBundled()
            self.database = db
            self.library = lib
            self.variants = vars
            (self.calculator, self.engine, self.generator, self.portioner,
             self.planner, self.cookPlanBuilder) = Self.buildEngines(database: db, library: lib, variants: vars)
            self.loadError = nil
        } catch {
            let empty = IngredientDatabase(ingredients: [])
            let emptyLib = RecipeLibrary(recipes: [])
            let emptyVars = VariantLibrary(variants: [])
            self.database = empty
            self.library = emptyLib
            self.variants = emptyVars
            (self.calculator, self.engine, self.generator, self.portioner,
             self.planner, self.cookPlanBuilder) = Self.buildEngines(database: empty, library: emptyLib, variants: emptyVars)
            self.loadError = String(describing: error)
        }
    }

    /// Rebuilds every derived engine straight from SwiftData. Call this after
    /// ANY edit (meal grams, new ingredient, variant activate/deactivate,
    /// restore from history…) so the rest of the app immediately reflects it —
    /// there's no other cache-invalidation path, this is the single source of
    /// truth refresh. Custom ingredients merge with the bundled catalogue
    /// (custom IDs never collide with bundled ones — see `IngredientEntity.slug`);
    /// variants come entirely from SwiftData (seeded once from the bundled
    /// JSON, then authoritative — see `PlanDataSeeder`).
    func reload(context: ModelContext) {
        let customIngredients = (try? context.fetch(FetchDescriptor<IngredientEntity>())) ?? []
        let variantEntities = (try? context.fetch(FetchDescriptor<VariantEntity>())) ?? []
        reload(customIngredients: customIngredients, variantEntities: variantEntities)
    }

    func reload(customIngredients: [IngredientEntity], variantEntities: [VariantEntity]) {
        let bundledIngredients = (try? IngredientDatabase.loadBundled().all) ?? []
        let merged = bundledIngredients + customIngredients.map { $0.asIngredient() }
        let db = IngredientDatabase(ingredients: merged)

        let dayVariants = variantEntities
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.asDayVariant() }
        let vars = VariantLibrary(variants: dayVariants)

        self.database = db
        self.variants = vars
        (self.calculator, self.engine, self.generator, self.portioner,
         self.planner, self.cookPlanBuilder) = Self.buildEngines(database: db, library: library, variants: vars)
    }

    private static func buildEngines(database: IngredientDatabase, library: RecipeLibrary, variants: VariantLibrary)
        -> (PortionCalculator, SubstitutionEngine, WeeklyPlanGenerator, VariantPortioner,
            VariantRotationPlanner, CookPlanBuilder) {
        let calc = PortionCalculator(database: database)
        let port = VariantPortioner(calculator: calc)
        return (calc, SubstitutionEngine(database: database),
               WeeklyPlanGenerator(library: library, calculator: calc), port,
               VariantRotationPlanner(library: variants, portioner: port),
               CookPlanBuilder(database: database, portioner: port))
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
