import Foundation
import SwiftData
import MealPrepCore

/// Persisted, editable copy of a trainer day-variant. Seeded once from the
/// bundled `variants.json` on first launch (see `PlanDataSeeder`); from then on
/// this is the source of truth — edits mutate these rows directly. Retiring a
/// variant sets `isActive = false` rather than deleting it, so history and any
/// already-cooked record referencing it stays intact.
@Model
final class VariantEntity {
    @Attribute(.unique) var variantID: String = ""
    var name: String = ""
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \MealEntity.variant)
    var meals: [MealEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \VariantChangeEntity.variant)
    var history: [VariantChangeEntity] = []

    init(variantID: String, name: String, isActive: Bool = true, sortOrder: Int = 0,
         createdAt: Date = Date()) {
        self.variantID = variantID
        self.name = name
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - Bridge to MealPrepCore

    func asDayVariant() -> DayVariant {
        DayVariant(id: variantID, name: name,
                  meals: meals.sorted { $0.sortOrder < $1.sortOrder }.map { $0.asMealTemplate() },
                  isActive: isActive)
    }

    /// Records the CURRENT (pre-edit) state as a history entry, so an edit can
    /// always be undone. Call this immediately before applying a change.
    func recordHistory(summary: String) {
        let snapshot = asDayVariant().meals
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        history.append(VariantChangeEntity(timestamp: Date(), summary: summary, snapshotData: data, variant: self))
    }
}

/// One meal inside a `VariantEntity`. Ingredient lines and cook steps are
/// stored as JSON-encoded `Data` — both are already `Codable` in MealPrepCore,
/// so this avoids modelling every nested field as its own SwiftData attribute.
@Model
final class MealEntity {
    @Attribute(.unique) var mealID: String = ""
    var name: String = ""
    var mealTypeRaw: String = "lunch"
    var batchSafe: Bool = false
    var freshOnly: Bool = false
    var linesData: Data = Data()
    var cookStepsData: Data = Data()
    var sortOrder: Int = 0
    var variant: VariantEntity?

    init(mealID: String, name: String, mealTypeRaw: String, batchSafe: Bool = false,
         freshOnly: Bool = false, linesData: Data = Data(), cookStepsData: Data = Data(),
         sortOrder: Int = 0) {
        self.mealID = mealID
        self.name = name
        self.mealTypeRaw = mealTypeRaw
        self.batchSafe = batchSafe
        self.freshOnly = freshOnly
        self.linesData = linesData
        self.cookStepsData = cookStepsData
        self.sortOrder = sortOrder
    }

    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .lunch }
    var lines: [RecipeLine] { (try? JSONDecoder().decode([RecipeLine].self, from: linesData)) ?? [] }
    var cookSteps: [CookStep] { (try? JSONDecoder().decode([CookStep].self, from: cookStepsData)) ?? [] }

    func setLines(_ lines: [RecipeLine]) {
        linesData = (try? JSONEncoder().encode(lines)) ?? Data()
    }
    func setCookSteps(_ steps: [CookStep]) {
        cookStepsData = (try? JSONEncoder().encode(steps)) ?? Data()
    }

    func asMealTemplate() -> MealTemplate {
        MealTemplate(id: mealID, name: name, mealType: mealType, lines: lines,
                    batchSafe: batchSafe, freshOnly: freshOnly, cookSteps: cookSteps)
    }

    static func from(_ template: MealTemplate, sortOrder: Int) -> MealEntity {
        let entity = MealEntity(mealID: template.id, name: template.name,
                                mealTypeRaw: template.mealType.rawValue,
                                batchSafe: template.batchSafe, freshOnly: template.freshOnly,
                                sortOrder: sortOrder)
        entity.setLines(template.lines)
        entity.setCookSteps(template.cookSteps)
        return entity
    }
}

/// One change-history entry for a variant: what it looked like immediately
/// before an edit, so the edit can be undone.
@Model
final class VariantChangeEntity {
    var timestamp: Date = Date()
    var summary: String = ""
    /// JSON-encoded `[MealTemplate]` — the variant's meals right before the change.
    var snapshotData: Data = Data()
    var variant: VariantEntity?

    init(timestamp: Date = Date(), summary: String, snapshotData: Data, variant: VariantEntity? = nil) {
        self.timestamp = timestamp
        self.summary = summary
        self.snapshotData = snapshotData
        self.variant = variant
    }

    var snapshot: [MealTemplate] {
        (try? JSONDecoder().decode([MealTemplate].self, from: snapshotData)) ?? []
    }
}
