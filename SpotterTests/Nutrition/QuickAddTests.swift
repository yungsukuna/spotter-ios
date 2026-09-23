import Foundation
import Testing

@testable import Spotter

@MainActor
@Suite("QuickAdd")
struct QuickAddTests {

    @Test("Blank macro fields become nil, not zero")
    func blankMacrosAreNil() throws {
        let nutrients = try #require(QuickAdd.makeNutrients(kcalText: "250"))
        #expect(nutrients.kcal == 250)
        #expect(nutrients.proteinG == nil)
        #expect(nutrients.carbsG == nil)
        #expect(nutrients.fatG == nil)
    }

    @Test("A typed zero is kept as zero, not treated as blank")
    func zeroIsKeptAsZero() throws {
        let nutrients = try #require(QuickAdd.makeNutrients(kcalText: "300", proteinText: "0"))
        #expect(nutrients.proteinG == 0)
    }

    @Test("Blank calories is rejected")
    func blankKcalIsRejected() {
        #expect(QuickAdd.makeNutrients(kcalText: "") == nil)
        #expect(QuickAdd.makeNutrients(kcalText: "   ") == nil)
    }

    @Test("Unparsable calories text is rejected")
    func invalidKcalIsRejected() {
        #expect(QuickAdd.makeNutrients(kcalText: "not a number") == nil)
    }

    @Test("A comma decimal separator parses like a period")
    func commaSeparatorParses() throws {
        let nutrients = try #require(QuickAdd.makeNutrients(kcalText: "250,5", proteinText: "12,5"))
        #expect(nutrients.kcal == 250.5)
        #expect(nutrients.proteinG == 12.5)
    }

    @Test("An unparsable macro field is unknown rather than crashing")
    func garbageMacroIsUnknown() throws {
        let nutrients = try #require(QuickAdd.makeNutrients(kcalText: "250", proteinText: "lots"))
        #expect(nutrients.proteinG == nil)
    }

    @Test("isQuickAdd is true for a quick-add entry")
    func isQuickAddTrueForQuickAdd() {
        let entry = QuickAdd.makeEntry(name: "Restaurant meal", nutrients: Nutrients(kcal: 600), meal: .dinner)
        #expect(entry.isQuickAdd)
        #expect(entry.food == nil)
        #expect(entry.servingGramWeight == 0)
    }

    @Test("isQuickAdd is false for a catalogue-food entry, even after its food is deleted")
    func isQuickAddFalseForDeletedFoodEntry() {
        let food = FoodItem(name: "Weet-Bix", nutrientsPer100g: Nutrients(kcal: 349))
        let entry = DiaryEntry(
            logging: food,
            quantity: 1,
            serving: ServingSize(label: "30 g", gramWeight: 30),
            meal: .breakfast
        )
        // Simulate the food having been deleted — SwiftData nullifies the
        // link, but the entry keeps its real (non-zero) serving weight.
        entry.food = nil
        #expect(!entry.isQuickAdd)
    }

    @Test("A blank name falls back to \"Quick add\"")
    func blankNameFallsBack() {
        let entry = QuickAdd.makeEntry(name: "   ", nutrients: Nutrients(kcal: 100), meal: .snack)
        #expect(entry.foodName == "Quick add")
    }

    @Test("A trimmed name is kept as typed")
    func trimmedNameIsKept() {
        let entry = QuickAdd.makeEntry(name: "  Cafe lunch  ", nutrients: Nutrients(kcal: 500), meal: .lunch)
        #expect(entry.foodName == "Cafe lunch")
    }

    @Test("The entry lands in the requested meal with quantity 1")
    func entryUsesRequestedMealAndQuantity() {
        let entry = QuickAdd.makeEntry(name: "Snack", nutrients: Nutrients(kcal: 150), meal: .snack)
        #expect(entry.meal == .snack)
        #expect(entry.quantity == 1)
    }
}
