import SwiftUI
import SwiftData
import MealPrepCore

/// Change history for one variant — date + what changed, with the ability to
/// restore any previous version. Restoring itself is recorded as a new
/// history entry, so a restore can always be undone too.
struct VariantHistoryView: View {
    let variant: VariantEntity

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRestore: VariantChangeEntity?

    private var sortedHistory: [VariantChangeEntity] {
        variant.history.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedHistory.isEmpty {
                    ContentUnavailableView("No changes yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Edits to this variant will show up here."))
                } else {
                    ForEach(sortedHistory) { entry in
                        Button {
                            pendingRestore = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.summary).font(.subheadline).foregroundStyle(.primary)
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Restore this version?", isPresented: Binding(
                get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }
            ), presenting: pendingRestore) { entry in
                Button("Restore", role: .destructive) { restore(entry) }
            } message: { entry in
                Text("Replaces the current meals with what this variant looked like on \(entry.timestamp.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
    }

    private func restore(_ entry: VariantChangeEntity) {
        variant.recordHistory(summary: "Restored to \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
        for meal in variant.meals { context.delete(meal) }
        variant.meals = entry.snapshot.enumerated().map { index, template in
            let restored = MealEntity.from(template, sortOrder: index)
            restored.variant = variant
            return restored
        }
        try? context.save()
        model.reload(context: context)
        dismiss()
    }
}
