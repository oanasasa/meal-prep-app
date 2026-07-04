import SwiftUI
import SwiftData
import MealPrepCore

/// The core feature made tappable: pick the ingredient the store didn't have,
/// see whole-food substitutes re-gram'd to keep the meal within ±5%. Can also
/// search fresh fridge stock instead of the default same-food-group pool.
struct SubstituteView: View {
    let title: String
    let lines: [RecipeLine]      // Her scaled grams for this meal
    let target: MacroVector      // the meal's per-plan macro target

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var fridgeEntities: [FridgeItemEntity]
    @State private var missingID: String?
    @State private var useFridge = false

    var body: some View {
        NavigationStack {
            List {
                Section("Which ingredient is missing?") {
                    ForEach(lines, id: \.ingredientID) { line in
                        if let ing = model.ingredient(line.ingredientID) {
                            Button {
                                missingID = (missingID == line.ingredientID) ? nil : line.ingredientID
                            } label: {
                                HStack {
                                    Image(systemName: missingID == line.ingredientID
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(missingID == line.ingredientID ? Color.accentColor : Color.secondary)
                                    Text(ing.name)
                                    Spacer()
                                    Text("\(Fmt.g(line.baseRawGrams)) g")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if missingID != nil {
                    Section {
                        Toggle("Replace with something I have", isOn: $useFridge)
                    }
                }

                if let missingID {
                    let fridge = useFridge ? model.fridgeInventory(from: fridgeEntities) : nil
                    let suggestions = model.suggestions(forMissing: missingID, lines: lines, target: target, fridge: fridge)
                    Section(useFridge ? "From your fridge (fresh only)" : "Swap in (ranked, keeps meal within ±5%)") {
                        if suggestions.isEmpty {
                            Text(useFridge ? "Nothing fresh in your fridge fits here yet."
                                           : "No whole-food match in this group yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(suggestions, id: \.substitute.id) { s in
                            suggestionRow(s)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func suggestionRow(_ s: SubstitutionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: s.withinTolerance ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(s.withinTolerance ? .green : .orange)
                Text(s.substitute.name).font(.headline)
                Spacer()
                Text("\(Fmt.g(s.grams)) g")
                    .font(.headline.monospacedDigit()).foregroundStyle(.tint)
            }
            DeltaChips(delta: s.delta.absolute, ok: s.withinTolerance)
        }
        .padding(.vertical, 4)
    }
}
