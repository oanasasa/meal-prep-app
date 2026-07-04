import SwiftUI
import SwiftData
import MealPrepCore

struct CookModeView: View {
    let sessionID: String
    let plan: TrainerPlanEntity

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cookLogs: [CookSessionLogEntity]
    @Query private var fridgeEntities: [FridgeItemEntity]

    private var week: VariantWeek? { model.variantWeek(for: plan) }
    private var session: CookSession? { week?.cookSessions.first { $0.id == sessionID } }
    private var cookPlan: CookPlan? {
        guard let week else { return nil }
        return model.cookPlan(sessionID: sessionID, week: week, plan: plan)
    }
    private var sessionKey: String {
        CookSessionLogEntity.key(weekStart: AppModel.currentMonday(), sessionID: sessionID)
    }
    private var log: CookSessionLogEntity? { cookLogs.first { $0.sessionKey == sessionKey } }
    private var isCooked: Bool { log?.isCooked ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session, let cookPlan {
                        headerCard(session: session, plan: cookPlan)
                        ForEach(cookPlan.stations) { station in
                            stationCard(station)
                        }
                        batchGramsCard(cookPlan)
                        portionsCard(cookPlan)
                        markCookedButton
                    } else {
                        ContentUnavailableView("Couldn't build this session", systemImage: "exclamationmark.triangle",
                                               description: Text("Try reopening from the Week tab."))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(session?.title ?? "Cook Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Header

    private func headerCard(session: CookSession, plan cp: CookPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "timer").font(.title2).foregroundStyle(.orange)
                Text("~\(cp.totalMinutes) min").font(.title2.weight(.bold))
                Spacer()
                if isCooked {
                    Label("Cooked", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                }
            }
            Text("Cooks for " + session.coversDayOffsets
                .map { CookScheduler.weekdayName(forOffset: $0) }.joined(separator: " + "))
                .font(.subheadline).foregroundStyle(.secondary)
            if cp.totalMinutes > 60 {
                Label("Longer than the usual 45–60 min target", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Stations (merged parallel flow)

    private func stationCard(_ station: StationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon(for: station.method)).foregroundStyle(.tint)
                Text(name(for: station.method)).font(.headline)
                Spacer()
                Text("~\(station.stationMinutes) min").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(station.steps) { instance in
                StepRow(instance: instance)
                if instance.id != station.steps.last?.id { Divider() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func icon(for method: CookMethod) -> String {
        switch method {
        case .oven: return "flame.fill"
        case .stovetop: return "frying.pan.fill"
        case .riceCooker: return "microwave.fill"
        case .noCook: return "hand.raised.fill"
        }
    }
    private func name(for method: CookMethod) -> String {
        switch method {
        case .oven: return "Oven"
        case .stovetop: return "Stovetop"
        case .riceCooker: return "Rice cooker"
        case .noCook: return "Assembly"
        }
    }

    // MARK: - Batch grams

    private func batchGramsCard(_ cp: CookPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOTAL TO COOK — 2 DAYS × 2 PEOPLE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(cp.batchGrams) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(displayAmount(item)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func displayAmount(_ item: BatchIngredientAmount) -> String {
        if item.unit == .piece { return "\(Fmt.g(item.totalRawGrams)) g raw" }
        return "\(Fmt.g(item.totalRawGrams)) g raw"
    }

    // MARK: - Container portioning

    private func portionsCard(_ cp: CookPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PORTION INTO CONTAINERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(cp.containerPortions) { portion in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(CookScheduler.weekdayName(forOffset: portion.dayOffset)) · \(portion.profileName) · \(portion.mealName)")
                        .font(.subheadline.weight(.semibold))
                    Text(portion.lines.map { line in
                        "\(model.ingredient(line.ingredientID)?.name ?? line.ingredientID) \(Fmt.g(line.baseRawGrams))g"
                    }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Mark as cooked

    private var markCookedButton: some View {
        Button {
            let entry = log ?? {
                let new = CookSessionLogEntity(sessionKey: sessionKey)
                context.insert(new)
                return new
            }()
            let wasCooked = entry.isCooked
            entry.isCooked.toggle()
            entry.cookedAt = entry.isCooked ? Date() : nil
            if entry.isCooked, let week {
                MealNotificationScheduler.cancelNudges(for: sessionID, week: week)
            }
            // Decrement the fridge by exactly what this session used, once —
            // only on the false→true transition, so re-toggling doesn't
            // double-subtract.
            if entry.isCooked && !wasCooked, let cookPlan {
                decrementFridge(by: cookPlan.batchGrams)
            }
        } label: {
            Label(isCooked ? "Marked as cooked" : "Mark session as cooked",
                  systemImage: isCooked ? "checkmark.circle.fill" : "circle")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(isCooked ? .green : .accentColor)
        .controlSize(.large)
    }

    /// Uses up fridge stock for exactly what this session cooked. Clamps at
    /// zero and simply skips ingredients that aren't tracked in the fridge
    /// (e.g. spices) rather than erroring.
    private func decrementFridge(by batch: [BatchIngredientAmount]) {
        for amount in batch {
            guard let entity = fridgeEntities.first(where: { $0.ingredientID == amount.ingredientID }) else { continue }
            entity.quantityGrams = max(0, entity.quantityGrams - amount.totalRawGrams)
            if entity.quantityGrams == 0 { context.delete(entity) }
        }
    }
}

/// One instruction row with a small built-in countdown timer.
private struct StepRow: View {
    let instance: CookStepInstance
    @State private var timer = StepTimer()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.step.text).font(.subheadline)
                Text(instance.mealName).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            timerControl
        }
        .padding(.vertical, 2)
    }

    private var timerControl: some View {
        HStack(spacing: 6) {
            Text(timer.displayText(totalMinutes: instance.step.minutes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(timer.isRunning ? .orange : .secondary)
            Button {
                timer.toggle(totalMinutes: instance.step.minutes)
            } label: {
                Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
            }
        }
    }
}

/// A tiny self-contained per-step countdown. Not persisted — cook mode timers
/// are ephemeral to the current cooking session in the UI.
@Observable
private final class StepTimer {
    var remainingSeconds: Int?
    var isRunning = false
    private var tickTask: Task<Void, Never>?

    func toggle(totalMinutes: Int) {
        if isRunning {
            isRunning = false
            tickTask?.cancel()
            return
        }
        if remainingSeconds == nil { remainingSeconds = totalMinutes * 60 }
        isRunning = true
        tickTask = Task { [weak self] in
            while let self, self.isRunning, let remaining = self.remainingSeconds, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remainingSeconds = remaining - 1
            }
            self?.isRunning = false
        }
    }

    func displayText(totalMinutes: Int) -> String {
        let seconds = remainingSeconds ?? totalMinutes * 60
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
