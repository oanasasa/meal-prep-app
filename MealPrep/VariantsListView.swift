import SwiftUI
import SwiftData
import MealPrepCore

/// All day-variants (active and retired), the entry point to the plan editor.
/// "Duplicate this variant" lives on each variant's own detail screen; the "+"
/// here builds a new one from scratch.
struct VariantsListView: View {
    let plan: TrainerPlanEntity

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \VariantEntity.sortOrder) private var variantEntities: [VariantEntity]

    var body: some View {
        List {
            ForEach(variantEntities) { variant in
                NavigationLink {
                    VariantDetailView(variant: variant, plan: plan)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.name)
                            Text("\(variant.meals.count) meals").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !variant.isActive {
                            Text("Inactive").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle("Meal Plan Variants")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addFromScratch() } label: { Image(systemName: "plus") }
            }
        }
    }

    private func addFromScratch() {
        let newID = "variant-\(UUID().uuidString.prefix(8))"
        let variant = VariantEntity(variantID: newID, name: "New Variant", isActive: true,
                                    sortOrder: variantEntities.count)
        context.insert(variant)
        try? context.save()
        model.reload(context: context)
    }
}
