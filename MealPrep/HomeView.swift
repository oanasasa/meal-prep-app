import SwiftUI
import SwiftData
import MealPrepCore

/// Context passed to the substitution sheet.
struct SubstituteContext: Identifiable {
    let id = UUID()
    let title: String
    let lines: [RecipeLine]
    let target: MacroVector
}

struct HomeView: View {
    let plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var logs: [DailyLogEntity]
    @State private var substitute: SubstituteContext?

    private var today: VariantDay? { model.todaysVariantDay(for: plan) }
    private var todayOffset: Int { AppModel.todayOffset() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let err = model.loadError { errorCard(err) }
                    if let week = model.variantWeek(for: plan) { cookCountdownCard(week) }
                    dayTotalCard
                    ForEach(today?.meals ?? []) { meal in mealCard(meal) }
                    substituteButton
                    supplementsCard
                    waterCard
                    Text("All grams are raw weights.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(dayTitle)
            .sheet(item: $substitute) { ctx in
                SubstituteView(title: ctx.title, lines: ctx.lines, target: ctx.target)
            }
        }
    }

    private var dayTitle: String {
        "Today · " + CookScheduler.weekdayName(forOffset: todayOffset)
    }

    // MARK: - Meals

    private var dayTotalCard: some View {
        let total = MacroVector.sum(today?.meals.map(\.herMacros) ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY · \(today?.variantID ?? "—")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("target ~\(Fmt.g(plan.dailyKcal)) kcal")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            MacroSummary(macros: total)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func mealCard(_ meal: PlannedVariantMeal) -> some View {
        Button {
            substitute = SubstituteContext(title: meal.meal.name,
                                           lines: meal.meal.lines,
                                           target: meal.herMacros)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(meal.meal.mealType.displayName.uppercased())
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if meal.meal.freshOnly {
                        Label("fresh", systemImage: "leaf.fill").font(.caption2).foregroundStyle(.green)
                    } else if meal.cookSessionID != nil {
                        Label("batch", systemImage: "flame.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                Text(meal.meal.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                MacroSummary(macros: meal.herMacros)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var substituteButton: some View {
        Button {
            if let first = today?.meals.first {
                substitute = SubstituteContext(title: first.meal.name,
                                               lines: first.meal.lines,
                                               target: first.herMacros)
            }
        } label: {
            Label("Something's missing → substitute", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled((today?.meals.isEmpty ?? true))
    }

    private func cookCountdownCard(_ week: VariantWeek) -> some View {
        let next = week.cookSessions.first { $0.cookDayOffset >= todayOffset }
        return HStack(spacing: 14) {
            Image(systemName: next == nil ? "checkmark.circle.fill" : "timer")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.green, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Next cook session").font(.subheadline).foregroundStyle(.secondary)
                if let next {
                    Text("\(next.title) · \(CookScheduler.weekdayName(forOffset: next.cookDayOffset))")
                        .font(.headline)
                    Text("Cooks for " + next.coversDayOffsets
                        .map { CookScheduler.weekdayName(forOffset: $0) }.joined(separator: " + "))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("All cooked — nothing to prep today").font(.headline)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Supplements

    private var supplementsCard: some View {
        let log = todayLog()
        return VStack(alignment: .leading, spacing: 10) {
            Text("SUPPLEMENTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Reminders.supplements) { supp in
                let taken = log?.isTaken(supp.id) ?? false
                Button {
                    ensureLog().toggle(supp.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(taken ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(supp.name).font(.subheadline)
                                .strikethrough(taken).foregroundStyle(taken ? .secondary : .primary)
                            Text(reminderTimeText(supp)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func reminderTimeText(_ supp: SupplementReminder) -> String {
        let t = Reminders.time(for: supp, dayOffset: todayOffset, thursdayGym: plan.gymThursday)
        return String(format: "%02d:%02d · %@", t.hour, t.minute, supp.note)
    }

    // MARK: - Water

    private var waterCard: some View {
        let log = todayLog()
        let ml = log?.waterMilliliters ?? 0
        let goal = Reminders.hydrationGoalMilliliters
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Water", systemImage: "drop.fill").font(.headline).foregroundStyle(.blue)
                Spacer()
                Text("\(Double(ml)/1000, specifier: "%.1f") / \(goal/1000) L")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(ml), total: Double(goal)).tint(.blue)
            HStack {
                Button { ensureLog().waterMilliliters = max(0, ml - 250) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                Spacer()
                Text("+250 ml per glass").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button { ensureLog().waterMilliliters = min(goal + 1000, ml + 250) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
            .tint(.blue)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Log helpers

    private func todayLog() -> DailyLogEntity? {
        let key = DailyLogEntity.key()
        return logs.first { $0.dayKey == key }
    }

    @discardableResult
    private func ensureLog() -> DailyLogEntity {
        if let existing = todayLog() { return existing }
        let log = DailyLogEntity(dayKey: DailyLogEntity.key())
        context.insert(log)
        return log
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
