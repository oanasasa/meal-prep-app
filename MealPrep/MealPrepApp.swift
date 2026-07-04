import SwiftUI
import SwiftData

@main
struct MealPrepApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        // Local-first persistence: the trainer plan + per-day tracking + the
        // editable plan (variants/meals/ingredients, seeded from bundled JSON).
        .modelContainer(for: [TrainerPlanEntity.self, DailyLogEntity.self, CookSessionLogEntity.self,
                             FridgeItemEntity.self, VariantEntity.self, MealEntity.self,
                             VariantChangeEntity.self, IngredientEntity.self])
    }
}
