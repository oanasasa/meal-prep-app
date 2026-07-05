import SwiftUI
import SwiftData
import MealPrepCore

/// Edit one meal: rename, retag batch-safe/fresh-only, add/remove/re-gram
/// ingredients — all with live day-total macro feedback against the profile's
/// targets (colour-coded ±5%/±10%/beyond) so you can see the impact before
/// saving. Grams are always "Her" base weights; the partner's total is shown
/// too, scaled by his multiplier, to make the propagation visible.
struct MealEditorView: View {
    let meal: MealEntity
    let variant: VariantEntity
    let plan: TrainerPlanEntity

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var mealType: MealType
    @State private var batchSafe: Bool
    @State private var freshOnly: Bool
    @State private var lines: [RecipeLine]
    @State private var showIngredientPicker = false

    private var partnerLabel: String {
        let trimmed = plan.partnerName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Partner" : trimmed
    }

    init(meal: MealEntity, variant: VariantEntity, plan: TrainerPlanEntity) {
        self.meal = meal
        self.variant = variant
        self.plan = plan
        _name = State(initialValue: meal.name)
        _mealType = State(initialValue: meal.mealType)
        _batchSafe = State(initialValue: meal.batchSafe)
        _freshOnly = State(initialValue: meal.freshOnly)
        _lines = State(initialValue: meal.lines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Day total (with this edit)") {
                    DayTotalBanner(label: "Her", actual: herDayMacros, target: plan.daily)
                    DayTotalBanner(label: "\(partnerLabel) (×\(String(format: "%.2f", plan.husbandMultiplier)))",
                                  actual: hisDayMacros, target: plan.daily * plan.husbandMultiplier)
                }

                Section("Meal") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Cooking") {
                    Toggle("Batch-safe (cook once, eat over 2 days)", isOn: $batchSafe)
                        .onChange(of: batchSafe) { _, new in if new { freshOnly = false } }
                    Toggle("Fresh-only (assembled same day)", isOn: $freshOnly)
                        .onChange(of: freshOnly) { _, new in if new { batchSafe = false } }
                }

                Section("Ingredients (raw grams, Her portion)") {
                    ForEach(Array(lines.enumerated()), id: \.element.ingredientID) { index, line in
                        lineRow(index: index, line: line)
                    }
                    .onDelete { offsets in lines.remove(atOffsets: offsets) }

                    Button { showIngredientPicker = true } label: {
                        Label("Add ingredient", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(name.isEmpty ? "Edit Meal" : name)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(lines.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showIngredientPicker) {
                IngredientPickerView { ingredient in
                    // Piece foods start at 1 piece; weighed foods start at 100 g.
                    let start: Double = (ingredient.unit == .piece && (ingredient.gramsPerPiece ?? 0) > 0)
                        ? (ingredient.gramsPerPiece ?? 100) : 100
                    lines.append(RecipeLine(ingredientID: ingredient.id, baseRawGrams: start))
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func lineRow(index: Int, line: RecipeLine) -> some View {
        let ingredient = model.ingredient(line.ingredientID)
        let perPiece = ingredient?.gramsPerPiece ?? 0
        let isPiece = ingredient?.unit == .piece && perPiece > 0

        VStack(alignment: .leading, spacing: 6) {
            Text(ingredient?.name ?? line.ingredientID)
            if isPiece {
                // Whole-item foods (eggs, tortillas…): enter pieces, not grams.
                HStack(spacing: 10) {
                    TextField("0", value: pieceBinding(at: index, gramsPerPiece: perPiece), format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text(pieceLabel(line.baseRawGrams / perPiece)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Fmt.g(line.baseRawGrams)) g raw").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    Stepper(value: pieceBinding(at: index, gramsPerPiece: perPiece), in: 0...200, step: 1) {
                        EmptyView()
                    }.labelsHidden()
                }
            } else {
                // Weighed foods: type grams directly, or nudge with ± (step 5 g).
                HStack(spacing: 10) {
                    TextField("0", value: gramsBinding(at: index), format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text(ingredient?.unit == .milliliter ? "ml" : "g raw").foregroundStyle(.secondary)
                    Spacer()
                    Stepper(value: gramsBinding(at: index), in: 0...5000, step: 5) {
                        EmptyView()
                    }.labelsHidden()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func pieceLabel(_ count: Double) -> String {
        abs(count - 1) < 0.01 ? "piece" : "pieces"
    }

    private func gramsBinding(at index: Int) -> Binding<Double> {
        Binding(
            get: { index < lines.count ? lines[index].baseRawGrams : 0 },
            set: { newValue in
                guard index < lines.count else { return }
                let id = lines[index].ingredientID
                lines[index] = RecipeLine(ingredientID: id, baseRawGrams: max(0, newValue))
            }
        )
    }

    /// Reads/writes the line in pieces, converting to the stored raw grams via
    /// the ingredient's grams-per-piece.
    private func pieceBinding(at index: Int, gramsPerPiece: Double) -> Binding<Double> {
        Binding(
            get: { index < lines.count ? lines[index].baseRawGrams / gramsPerPiece : 0 },
            set: { pieces in
                guard index < lines.count else { return }
                let id = lines[index].ingredientID
                lines[index] = RecipeLine(ingredientID: id, baseRawGrams: max(0, pieces) * gramsPerPiece)
            }
        )
    }

    // MARK: - Live macro feedback

    private var editedTemplate: MealTemplate {
        MealTemplate(id: meal.mealID, name: name, mealType: mealType, lines: lines,
                    batchSafe: batchSafe, freshOnly: freshOnly, cookSteps: meal.cookSteps)
    }

    private var editedDayVariant: DayVariant {
        let others = variant.meals.filter { $0.mealID != meal.mealID }.map { $0.asMealTemplate() }
        return DayVariant(id: variant.variantID, name: variant.name, meals: others + [editedTemplate],
                          isActive: variant.isActive)
    }

    private var herDayMacros: MacroVector {
        (try? model.portioner.dayMacros(for: editedDayVariant)) ?? .zero
    }

    private var hisDayMacros: MacroVector {
        (try? model.portioner.dayMacros(for: editedDayVariant, multiplier: plan.husbandMultiplier)) ?? .zero
    }

    // MARK: - Save

    private func save() {
        variant.recordHistory(summary: "Edited \(meal.name)")
        meal.name = name
        meal.mealTypeRaw = mealType.rawValue
        meal.batchSafe = batchSafe
        meal.freshOnly = freshOnly
        meal.setLines(lines)
        try? context.save()
        model.reload(context: context)
        dismiss()
    }
}
