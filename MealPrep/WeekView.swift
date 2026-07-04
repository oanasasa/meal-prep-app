import SwiftUI
import MealPrepCore

/// The week as a rotation of trainer variants, grouped by day, plus the rolling
/// 2-day cook-session summary.
struct WeekView: View {
    let plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model

    private var week: VariantWeek? { model.variantWeek(for: plan) }

    var body: some View {
        NavigationStack {
            List {
                if let week {
                    cookSessionsSection(week)
                    ForEach(week.days) { day in daySection(day) }
                } else {
                    Text("Couldn't build this week's plan.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("This Week")
        }
    }

    private func cookSessionsSection(_ week: VariantWeek) -> some View {
        Section("Cook sessions (rolling 2-day)") {
            ForEach(week.cookSessions) { session in
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.title) · \(CookScheduler.weekdayName(forOffset: session.cookDayOffset))")
                            .font(.subheadline.weight(.semibold))
                        Text("cooks batch meals for " + session.coversDayOffsets
                            .map { CookScheduler.weekdayName(forOffset: $0) }.joined(separator: " + "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if plan.gymThursday {
                Label("Thursday gym on — 3rd session moved to Friday",
                      systemImage: "figure.strengthtraining.traditional")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func daySection(_ day: VariantDay) -> some View {
        Section {
            ForEach(day.meals) { meal in mealRow(meal) }
        } header: {
            HStack {
                Text(CookScheduler.weekdayName(forOffset: day.dayOffset))
                Text("· \(day.variantID)").foregroundStyle(.tint)
                Spacer()
                if let session = CookScheduler.session(forDayOffset: day.dayOffset, gymThursday: plan.gymThursday) {
                    Text("cook: \(session.title)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func mealRow(_ meal: PlannedVariantMeal) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(meal.meal.mealType.displayName)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if meal.meal.batchSafe {
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                    } else {
                        Image(systemName: "leaf.fill").font(.caption2).foregroundStyle(.green)
                    }
                }
                Text(meal.meal.name).font(.body)
            }
            Spacer()
            Text("\(Fmt.g(meal.herMacros.kcal)) kcal\n\(Fmt.g(meal.herMacros.protein))g P")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}
