import SwiftUI
import SwiftData

/// Tab shell. Seeds a default trainer plan on first launch, then hands the live
/// `TrainerPlanEntity` down to the three tabs.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var plans: [TrainerPlanEntity]
    @State private var selectedTab = 0

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
                    PlanEntryView(plan: plan)
                        .tabItem { Label("Plan", systemImage: "slider.horizontal.3") }
                        .tag(2)
                }
                .task {
                    // Local notifications for supplements + hydration.
                    if await ReminderScheduler.requestAuthorization() {
                        await ReminderScheduler.reschedule(thursdayGym: plan.gymThursday)
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
