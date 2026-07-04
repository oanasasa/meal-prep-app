import SwiftUI
import MealPrepCore

/// Read-only preview of everything the week needs, grouped by store section —
/// this pre-shop list doesn't subtract fridge stock (only the post-shop
/// Restock flow is fridge-aware). It's also where the "Grocery list ready"
/// notification opens.
struct GroceryListView: View {
    let plan: TrainerPlanEntity
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var items: [GroceryItem] { model.groceryItems(for: plan) }
    private var sections: [StoreSection] {
        Array(Set(items.map(\.section))).sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("Nothing needed yet", systemImage: "cart",
                                           description: Text("Your grocery list builds from this week's plan."))
                } else {
                    List {
                        ForEach(sections, id: \.self) { section in
                            Section(section.rawValue.capitalized) {
                                ForEach(items.filter { $0.section == section }) { item in
                                    HStack {
                                        Text(item.name)
                                        Spacer()
                                        Text(item.displayQuantity).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                }
                            }
                        }
                        Section {
                            Text("This is everything the week needs — it doesn't yet subtract what's in your fridge.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Grocery List (\(items.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
