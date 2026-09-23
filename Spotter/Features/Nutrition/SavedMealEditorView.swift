import SwiftUI

/// Rename a saved meal, remove items, or adjust quantities.
///
/// No nested food search in v1 — adding a new item to an existing saved meal
/// means saving a fresh one from the diary instead.
struct SavedMealEditorView: View {
    let savedMeal: SavedMeal

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var items: [SavedMealItem]
    private let originalItems: [SavedMealItem]

    init(savedMeal: SavedMeal) {
        self.savedMeal = savedMeal
        let ordered = savedMeal.orderedItems
        _name = State(initialValue: savedMeal.name)
        _items = State(initialValue: ordered)
        originalItems = ordered
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                }

                Section("Items") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(item.foodName)
                            Stepper(value: $item.quantity, in: 0.25...50, step: 0.25) {
                                Text("\(QuantityFormatter.string(from: item.quantity)) × \(item.servingLabel)")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                    }
                    .onDelete { indices in
                        items.remove(atOffsets: indices)
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    /// Renumbers to match the (possibly reordered-by-deletion) list, and
    /// rescales each item's snapshot nutrition by its quantity change — the
    /// snapshot was captured at a specific quantity, so a quantity edit here
    /// must not leave a deleted-food item's nutrition stale for its new
    /// quantity. A live-food item recomputes its own nutrition at log time
    /// regardless, but rescaling here keeps the saved meal's own totals
    /// accurate too.
    private func save() {
        let originalByID = Dictionary(uniqueKeysWithValues: originalItems.map { ($0.id, $0) })
        savedMeal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        savedMeal.items = items.enumerated().map { index, item in
            var updated = item
            updated.order = index
            if let original = originalByID[item.id],
               original.quantity > 0,
               original.quantity != item.quantity {
                updated.nutrientsSnapshot = original.nutrientsSnapshot.scaled(by: item.quantity / original.quantity)
            }
            return updated
        }
        dismiss()
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let savedMeal = SavedMeal(
        name: "Protein Shake + Oats",
        items: [
            SavedMealItem(
                order: 0,
                foodName: "Protein Powder",
                quantity: 1,
                servingLabel: "1 scoop",
                servingGramWeight: 30,
                nutrientsSnapshot: Nutrients(kcal: 120, proteinG: 24)
            ),
            SavedMealItem(
                order: 1,
                foodName: "Oats",
                quantity: 1,
                servingLabel: "50 g",
                servingGramWeight: 50,
                nutrientsSnapshot: Nutrients(kcal: 190, proteinG: 7, carbsG: 33, fatG: 3.5)
            ),
        ]
    )
    container.mainContext.insert(savedMeal)
    return SavedMealEditorView(savedMeal: savedMeal)
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
