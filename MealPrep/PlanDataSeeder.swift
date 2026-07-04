import Foundation
import SwiftData
import MealPrepCore

/// Copies the bundled `variants.json` into SwiftData on first launch. From
/// then on the SwiftData rows are authoritative — the bundled JSON is never
/// read again, so edits persist and survive future app updates that might
/// ship a revised seed file.
enum PlanDataSeeder {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<VariantEntity>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }
        guard let bundled = try? VariantLibrary.loadBundled() else { return }

        for (index, variant) in bundled.all.enumerated() {
            let entity = VariantEntity(variantID: variant.id, name: variant.name,
                                       isActive: variant.isActive, sortOrder: index)
            entity.meals = variant.meals.enumerated().map { i, meal in MealEntity.from(meal, sortOrder: i) }
            context.insert(entity)
        }
        try? context.save()
    }
}
