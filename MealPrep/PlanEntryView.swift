import SwiftUI
import SwiftData
import MealPrepCore

/// Manual trainer-plan entry (Feature 1) + schedule toggles. Edits write straight
/// through to the SwiftData model, so the plan is persisted automatically.
struct PlanEntryView: View {
    @Bindable var plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily targets (Her)") {
                    macroField("Calories", value: $plan.dailyKcal, unit: "kcal")
                    macroField("Protein", value: $plan.dailyProtein, unit: "g")
                    macroField("Carbs", value: $plan.dailyCarbs, unit: "g")
                    macroField("Fat", value: $plan.dailyFat, unit: "g")
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
                }
            }
            .navigationTitle("Your Plan")
            .onChange(of: plan.gymThursday) { _, newValue in
                // Thursday gym affects both the cook schedule and creatine timing.
                Task { await ReminderScheduler.reschedule(thursdayGym: newValue) }
            }
        }
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 90)
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
