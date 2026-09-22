import Foundation
import Testing

@testable import Tally

@MainActor
@Suite("SavedMealLogging")
struct SavedMealLoggingTests {

    private func snapshot(
        name: String,
        kcal: Double?,
        protein: Double? = nil,
        food: FoodItem? = nil,
        quantity: Double = 1,
        gramWeight: Double = 100
    ) -> DiaryEntrySnapshot {
        DiaryEntrySnapshot(
            foodName: name,
            quantity: quantity,
            servingLabel: "\(Int(gramWeight)) g",
            servingGramWeight: gramWeight,
            nutrients: Nutrients(kcal: kcal, proteinG: protein),
            food: food
        )
    }

    @Test("Snapshot to items to entries round-trips the nutrition")
    func roundTrips() {
        let snapshots = [snapshot(name: "Oats", kcal: 190, protein: 7)]
        let items = SavedMealLogging.items(from: snapshots)
        #expect(items.count == 1)
        #expect(items[0].order == 0)
        #expect(items[0].nutrientsSnapshot.kcal == 190)
        #expect(items[0].foodID == nil)

        let entries = SavedMealLogging.entries(for: items, resolvingFoods: [:], meal: .breakfast)
        #expect(entries.count == 1)
        #expect(entries[0].nutrients.kcal == 190)
        #expect(entries[0].nutrients.proteinG == 7)
        #expect(entries[0].meal == .breakfast)
    }

    @Test("Items preserve source order")
    func itemsPreserveOrder() {
        let snapshots = [snapshot(name: "First", kcal: 100), snapshot(name: "Second", kcal: 200)]
        let items = SavedMealLogging.items(from: snapshots)
        #expect(items.map(\.order) == [0, 1])
        #expect(items.map(\.foodName) == ["First", "Second"])
    }

    @Test("A food-backed snapshot captures the food's ID")
    func itemsCaptureFoodID() {
        let food = FoodItem(name: "Chicken", nutrientsPer100g: Nutrients(kcal: 120))
        let items = SavedMealLogging.items(from: [snapshot(name: "Chicken", kcal: 120, food: food)])
        #expect(items[0].foodID == food.id)
    }

    @Test("A deleted food falls back to the item's own snapshot nutrition")
    func deletedFoodFallsBackToSnapshot() {
        let item = SavedMealItem(
            order: 0,
            foodID: UUID(),
            foodName: "Discontinued Bar",
            quantity: 1,
            servingLabel: "1 bar",
            servingGramWeight: 45,
            nutrientsSnapshot: Nutrients(kcal: 210, proteinG: 5)
        )
        let entries = SavedMealLogging.entries(for: [item], resolvingFoods: [:], meal: .snack)
        #expect(entries[0].nutrients.kcal == 210)
        #expect(entries[0].nutrients.proteinG == 5)
        #expect(entries[0].food == nil)
    }

    @Test("A live food uses its current per-100 g values, not the stale snapshot")
    func liveFoodUsesCurrentValues() {
        let food = FoodItem(name: "Chicken Breast", nutrientsPer100g: Nutrients(kcal: 120, proteinG: 22.5))
        let item = SavedMealItem(
            order: 0,
            foodID: food.id,
            foodName: "Chicken Breast",
            quantity: 2,
            servingLabel: "100 g",
            servingGramWeight: 100,
            // Deliberately stale, to prove the live path ignores it.
            nutrientsSnapshot: Nutrients(kcal: 999, proteinG: 999)
        )
        let entries = SavedMealLogging.entries(for: [item], resolvingFoods: [food.id: food], meal: .lunch)
        #expect(entries[0].nutrients.kcal == 240)
        #expect(entries[0].nutrients.proteinG == 45)
        #expect(entries[0].food === food)
    }

    @Test("Totals preserve nil vs zero")
    func totalsPreserveNilVsZero() {
        let savedMeal = SavedMeal(name: "Mixed", items: [
            SavedMealItem(order: 0, foodName: "A", quantity: 1, servingLabel: "100 g", servingGramWeight: 100, nutrientsSnapshot: Nutrients(kcal: 100, fiberG: nil)),
            SavedMealItem(order: 1, foodName: "B", quantity: 1, servingLabel: "100 g", servingGramWeight: 100, nutrientsSnapshot: Nutrients(kcal: 200, fiberG: 5)),
        ])
        #expect(savedMeal.totalNutrients.kcal == 300)
        // One item knew fibre, so the total knows it too — not poisoned to
        // nil by the item that didn't.
        #expect(savedMeal.totalNutrients.fiberG == 5)

        let allUnknown = SavedMeal(name: "Unknown", items: [
            SavedMealItem(order: 0, foodName: "A", quantity: 1, servingLabel: "100 g", servingGramWeight: 100, nutrientsSnapshot: Nutrients(kcal: 100, fiberG: nil)),
        ])
        #expect(allUnknown.totalNutrients.fiberG == nil)
    }

    @Test("Logging a saved meal marks it used")
    func loggingMarksUsed() {
        let savedMeal = SavedMeal(name: "Breakfast Combo", items: [
            SavedMealItem(order: 0, foodName: "Oats", quantity: 1, servingLabel: "100 g", servingGramWeight: 100, nutrientsSnapshot: Nutrients(kcal: 190)),
        ])
        #expect(savedMeal.useCount == 0)
        #expect(savedMeal.lastUsedAt == nil)

        savedMeal.markUsed()

        #expect(savedMeal.useCount == 1)
        #expect(savedMeal.lastUsedAt != nil)
    }

    @Test("Entries built from a saved meal keep ascending timestamps")
    func entriesKeepAscendingTimestamps() {
        let items = SavedMealLogging.items(from: [
            snapshot(name: "First", kcal: 100),
            snapshot(name: "Second", kcal: 200),
        ])
        let entries = SavedMealLogging.entries(for: items, resolvingFoods: [:], meal: .dinner)
        #expect(entries[0].loggedAt <= entries[1].loggedAt)
    }

    @Test("Empty items produce no entries")
    func emptyItemsProduceNoEntries() {
        #expect(SavedMealLogging.entries(for: [], resolvingFoods: [:], meal: .lunch).isEmpty)
    }
}
