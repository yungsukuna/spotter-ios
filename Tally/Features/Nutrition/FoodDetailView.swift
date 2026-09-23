import SwiftData
import SwiftUI

/// Portion picker and save screen for a single food — either one already
/// saved (``FoodItem``) or a not-yet-saved search result (``FoodRecord``).
///
/// Both are handled by one screen because the picker itself doesn't care
/// where the numbers came from; ``Source`` only changes what `save()` has to
/// do first. A search result is never written to the store just for being
/// looked at — only ``save()`` calls ``FoodRecord/makeFoodItem()`` (or reuses
/// a matching cached food by barcode), so browsing results is free of side
/// effects.
struct FoodDetailView: View {
    enum Source {
        case existing(FoodItem)
        case record(FoodRecord)
    }

    let source: Source
    let initialMeal: Meal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Double
    @State private var selectedServing: ServingSize
    @State private var meal: Meal

    init(source: Source, initialMeal: Meal = Meal.suggested(at: Date())) {
        self.source = source
        self.initialMeal = initialMeal
        _meal = State(initialValue: initialMeal)
        _quantity = State(initialValue: 1)
        switch source {
        case .existing(let food):
            _selectedServing = State(initialValue: food.defaultServing)
        case .record(let record):
            _selectedServing = State(initialValue: record.defaultServing)
        }
    }

    private var title: String {
        switch source {
        case .existing(let food): food.displayTitle
        case .record(let record): record.brand.map { "\(record.name) · \($0)" } ?? record.name
        }
    }

    private var nutrientsPer100g: Nutrients {
        switch source {
        case .existing(let food): food.nutrientsPer100g
        case .record(let record): record.nutrientsPer100g
        }
    }

    private var availableServings: [ServingSize] {
        switch source {
        case .existing(let food): food.normalisedServings
        case .record(let record): record.normalisedServings
        }
    }

    /// Nutrition for the currently-selected quantity and serving. Recomputed
    /// on every change so the panel always matches the picker without a
    /// separate "preview" state to keep in sync.
    private var previewNutrients: Nutrients {
        nutrientsPer100g.scaled(byGrams: selectedServing.gramWeight * quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title).font(Theme.Typography.cardTitle)
                }

                Section("Portion") {
                    Picker("Serving", selection: $selectedServing) {
                        ForEach(availableServings) { serving in
                            Text(serving.label).tag(serving)
                        }
                    }
                    Stepper(value: $quantity, in: 0.25...50, step: 0.25) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text(QuantityFormatter.string(from: quantity))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
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
            .navigationTitle("Log Food")
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
        let food = resolvedFoodItem()
        food.markUsed()
        let entry = DiaryEntry(
            logging: food,
            quantity: quantity,
            serving: selectedServing,
            meal: meal
        )
        modelContext.insert(entry)
        WidgetSnapshotWriter.refresh(in: modelContext)
        dismiss()
    }

    /// The food to log against. A cached product is matched by barcode so
    /// re-searching something already scanned before doesn't create a
    /// duplicate `FoodItem` and trip the unique-barcode constraint.
    private func resolvedFoodItem() -> FoodItem {
        switch source {
        case .existing(let food):
            return food
        case .record(let record):
            if let barcode = record.barcode {
                var descriptor = FetchDescriptor<FoodItem>(
                    predicate: #Predicate<FoodItem> { $0.barcode == barcode }
                )
                descriptor.fetchLimit = 1
                if let existing = try? modelContext.fetch(descriptor).first {
                    return existing
                }
            }
            let food = record.makeFoodItem()
            modelContext.insert(food)
            return food
        }
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    let food = FoodItem(
        name: "Chicken breast, raw, boneless, skinless",
        nutrientsPer100g: Nutrients(kcal: 120, proteinG: 22.5, carbsG: 0, fatG: 2.6),
        servings: [ServingSize(label: "1 breast", gramWeight: 174)]
    )
    container.mainContext.insert(food)
    return FoodDetailView(source: .existing(food))
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
