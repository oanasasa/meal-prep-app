import SwiftUI
import SwiftData
import MealPrepCore

/// Search the merged (bundled + custom) ingredient database and pick one to
/// add as a meal line. "Can't find it?" leads to `AddIngredientView` so the
/// trainer's new food becomes available immediately, then is selected.
struct IngredientPickerView: View {
    let onSelect: (Ingredient) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showAddNew = false

    private var matches: [Ingredient] {
        let all = model.database.all.sorted { $0.name < $1.name }
        guard !query.isEmpty else { return Array(all.prefix(30)) }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showAddNew = true
                    } label: {
                        Label("Add a new ingredient", systemImage: "plus.circle.fill")
                    }
                }
                Section {
                    ForEach(matches) { ingredient in
                        Button {
                            onSelect(ingredient)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name).foregroundStyle(.primary)
                                    Text("\(Fmt.g(ingredient.per100g.kcal)) kcal · \(Fmt.g(ingredient.per100g.protein))g P / 100g")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search ingredients")
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showAddNew) {
                AddIngredientView { newIngredient in
                    onSelect(newIngredient)
                    dismiss()
                }
            }
        }
    }
}

/// Form for a trainer-introduced food not yet in the database: name, category,
/// per-100g macros (from the product label), and a substitution group so the
/// swap engine can use it.
struct AddIngredientView: View {
    /// Called with the newly-created ingredient once saved.
    var onSave: (Ingredient) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var section: StoreSection = .pantry
    @State private var group: SubstitutionGroup = .vegetable
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var unit: MeasureUnit = .grams
    @State private var gramsPerPiece = ""
    @State private var isPerishableProtein = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(kcal) != nil && Double(protein) != nil && Double(carbs) != nil && Double(fat) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Turkey bacon", text: $name)
                }
                Section("Category") {
                    Picker("Store section", selection: $section) {
                        ForEach(StoreSection.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Substitution group", selection: $group) {
                        ForEach(SubstitutionGroup.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Section("Per 100 g (from the label)") {
                    numberField("Calories", $kcal, "kcal")
                    numberField("Protein", $protein, "g")
                    numberField("Carbs", $carbs, "g")
                    numberField("Fat", $fat, "g")
                }
                Section("Measured as") {
                    Picker("Unit", selection: $unit) {
                        Text("Grams").tag(MeasureUnit.grams)
                        Text("Piece").tag(MeasureUnit.piece)
                        Text("Milliliters").tag(MeasureUnit.milliliter)
                    }
                    .pickerStyle(.segmented)
                    if unit == .piece {
                        numberField("Grams per piece", $gramsPerPiece, "g")
                    }
                }
                Section {
                    Toggle("Perishable protein (2-day rule applies)", isOn: $isPerishableProtein)
                }
            }
            .navigationTitle("New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func numberField(_ label: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 90)
                .minimumScaleFactor(0.5)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let kcalV = Double(kcal), let proteinV = Double(protein),
              let carbsV = Double(carbs), let fatV = Double(fat) else { return }

        let existingIDs = Set(model.database.all.map(\.id))
        var slug = IngredientEntity.slug(from: name)
        if slug.isEmpty { slug = "ingredient" }
        var candidate = slug
        var suffix = 2
        while existingIDs.contains(candidate) {
            candidate = "\(slug)-\(suffix)"
            suffix += 1
        }

        let entity = IngredientEntity(ingredientID: candidate, name: name,
                                      sectionRaw: section.rawValue, groupRaw: group.rawValue,
                                      kcal: kcalV, protein: proteinV, carbs: carbsV, fat: fatV,
                                      unitRaw: unit.rawValue,
                                      gramsPerPiece: unit == .piece ? Double(gramsPerPiece) : nil,
                                      isPerishableProtein: isPerishableProtein)
        context.insert(entity)
        try? context.save()
        model.reload(context: context)
        onSave(entity.asIngredient())
        dismiss()
    }
}
