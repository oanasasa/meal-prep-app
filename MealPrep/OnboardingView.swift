import SwiftUI
import SwiftData
import MealPrepCore

/// First-run setup: enter macros, set schedule, done. Exactly 3 screens —
/// she's tired, this should take under a minute and every field is editable
/// again later in the Plan tab, so nothing here needs to be perfect.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var page = 0

    // Mirrors TrainerPlanEntity's own defaults, so skipping straight through
    // still produces a sensible starting plan.
    @State private var dailyKcal: Double = 1600
    @State private var dailyProtein: Double = 130
    @State private var dailyCarbs: Double = 150
    @State private var dailyFat: Double = 50
    @State private var mealsPerDay: Int = 4
    @State private var gymThursday = false
    @State private var husbandMultiplier: Double = 1.4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                macrosPage.tag(0)
                schedulePage.tag(1)
                donePage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            navigationBar
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Page 1: Macros

    private var macrosPage: some View {
        OnboardingPage(icon: "target", title: "Your Macros",
                       subtitle: "Enter the daily targets from your trainer's plan. You can change these anytime in Plan.") {
            VStack(spacing: 14) {
                macroField("Calories", value: $dailyKcal, unit: "kcal")
                macroField("Protein", value: $dailyProtein, unit: "g")
                macroField("Carbs", value: $dailyCarbs, unit: "g")
                macroField("Fat", value: $dailyFat, unit: "g")

                Picker("Meals per day", selection: $mealsPerDay) {
                    ForEach([3, 4, 5], id: \.self) { Text("\($0) meals").tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
            }
        }
    }

    private func macroField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            TextField(label, value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 90)
                .minimumScaleFactor(0.5)
            Text(unit).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Page 2: Schedule

    private var schedulePage: some View {
        OnboardingPage(icon: "calendar.badge.clock", title: "Your Schedule",
                       subtitle: "Gym is Monday, Wednesday, Friday by default — Thursday is optional and shifts your third cook session.") {
            VStack(spacing: 14) {
                Toggle(isOn: $gymThursday) {
                    Label("Going to the gym Thursday", systemImage: "figure.strengthtraining.traditional")
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    Label("Husband portions", systemImage: "person.2.fill").font(.subheadline.weight(.semibold))
                    Stepper(value: $husbandMultiplier, in: 1.0...2.0, step: 0.05) {
                        Text("Multiplier ×\(husbandMultiplier, specifier: "%.2f")")
                    }
                    Text("He eats the same meals, scaled up.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Page 3: Done

    private var donePage: some View {
        OnboardingPage(icon: "checkmark.seal.fill", title: "You're All Set",
                       subtitle: "Rolling 2-day batch cooking: we'll tell you when it's time to cook, remind you about supplements and water, and help you swap an ingredient the moment the store's out of it.", iconColor: .green) {
            VStack(alignment: .leading, spacing: 10) {
                bullet("timer", "Cook sessions land on Sunday, Tuesday, and Thursday or Friday — never more than 2 days of food at once.")
                bullet("arrow.triangle.2.circlepath", "Missing an ingredient? Substitute in one tap, ranked to keep your macros on target.")
                bullet("refrigerator.fill", "Track your fridge and restock after shopping — we'll flag anything that affects your plan.")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
            }
            Spacer()
            if page < 2 {
                Button("Continue") { withAnimation { page += 1 } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Get Started") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
            }
        }
        .padding()
    }

    private func finish() {
        let plan = TrainerPlanEntity(dailyKcal: dailyKcal, dailyProtein: dailyProtein,
                                     dailyCarbs: dailyCarbs, dailyFat: dailyFat,
                                     mealsPerDay: mealsPerDay, gymThursday: gymThursday,
                                     husbandMultiplier: husbandMultiplier)
        context.insert(plan)
        try? context.save()
    }
}

/// Shared chrome for one onboarding page: icon, title, subtitle, and content.
private struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconColor: Color = .accentColor
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(iconColor)
                    .padding(.top, 40)
                Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                content
                    .padding(.horizontal)
                Spacer(minLength: 20)
            }
        }
    }
}
