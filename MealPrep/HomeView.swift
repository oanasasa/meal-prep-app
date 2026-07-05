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

/// Wraps a cook session id so it can drive a `.sheet(item:)`. `weekStart` lets
/// the caller mark a session against a specific week — the Sunday prep card uses
/// it to record against the *upcoming* week, not the one that's ending.
struct CookModeContext: Identifiable {
    let id: String
    var weekStart: Date? = nil
}

struct HomeView: View {
    let plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var logs: [DailyLogEntity]
    @Query private var cookLogs: [CookSessionLogEntity]
    @State private var substitute: SubstituteContext?
    @State private var cookModeContext: CookModeContext?

    private var today: VariantDay? { model.todaysVariantDay(for: plan) }
    private var todayOffset: Int { AppModel.todayOffset() }

    /// The prep session the user would actually cook TODAY, the week it prepares,
    /// and whether it's already been marked cooked — the single source of truth
    /// for the home status, so it never *assumes* things are cooked. Sunday preps
    /// the *upcoming* week (the trainer's "Sunday prep" covers next Mon+Tue), so
    /// its cooked-state is tracked against next Monday, not the week that's ending.
    private struct TodayPrep {
        let session: CookSession
        let weekStart: Date
        let isCooked: Bool
    }

    private var todayPrep: TodayPrep? {
        let sessions = CookScheduler.sessions(gymThursday: plan.gymThursday)
        let monday = AppModel.currentMonday()
        if todayOffset == CookScheduler.tiredDayOffset {   // Sunday → prep next week
            guard let s = sessions.first(where: { $0.id == "sun-prep" }) else { return nil }
            let nextMonday = Calendar.current.date(byAdding: .day, value: 7, to: monday) ?? monday
            return TodayPrep(session: s, weekStart: nextMonday, isCooked: sessionCooked(s.id, weekStart: nextMonday))
        }
        // Mon–Sat: a session whose cook weekday is today (Tuesday, Thursday/Friday).
        guard let s = sessions.first(where: { (($0.cookDayOffset % 7) + 7) % 7 == todayOffset }) else { return nil }
        return TodayPrep(session: s, weekStart: monday, isCooked: sessionCooked(s.id, weekStart: monday))
    }

    private func sessionCooked(_ sessionID: String, weekStart: Date) -> Bool {
        let key = CookSessionLogEntity.key(weekStart: weekStart, sessionID: sessionID)
        return cookLogs.first { $0.sessionKey == key }?.isCooked ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let err = model.loadError { errorCard(err) }
                    if let week = model.variantWeek(for: plan), !week.days.allSatisfy(\.meals.isEmpty) {
                        prepStatusCard(week)
                    }
                    if today != nil {
                        dayTotalCard
                        ForEach(today?.meals ?? []) { meal in mealCard(meal) }
                    } else if model.loadError == nil {
                        ContentUnavailableView("No meals today", systemImage: "fork.knife",
                                               description: Text("Check your macro plan in the Plan tab."))
                    }
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
            .sheet(item: $cookModeContext) { ctx in
                CookModeView(sessionID: ctx.id, plan: plan, weekStart: ctx.weekStart)
            }
        }
    }

    private var dayTitle: String {
        "Today · " + CookScheduler.weekdayName(forOffset: todayOffset)
    }

    // MARK: - Meals

    private var dayTotalCard: some View {
        // Derived live from `model` (rebuilt on every edit via `reload`), so this
        // card — and its vs-target delta — recalculates the instant a meal changes.
        let total = MacroVector.sum(today?.meals.map(\.herMacros) ?? [])
        let delta = MacroDelta(target: plan.daily, actual: total)
        let tier = ToleranceTier(delta)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY · \(today?.variantID ?? "—")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("target ~\(Fmt.g(plan.dailyKcal)) kcal")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            MacroSummary(macros: total)
            HStack(spacing: 6) {
                Image(systemName: tier == .good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text("\(Fmt.signed(delta.absolute.kcal)) kcal vs target")
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(tier.color)
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


    /// Home's cook status. On a prep day it reflects the ACTUAL cooked-state of
    /// today's session (never assumed); on other days it points at the next
    /// session that still needs cooking.
    @ViewBuilder
    private func prepStatusCard(_ week: VariantWeek) -> some View {
        if let prep = todayPrep {
            prepDayCard(prep, week: week)
        } else {
            nextSessionCard(week)
        }
    }

    private func prepDayCard(_ prep: TodayPrep, week: VariantWeek) -> some View {
        let mealCount = week.meals(inSession: prep.session.id).count
        let covers = prep.session.coversDayOffsets
            .map { CookScheduler.weekdayName(forOffset: $0) }.joined(separator: " + ")
        return Button {
            if !prep.isCooked {
                cookModeContext = CookModeContext(id: prep.session.id, weekStart: prep.weekStart)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: prep.isCooked ? "checkmark.seal.fill" : "flame.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(prep.isCooked ? .green : .orange, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    if prep.isCooked {
                        Text("All cooked ✓").font(.headline)
                        Text("\(prep.session.title) done · covers \(covers)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Prep day today").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(prep.session.title): \(mealCount) meal\(mealCount == 1 ? "" : "s") to cook")
                            .font(.headline)
                        Text("Covers \(covers)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !prep.isCooked {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(prep.isCooked)
    }

    private func nextSessionCard(_ week: VariantWeek) -> some View {
        // Non-prep day: the next session this week that hasn't been cooked yet.
        let monday = AppModel.currentMonday()
        let upcoming = week.cookSessions
            .filter { $0.cookDayOffset >= todayOffset && !sessionCooked($0.id, weekStart: monday) }
            .sorted { $0.cookDayOffset < $1.cookDayOffset }
            .first
        return Button {
            if let upcoming { cookModeContext = CookModeContext(id: upcoming.id) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: upcoming == nil ? "checkmark.circle.fill" : "timer")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.green, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    if let upcoming {
                        Text("Next cook session").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(upcoming.title) · \(CookScheduler.weekdayName(forOffset: upcoming.cookDayOffset))")
                            .font(.headline)
                        Text("Cooks for " + upcoming.coversDayOffsets
                            .map { CookScheduler.weekdayName(forOffset: $0) }.joined(separator: " + "))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No cooking scheduled today").font(.headline)
                        Text("You're prepped through the week.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if upcoming != nil {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(upcoming == nil)
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
