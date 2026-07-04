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
        // Local-first persistence: the trainer plan + per-day tracking.
        .modelContainer(for: [TrainerPlanEntity.self, DailyLogEntity.self])
    }
}
