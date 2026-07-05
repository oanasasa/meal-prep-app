import SwiftUI
import SwiftData
import MealPrepCore

/// One variant's meals: tap a meal to edit it, add a new one, duplicate the
/// whole variant as a starting point for another, or retire it (active
/// toggle) without losing history.
struct VariantDetailView: View {
    @Bindable var variant: VariantEntity
    let plan: TrainerPlanEntity

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showHistory = false
    @State private var editingMeal: MealEntity?

    private var sortedMeals: [MealEntity] { variant.meals.sorted { $0.sortOrder < $1.sortOrder } }
    private var dayMacros: MacroVector { (try? model.portioner.dayMacros(for: variant.asDayVariant())) ?? .zero }

    var body: some View {
        List {
            Section("Day total (Her)") {
                MacroSummary(macros: dayMacros)
                let delta = MacroDelta(target: plan.daily, actual: dayMacros)
                let tier = ToleranceTier(delta)
                Text("\(Fmt.signed(delta.absolute.kcal)) kcal vs target")
                    .font(.caption.weight(.semibold)).foregroundStyle(tier.color)
            }

            Section {
                TextField("Name", text: $variant.name)
                    .onSubmit(persistAndReload)
                Toggle("Active (used in weekly rotation)", isOn: $variant.isActive)
                    .onChange(of: variant.isActive) { _, _ in persistAndReload() }
            }

            Section("Meals") {
                ForEach(sortedMeals) { meal in
                    Button {
                        editingMeal = meal
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name).foregroundStyle(.primary)
                                Text(meal.mealType.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button { addMeal() } label: {
                    Label("Add meal", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button { duplicate() } label: {
                    Label("Duplicate this variant", systemImage: "plus.square.on.square")
                }
                Button { showHistory = true } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle(variant.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingMeal) { meal in
            MealEditorView(meal: meal, variant: variant, plan: plan)
        }
        .sheet(isPresented: $showHistory) {
            VariantHistoryView(variant: variant)
        }
    }

    private func persistAndReload() {
        try? context.save()
        model.reload(context: context)
    }

    private func addMeal() {
        variant.recordHistory(summary: "Added a new meal")
        let newMeal = MealEntity(mealID: "meal-\(UUID().uuidString.prefix(8))", name: "New Meal",
                                 mealTypeRaw: MealType.lunch.rawValue, sortOrder: variant.meals.count)
        newMeal.variant = variant
        variant.meals.append(newMeal)
        persistAndReload()
        editingMeal = newMeal   // jump straight into editing it
    }

    private func duplicate() {
        let existingVariantIDs = Set(model.variants.all.map(\.id))
        var newID = "\(variant.variantID)-copy"
        var suffix = 2
        while existingVariantIDs.contains(newID) {
            newID = "\(variant.variantID)-copy-\(suffix)"
            suffix += 1
        }
        let newVariant = VariantEntity(variantID: newID, name: "\(variant.name) Copy", isActive: true,
                                       sortOrder: model.variants.count)
        newVariant.meals = sortedMeals.enumerated().map { index, meal in
            let copy = MealEntity(mealID: "\(meal.mealID)-\(newID)", name: meal.name, mealTypeRaw: meal.mealTypeRaw,
                                  batchSafe: meal.batchSafe, freshOnly: meal.freshOnly, sortOrder: index)
            copy.setLines(meal.lines)
            copy.setCookSteps(meal.cookSteps)
            copy.variant = newVariant
            return copy
        }
        context.insert(newVariant)
        persistAndReload()
        dismiss()
    }
}
