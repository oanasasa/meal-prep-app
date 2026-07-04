import SwiftUI
import SwiftData
import UserNotifications

/// Tab shell. Shows a 3-screen onboarding flow on first launch (no plan yet);
/// once a `TrainerPlanEntity` exists, hands it down to the four tabs. Also owns
/// notification setup and deep-link routing (tapping a cook-session or
/// evening-nudge notification opens Cook Mode directly; the grocery
/// notification opens the grocery list).
struct RootView: View {
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
                OnboardingView()
            }
        }
    }
}
