import SwiftUI
import SwiftData
import UserNotifications

/// Tab shell. Seeds a default trainer plan on first launch, then hands the live
/// `TrainerPlanEntity` down to the three tabs. Also owns notification setup and
/// deep-link routing (tapping a cook-session or evening-nudge notification
/// opens Cook Mode directly; the grocery notification opens the grocery list).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query private var plans: [TrainerPlanEntity]
    @State private var selectedTab = 0
    @State private var router = NotificationRouter()
    @State private var activeRoute: NotificationRoute?

    var body: some View {
        Group {
            if let plan = plans.first {
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
            } else {
                ProgressView().task { seedIfNeeded() }
            }
        }
    }

    private func seedIfNeeded() {
        guard plans.isEmpty else { return }
        context.insert(TrainerPlanEntity())
        try? context.save()
    }
}
