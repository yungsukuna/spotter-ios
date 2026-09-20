import SwiftUI

/// Adjust the quantity or meal of an already-logged entry.
///
/// Rescaling uses a ratio against the entry's own snapshot
/// (`newNutrients = oldNutrients.scaled(by: newQuantity / oldQuantity)`)
/// rather than reading back through ``DiaryEntry/food``, which may be nil —
/// the food can be deleted after being logged, and the diary snapshot is the
/// only copy of the nutrition that is guaranteed to still exist.
struct EditDiaryEntryView: View {
    let entry: DiaryEntry

    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Double
    @State private var meal: Meal

    init(entry: DiaryEntry) {
        self.entry = entry
        _quantity = State(initialValue: entry.quantity)
        _meal = State(initialValue: entry.meal)
    }

    private var previewNutrients: Nutrients {
        guard entry.quantity > 0 else { return entry.nutrients }
        return entry.nutrients.scaled(by: quantity / entry.quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Portion") {
                    Stepper(value: $quantity, in: 0.25...50, step: 0.25) {
                        Text("\(QuantityFormatter.string(from: quantity)) × \(entry.servingLabel)")
                    }
                }

                Section("Meal") {
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.ordered) { meal in
                            Text(meal.displayName).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Nutrition") {
                    LabeledContent("Calories", value: Format.energy(previewNutrients.kcal))
                    LabeledContent("Protein", value: Format.grams(previewNutrients.proteinG))
                    LabeledContent("Carbs", value: Format.grams(previewNutrients.carbsG))
                    LabeledContent("Fat", value: Format.grams(previewNutrients.fatG))
                }
            }
            .navigationTitle(entry.foodName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        entry.nutrients = previewNutrients
        entry.quantity = quantity
        entry.meal = meal
        dismiss()
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let food = FoodItem(name: "Weet-Bix", nutrientsPer100g: Nutrients(kcal: 349, proteinG: 12.9, carbsG: 67.1, fatG: 1.3))
    container.mainContext.insert(food)
    let entry = DiaryEntry(logging: food, quantity: 2, serving: ServingSize(label: "2 biscuits", gramWeight: 30), meal: .breakfast)
    container.mainContext.insert(entry)
    return EditDiaryEntryView(entry: entry)
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
