import Foundation
import Testing

@testable import Tally

@MainActor
@Suite("CustomFoodDraft")
struct CustomFoodDraftTests {

    @Test("A blank nutrient field parses to nil, not zero")
    func blankFieldIsUnknown() {
        var draft = CustomFoodDraft()
        draft.name = "Mystery Bar"
        draft.kcalText = "250"
        draft.fiberText = ""

        #expect(draft.nutrients.kcal == 250)
        #expect(draft.nutrients.fiberG == nil)
    }

    @Test("Unparsable text is treated as unknown rather than crashing")
    func garbageTextIsUnknown() {
        var draft = CustomFoodDraft()
        draft.kcalText = "not a number"
        #expect(draft.nutrients.kcal == nil)
    }

    @Test("A name is required to be valid; whitespace does not count")
    func nameIsRequired() {
        var draft = CustomFoodDraft()
        draft.kcalText = "100"
        #expect(!draft.isValid)

        draft.name = "   "
        #expect(!draft.isValid)

        draft.name = "Something"
        #expect(draft.isValid)
    }

    @Test("Applying sets isCustom and source regardless of the food's prior origin")
    func applyMarksCustom() {
        var draft = CustomFoodDraft()
        draft.name = "Homemade Soup"
        draft.kcalText = "80"

        let food = FoodItem(name: "placeholder", source: .openFoodFacts)
        draft.apply(to: food)

        #expect(food.name == "Homemade Soup")
        #expect(food.isCustom == true)
        #expect(food.source == .custom)
        #expect(food.nutrientsPer100g.kcal == 80)
    }

    @Test("Loading from an existing food round-trips its values")
    func loadsFromExistingFood() {
        let food = FoodItem(
            name: "Weet-Bix",
            brand: "Sanitarium",
            nutrientsPer100g: Nutrients(kcal: 349, proteinG: 12.9),
            servings: [ServingSize(label: "2 biscuits", gramWeight: 30)]
        )
        let draft = CustomFoodDraft(food: food)

        #expect(draft.name == "Weet-Bix")
        #expect(draft.brand == "Sanitarium")
        #expect(draft.kcalText == "349")
        #expect(draft.servings.count == 1)
    }

    @Test("Brand trims to nil when blank")
    func blankBrandBecomesNil() {
        var draft = CustomFoodDraft()
        draft.name = "Thing"
        draft.brand = "   "
        #expect(draft.trimmedBrand == nil)
    }

    @Test("Brand is preserved when non-blank")
    func nonBlankBrandIsKept() {
        var draft = CustomFoodDraft()
        draft.name = "Thing"
        draft.brand = "  Acme  "
        #expect(draft.trimmedBrand == "Acme")
    }
}
