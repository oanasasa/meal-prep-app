import Foundation
import SwiftData
import MealPrepCore

/// Copies the bundled `variants.json` into SwiftData on first launch. From
/// then on the SwiftData rows are authoritative — the bundled JSON is never
/// read again, so edits persist and survive future app updates that might
/// ship a revised seed file.
enum PlanDataSeeder {
    /// Inserts the bundled example variants only if the store is empty. Called
    /// on launch as a safety net; onboarding decides whether a brand-new user
    /// starts from the example plan or an empty one (see `OnboardingView`).
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<VariantEntity>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }
        seed(context: context)
    }

    /// Inserts the bundled example variants unconditionally.
    static func seed(context: ModelContext) {
        guard let bundled = try? VariantLibrary.loadBundled() else { return }
        let existingCount = (try? context.fetchCount(FetchDescriptor<VariantEntity>())) ?? 0
        for (index, variant) in bundled.all.enumerated() {
            let entity = VariantEntity(variantID: variant.id, name: variant.name,
                                       isActive: variant.isActive, sortOrder: existingCount + index)
            entity.meals = variant.meals.enumerated().map { i, meal in MealEntity.from(meal, sortOrder: i) }
            context.insert(entity)
        }
        try? context.save()
    }

    /// Discards ALL current variants (and their meals + edit history) and
    /// restores the bundled example plan. Used by "Reset to default plan".
    static func resetToDefault(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<VariantEntity>())) ?? []
        for variant in existing { context.delete(variant) }   // cascade removes meals + history
        try? context.save()
        seed(context: context)
    }
}
