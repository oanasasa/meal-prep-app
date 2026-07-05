import SwiftUI
import SwiftData
import MealPrepCore

/// Fast fridge/pantry inventory: add items, tap to decrement as they're used,
/// swipe to remove, and a "do not eat" flag for perishable proteins past the
/// trainer's 2-day rule.
struct InventoryView: View {
    let plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \FridgeItemEntity.ingredientID) private var items: [FridgeItemEntity]
    @State private var showAddSheet = false
    @State private var showRestock = false

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView("Fridge is empty", systemImage: "refrigerator",
                                           description: Text("Add what you have, or run a restock after shopping."))
                } else {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Fridge & Pantry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showRestock = true } label: { Label("Restock", systemImage: "cart.fill") }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddFridgeItemView() }
            .sheet(isPresented: $showRestock) { RestockView(plan: plan) }
        }
    }

    private func itemRow(_ item: FridgeItemEntity) -> some View {
        let ingredient = model.ingredient(item.ingredientID)
        let expired = ingredient.map {
            MealPrepCore.FridgeExpiry.isExpired(item: item.asFridgeItem, ingredient: $0)
        } ?? false
        let age = MealPrepCore.FridgeExpiry.ageInDays(addedDate: item.addedDate)

        // Whole row is tappable to decrement (matching the trailing minus button),
        // not just the icon. Swipe-to-delete still removes the item entirely.
        return Button {
            decrement(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient?.name ?? item.ingredientID).font(.subheadline).foregroundStyle(.primary)
                    if expired {
                        Label("Do not eat — \(age)d old", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.red)
                    } else if ingredient?.isPerishableProtein == true {
                        Text(age == 0 ? "Added today" : "\(age)d old")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(displayQuantity(item, ingredient: ingredient))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
            .opacity(expired ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func displayQuantity(_ item: FridgeItemEntity, ingredient: Ingredient?) -> String {
        if let ingredient, ingredient.unit == .piece, let per = ingredient.gramsPerPiece, per > 0 {
            let pieces = (item.quantityGrams / per).rounded()
            return "\(Int(pieces)) pc"
        }
        return "\(Int(item.quantityGrams.rounded())) g"
    }

    private func decrement(_ item: FridgeItemEntity) {
        let ingredient = model.ingredient(item.ingredientID)
        let step = (ingredient?.unit == .piece ? ingredient?.gramsPerPiece : nil) ?? 50
        item.quantityGrams = max(0, item.quantityGrams - step)
        if item.quantityGrams == 0 { context.delete(item) }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(items[index]) }
    }
}

/// Search the ingredient database and add (or top up) a fridge item.
struct AddFridgeItemView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [FridgeItemEntity]

    @State private var query = ""
    @State private var selected: Ingredient?
    @State private var gramsText = ""

    private var matches: [Ingredient] {
        guard !query.isEmpty else { return [] }
        return model.database.all
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name < $1.name }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    TextField("Search ingredients…", text: $query)
                    if let selected {
                        Label(selected.name, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    ForEach(matches, id: \.id) { ing in
                        Button(ing.name) { selected = ing; query = ing.name }
                    }
                }
                if selected != nil {
                    Section("Quantity (raw grams)") {
                        TextField("grams", text: $gramsText).keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Add to Fridge")
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addItem() }
                        .disabled(selected == nil || Double(gramsText) == nil)
                }
            }
        }
    }

    private func addItem() {
        guard let selected, let grams = Double(gramsText) else { return }
        if let current = existing.first(where: { $0.ingredientID == selected.id }) {
            current.quantityGrams += grams
            current.addedDate = Date()
        } else {
            context.insert(FridgeItemEntity(ingredientID: selected.id, quantityGrams: grams))
        }
        dismiss()
    }
}
