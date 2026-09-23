import SwiftUI

/// Adjust an already-logged entry.
///
/// Two different entries need two different edit behaviours here:
/// - **A catalogue-food entry** rescales by quantity ratio
///   (`newNutrients = oldNutrients.scaled(by: newQuantity / oldQuantity)`)
///   rather than reading back through ``DiaryEntry/food``, which may be nil —
///   the food can be deleted after being logged, and the diary snapshot is
///   the only copy of the nutrition guaranteed to still exist.
/// - **A quick-add entry** (see ``QuickAdd/isQuickAdd``) has no serving to
///   scale a ratio against, so it edits calories and macros directly instead.
struct EditDiaryEntryView: View {
    let entry: DiaryEntry

    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Double
    @State private var meal: Meal

    // Quick-add direct-edit fields.
    @State private var quickAddName: String
    @State private var kcalText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    private var isQuickAdd: Bool { entry.isQuickAdd }

    init(entry: DiaryEntry) {
        self.entry = entry
        _quantity = State(initialValue: entry.quantity)
        _meal = State(initialValue: entry.meal)
        _quickAddName = State(initialValue: entry.foodName)
        _kcalText = State(initialValue: Self.string(entry.nutrients.kcal))
        _proteinText = State(initialValue: Self.string(entry.nutrients.proteinG))
        _carbsText = State(initialValue: Self.string(entry.nutrients.carbsG))
        _fatText = State(initialValue: Self.string(entry.nutrients.fatG))
    }

    private static func string(_ value: Double?) -> String {
        guard let value else { return "" }
        return QuantityFormatter.string(from: value)
    }

    private var previewNutrients: Nutrients {
        guard entry.quantity > 0 else { return entry.nutrients }
        return entry.nutrients.scaled(by: quantity / entry.quantity)
    }

    private var quickAddNutrients: Nutrients? {
        QuickAdd.makeNutrients(
            kcalText: kcalText,
            proteinText: proteinText,
            carbsText: carbsText,
            fatText: fatText
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if isQuickAdd {
                    Section("Name") {
                        TextField("Name", text: $quickAddName)
                    }
                    Section("Calories") {
                        numberField("Calories", text: $kcalText)
                    }
                    Section("Macros (optional)") {
                        numberField("Protein (g)", text: $proteinText)
                        numberField("Carbs (g)", text: $carbsText)
                        numberField("Fat (g)", text: $fatText)
                    }
                } else {
                    Section("Portion") {
                        Stepper(value: $quantity, in: 0.25...50, step: 0.25) {
                            Text("\(QuantityFormatter.string(from: quantity)) × \(entry.servingLabel)")
                        }
                    }

                    Section("Nutrition") {
                        LabeledContent("Calories", value: Format.energy(previewNutrients.kcal))
                        LabeledContent("Protein", value: Format.grams(previewNutrients.proteinG))
                        LabeledContent("Carbs", value: Format.grams(previewNutrients.carbsG))
                        LabeledContent("Fat", value: Format.grams(previewNutrients.fatG))
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
            }
            .navigationTitle(entry.foodName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isQuickAdd && quickAddNutrients == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func numberField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }

    private func save() {
        if isQuickAdd {
            guard let quickAddNutrients else { return }
            let trimmedName = quickAddName.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.foodName = trimmedName.isEmpty ? QuickAdd.defaultName : trimmedName
            entry.nutrients = quickAddNutrients
        } else {
            entry.nutrients = previewNutrients
            entry.quantity = quantity
        }
        entry.meal = meal
        dismiss()
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let food = FoodItem(name: "Weet-Bix", nutrientsPer100g: Nutrients(kcal: 349, proteinG: 12.9, carbsG: 67.1, fatG: 1.3))
    container.mainContext.insert(food)
    let entry = DiaryEntry(logging: food, quantity: 2, serving: ServingSize(label: "2 biscuits", gramWeight: 30), meal: .breakfast)
    container.mainContext.insert(entry)
    return EditDiaryEntryView(entry: entry)
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
