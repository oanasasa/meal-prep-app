import SwiftUI
import SwiftData
import MealPrepCore

/// After a grocery trip: check off what you actually found. Anything left
/// unchecked immediately surfaces which meals it affects and a substitute
/// button for each — the core "restock triggers substitution" flow.
struct RestockView: View {
    let plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var fridgeEntities: [FridgeItemEntity]

    /// Defaults to "found" for every item — she unchecks the few exceptions
    /// rather than confirming every single item, which is far less friction
    /// for a trip where most things go as planned.
    @State private var found: [String: Bool] = [:]
    @State private var substituteContext: SubstituteContext?

    private var items: [GroceryItem] { model.groceryItems(for: plan) }
    private var missingItems: [GroceryItem] { items.filter { found[$0.id] == false } }

    var body: some View {
        NavigationStack {
            List {
                Section("Check off what you found") {
                    ForEach(items) { item in
                        Toggle(isOn: bindingFor(item)) {
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.displayQuantity).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !missingItems.isEmpty {
                    Section("Affected by what's missing") {
                        ForEach(missingItems) { item in
                            missingItemRow(item)
                        }
                    }
                }
            }
            .navigationTitle("Restock")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { applyRestock(); dismiss() }
                }
            }
            .sheet(item: $substituteContext) { ctx in
                SubstituteView(title: ctx.title, lines: ctx.lines, target: ctx.target)
            }
            .onAppear {
                for item in items where found[item.id] == nil { found[item.id] = true }
            }
        }
    }

    private func bindingFor(_ item: GroceryItem) -> Binding<Bool> {
        Binding(get: { found[item.id] ?? true }, set: { found[item.id] = $0 })
    }

    private func missingItemRow(_ item: GroceryItem) -> some View {
        let affected = model.affectedMeals(missingIngredientID: item.ingredientID, plan: plan)
        return VStack(alignment: .leading, spacing: 8) {
            Label(item.name, systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.subheadline)
            ForEach(affected) { meal in
                Button {
                    let target = (try? model.portioner.macros(for: meal.meal, multiplier: 1.0)) ?? .zero
                    substituteContext = SubstituteContext(title: meal.meal.name, lines: meal.meal.lines, target: target)
                } label: {
                    HStack {
                        Text(meal.meal.name)
                        Spacer()
                        Text("Substitute →").foregroundStyle(.tint)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)

                if let fallback = fallbackSuggestion(for: meal.variantID) {
                    Text("Or switch the whole day to \(fallback.variantID) — it fits what you have better.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fallbackSuggestion(for variantID: String) -> VariantFitScore? {
        model.variantFallback(awayFrom: variantID, fridge: projectedFridge())
    }

    /// What the fridge will look like after this restock (current stock + the
    /// items she actually checked off), used to score the fallback suggestion.
    private func projectedFridge() -> FridgeInventory {
        var byIngredient = Dictionary(uniqueKeysWithValues: fridgeEntities.map { ($0.ingredientID, $0.quantityGrams) })
        for item in items where found[item.id] != false {
            byIngredient[item.ingredientID, default: 0] += item.totalRawGrams
        }
        let now = Date()
        return FridgeInventory(items: byIngredient.map { FridgeItem(ingredientID: $0.key, quantityGrams: $0.value, addedDate: now) })
    }

    private func applyRestock() {
        for item in items where found[item.id] != false {
            if let existing = fridgeEntities.first(where: { $0.ingredientID == item.ingredientID }) {
                existing.quantityGrams += item.totalRawGrams
                existing.addedDate = Date()
            } else {
                context.insert(FridgeItemEntity(ingredientID: item.ingredientID, quantityGrams: item.totalRawGrams))
            }
        }
    }
}
