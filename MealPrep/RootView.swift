import SwiftUI
import SwiftData
import UserNotifications

/// Tab shell. Shows a 3-screen onboarding flow on first launch (no plan yet);
/// once a `TrainerPlanEntity` exists, hands it down to the four tabs. Also owns
/// notification setup, deep-link routing, and keeps `AppModel`'s derived
/// engines in sync with the live (editable) variant/ingredient data.
///
/// Edits call `model.reload(context:)` directly at their save site for
/// immediate feedback; the count-based `.onChange` below is just a safety net
/// that catches additions/removals if some future screen forgets to.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query private var plans: [TrainerPlanEntity]
    @Query private var customIngredients: [IngredientEntity]
    @Query private var variantEntities: [VariantEntity]
    @State private var selectedTab = 0
    @State private var router = NotificationRouter()
    @State private var activeRoute: NotificationRoute?
    @State private var seeded = false

    var body: some View {
        Group {
            if seeded, let plan = plans.first {
                TabView(selection: $selectedTab) {
                    HomeView(plan: plan)
                        .tabItem { Label("Today", systemImage: "sun.max.fill") }
                        .tag(0)
                    WeekView(plan: plan)
                        .tabItem { Label("Week", systemImage: "calendar") }
                        .tag(1)
                    InventoryView(plan: plan)
                        .tabItem { Label("Fridge", systemImage: "refrigerator.fill") }
                        .tag(2)
                    PlanEntryView(plan: plan)
                        .tabItem { Label("Plan", systemImage: "slider.horizontal.3") }
                        .tag(3)
                }
                .task {
                    UNUserNotificationCenter.current().delegate = router
                    if await ReminderScheduler.requestAuthorization() {
                        await ReminderScheduler.reschedule(thursdayGym: plan.gymThursday)
                        await MealNotificationScheduler.reschedule(model: model, plan: plan)
                    }
                }
                .onChange(of: router.pendingRoute) { _, newValue in
                    guard let newValue else { return }
                    activeRoute = newValue
                    router.pendingRoute = nil
                }
                .fullScreenCover(item: $activeRoute) { route in
                    switch route {
                    case .cookMode(let sessionID):
                        CookModeView(sessionID: sessionID, plan: plan)
                    case .grocery:
                        GroceryListView(plan: plan)
                    }
                }
            } else if seeded {
                OnboardingView()
            } else {
                ProgressView().task {
                    PlanDataSeeder.seedIfNeeded(context: context)
                    model.reload(context: context)
                    seeded = true
                }
            }
        }
        .onChange(of: customIngredients.count) { _, _ in model.reload(context: context) }
        .onChange(of: variantEntities.count) { _, _ in model.reload(context: context) }
    }
}
