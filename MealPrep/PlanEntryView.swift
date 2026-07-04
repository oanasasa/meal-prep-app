import SwiftUI
import SwiftData
import MealPrepCore

/// Manual trainer-plan entry (Feature 1) + schedule toggles. Edits write straight
/// through to the SwiftData model, so the plan is persisted automatically.
struct PlanEntryView: View {
    @Bindable var plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model
    @Query(sort: \VariantEntity.sortOrder) private var variantEntities: [VariantEntity]
    @State private var showGroceryList = false

    /// Active variants whose day total (at the CURRENTLY-TYPED targets, before
    /// saving) drifts outside ±5% of the new daily kcal target — "the trainer
    /// changed the numbers, not the food," so this flags what to go adjust.
    private var driftingVariants: [(name: String, kcal: Double, deltaKcal: Double)] {
        variantEntities.filter(\.isActive).compactMap { variant in
            guard let day = try? model.portioner.dayMacros(for: variant.asDayVariant()) else { return nil }
            let delta = MacroDelta(target: plan.daily, actual: day)
            guard !delta.isWithinTolerance(0.05, enforcing: [.kcal]) else { return nil }
            return (variant.name, day.kcal, delta.absolute.kcal)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily targets (Her)") {
                    macroField("Calories", value: $plan.dailyKcal, unit: "kcal")
                    macroField("Protein", value: $plan.dailyProtein, unit: "g")
                    macroField("Carbs", value: $plan.dailyCarbs, unit: "g")
                    macroField("Fat", value: $plan.dailyFat, unit: "g")

                    if !driftingVariants.isEmpty {
                        driftWarning
                    }
                }

                Section("Meals per day") {
                    Picker("Meals", selection: $plan.mealsPerDay) {
                        ForEach([3, 4, 5], id: \.self) { Text("\($0) meals").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    perMealPreview
                }

                Section("Schedule") {
                    Toggle("Going to the gym Thursday", isOn: $plan.gymThursday)
                    Text(plan.gymThursday
                         ? "Third cook session is on Friday."
                         : "Third cook session is on Thursday.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Husband portions") {
                    Stepper(value: $plan.husbandMultiplier, in: 1.0...2.0, step: 0.05) {
                        Text("Multiplier ×\(plan.husbandMultiplier, specifier: "%.2f")")
                    }
                    Text("His day ≈ \(Fmt.g(plan.dailyKcal * plan.husbandMultiplier)) kcal · "
                         + "\(Fmt.g(plan.dailyProtein * plan.husbandMultiplier))g protein")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Weekly plan") {
                    Button {
                        plan.planSeed &+= 1
                    } label: {
                        Label("Shift variant rotation", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Text("Rotates which trainer variant (V1–V4) starts the week.")
                        .font(.caption).foregroundStyle(.secondary)

                    Button { showGroceryList = true } label: {
                        Label("View grocery list", systemImage: "cart.fill")
                    }

                    NavigationLink {
                        VariantsListView(plan: plan)
                    } label: {
                        Label("Edit meal plan variants", systemImage: "square.and.pencil")
                    }
                }

                Section("Notification times") {
                    timePicker("Grocery list (Saturday)", hour: $plan.groceryHour, minute: $plan.groceryMinute)
                    timePicker("Morning meal summary", hour: $plan.morningSummaryHour, minute: $plan.morningSummaryMinute)
                    timePicker("Evening cook nudge", hour: $plan.eveningNudgeHour, minute: $plan.eveningNudgeMinute)
                    Text("Cook-session reminders and supplement times use the trainer's defaults for now.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Your Plan")
            .sheet(isPresented: $showGroceryList) { GroceryListView(plan: plan) }
            .onChange(of: plan.gymThursday) { _, newValue in
                // Thursday gym affects the cook schedule, creatine timing, and
                // which sessions the evening nudges attach to.
                Task {
                    await ReminderScheduler.reschedule(thursdayGym: newValue)
                    await MealNotificationScheduler.reschedule(model: model, plan: plan)
                }
            }
            .onChange(of: plan.planSeed) { _, _ in
                Task { await MealNotificationScheduler.reschedule(model: model, plan: plan) }
            }
            .onChange(of: plan.groceryHour) { _, _ in rescheduleMealNotifications() }
            .onChange(of: plan.groceryMinute) { _, _ in rescheduleMealNotifications() }
            .onChange(of: plan.morningSummaryHour) { _, _ in rescheduleMealNotifications() }
            .onChange(of: plan.morningSummaryMinute) { _, _ in rescheduleMealNotifications() }
            .onChange(of: plan.eveningNudgeHour) { _, _ in rescheduleMealNotifications() }
            .onChange(of: plan.eveningNudgeMinute) { _, _ in rescheduleMealNotifications() }
        }
    }

    private func rescheduleMealNotifications() {
        Task { await MealNotificationScheduler.reschedule(model: model, plan: plan) }
    }

    private func timePicker(_ label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            DatePicker("", selection: Binding(
                get: {
                    Calendar.current.date(from: DateComponents(hour: hour.wrappedValue, minute: minute.wrappedValue)) ?? Date()
                },
                set: { newDate in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                    hour.wrappedValue = c.hour ?? 0
                    minute.wrappedValue = c.minute ?? 0
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
    }

    private var driftWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("These variants now drift outside ±5% of your new target:",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            ForEach(driftingVariants, id: \.name) { drift in
                Text("\(drift.name): \(Fmt.g(drift.kcal)) kcal (\(Fmt.signed(drift.deltaKcal)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 90)
                .minimumScaleFactor(0.5)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private var perMealPreview: some View {
        let split = TrainerPlan.defaultSplit(daily: plan.daily, mealsPerDay: plan.mealsPerDay)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(zip(split.mealTypes, split.mealTargets).enumerated()), id: \.offset) { _, pair in
                HStack {
                    Text(pair.0.displayName).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Fmt.g(pair.1.kcal)) kcal · \(Fmt.g(pair.1.protein))g P")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }
}
