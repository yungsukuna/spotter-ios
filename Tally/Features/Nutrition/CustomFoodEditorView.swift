import SwiftData
import SwiftUI

/// The editable state behind ``CustomFoodEditorView``, pulled out of the view
/// so parsing and validation can be tested without SwiftUI.
struct CustomFoodDraft: Equatable {
    var name: String = ""
    var brand: String = ""
    var kcalText: String = ""
    var proteinText: String = ""
    var carbsText: String = ""
    var fatText: String = ""
    var satFatText: String = ""
    var sugarText: String = ""
    var fiberText: String = ""
    var sodiumText: String = ""
    var servings: [ServingSize] = []

    init() {}

    /// Load an existing food's values for editing.
    init(food: FoodItem) {
        name = food.name
        brand = food.brand ?? ""
        kcalText = Self.string(food.nutrientsPer100g.kcal)
        proteinText = Self.string(food.nutrientsPer100g.proteinG)
        carbsText = Self.string(food.nutrientsPer100g.carbsG)
        fatText = Self.string(food.nutrientsPer100g.fatG)
        satFatText = Self.string(food.nutrientsPer100g.satFatG)
        sugarText = Self.string(food.nutrientsPer100g.sugarG)
        fiberText = Self.string(food.nutrientsPer100g.fiberG)
        sodiumText = Self.string(food.nutrientsPer100g.sodiumMG)
        servings = food.servings
    }

    private static func string(_ value: Double?) -> String {
        guard let value else { return "" }
        return QuantityFormatter.string(from: value)
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var trimmedBrand: String? {
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A name is the only hard requirement — every nutrient field is
    /// legitimately optional, matching ``Nutrients``' own "nil means unknown"
    /// rule rather than forcing a zero into a field nobody measured.
    var isValid: Bool { !trimmedName.isEmpty }

    /// Parses the text fields into a nutrition panel. A blank field becomes
    /// `nil` (unknown), never `0` — leaving "Fiber" empty must not claim the
    /// food has none.
    var nutrients: Nutrients {
        Nutrients(
            kcal: Double(kcalText),
            proteinG: Double(proteinText),
            carbsG: Double(carbsText),
            fatG: Double(fatText),
            satFatG: Double(satFatText),
            sugarG: Double(sugarText),
            fiberG: Double(fiberText),
            sodiumMG: Double(sodiumText)
        )
    }

    /// Apply this draft onto a food, marking it custom. Shared by both the
    /// create and edit paths so they can never drift apart.
    func apply(to food: FoodItem) {
        food.name = trimmedName
        food.brand = trimmedBrand
        food.nutrientsPer100g = nutrients
        food.servings = servings
        food.isCustom = true
        food.source = .custom
    }
}

/// Manual food entry: create a brand-new custom food, edit an existing one,
/// or finish the "scanned a barcode Open Food Facts has never heard of" flow.
///
/// Accepting an optional prefilled barcode is what makes the third case work
/// — the barcode scanner (built separately) hands off here on
/// ``FoodDataError/productNotFound``, and saving attaches that barcode to the
/// new food so re-scanning the same product finds it next time.
struct CustomFoodEditorView: View {
    private let existingFood: FoodItem?
    private let prefilledBarcode: String?
    var onSave: ((FoodItem) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CustomFoodDraft
    @State private var newServingLabel = ""
    @State private var newServingGrams = ""

    init(
        existingFood: FoodItem? = nil,
        prefilledName: String = "",
        prefilledBrand: String? = nil,
        prefilledBarcode: String? = nil,
        onSave: ((FoodItem) -> Void)? = nil
    ) {
        self.existingFood = existingFood
        self.prefilledBarcode = prefilledBarcode
        self.onSave = onSave
        if let existingFood {
            _draft = State(initialValue: CustomFoodDraft(food: existingFood))
        } else {
            var draft = CustomFoodDraft()
            draft.name = prefilledName
            draft.brand = prefilledBrand ?? ""
            _draft = State(initialValue: draft)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $draft.name)
                    TextField("Brand (optional)", text: $draft.brand)
                    if let prefilledBarcode {
                        LabeledContent("Barcode", value: prefilledBarcode)
                    }
                }

                Section("Nutrition per 100 g") {
                    numberField("Calories", text: $draft.kcalText)
                    numberField("Protein (g)", text: $draft.proteinText)
                    numberField("Carbs (g)", text: $draft.carbsText)
                    numberField("Fat (g)", text: $draft.fatText)
                }

                Section("Additional (optional)") {
                    numberField("Saturated Fat (g)", text: $draft.satFatText)
                    numberField("Sugar (g)", text: $draft.sugarText)
                    numberField("Fiber (g)", text: $draft.fiberText)
                    numberField("Sodium (mg)", text: $draft.sodiumText)
                }

                Section("Servings") {
                    ForEach(draft.servings) { serving in
                        HStack {
                            Text(serving.label)
                            Spacer()
                            Text(Format.grams(serving.gramWeight))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .onDelete { indices in
                        draft.servings.remove(atOffsets: indices)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("Label, e.g. 1 cup", text: $newServingLabel)
                        TextField("Grams", text: $newServingGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Button {
                            addServing()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(
                            newServingLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || Double(newServingGrams) == nil
                        )
                    }
                }
            }
            .navigationTitle(existingFood == nil ? "New Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.isValid)
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
    }

    private func addServing() {
        guard let grams = Double(newServingGrams) else { return }
        let label = newServingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        draft.servings.append(ServingSize(label: label, gramWeight: grams))
        newServingLabel = ""
        newServingGrams = ""
    }

    private func save() {
        guard draft.isValid else { return }
        let (food, isNew) = resolvedFood()
        draft.apply(to: food)
        if food.barcode == nil {
            food.barcode = prefilledBarcode
        }
        if isNew {
            modelContext.insert(food)
        }
        onSave?(food)
        dismiss()
    }

    /// Finds a food to edit in place before creating a new one, so saving
    /// twice against the same prefilled barcode (e.g. the user backs out and
    /// re-enters this screen) updates the earlier row instead of tripping the
    /// unique-barcode constraint with a duplicate.
    private func resolvedFood() -> (food: FoodItem, isNew: Bool) {
        if let existingFood {
            return (existingFood, false)
        }
        if let prefilledBarcode, !prefilledBarcode.isEmpty {
            var descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate<FoodItem> { $0.barcode == prefilledBarcode }
            )
            descriptor.fetchLimit = 1
            if let alreadyStored = try? modelContext.fetch(descriptor).first {
                return (alreadyStored, false)
            }
        }
        return (FoodItem(name: draft.trimmedName), true)
    }
}

#Preview {
    CustomFoodEditorView()
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
