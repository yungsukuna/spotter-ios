import Foundation
import Testing

@testable import Tally

@MainActor
@Suite("DayTotals")
struct DayTotalsTests {

    private func entry(kcal: Double?, protein: Double? = nil, meal: Meal = .breakfast) -> DiaryEntry {
        let food = FoodItem(name: "Test Food", nutrientsPer100g: Nutrients(kcal: kcal, proteinG: protein))
        return DiaryEntry(logging: food, quantity: 1, serving: .hundredGrams, meal: meal)
    }

    @Test("Totals sum kcal across meals")
    func sumsAcrossMeals() {
        let entries = [
            entry(kcal: 300, meal: .breakfast),
            entry(kcal: 500, meal: .lunch),
            entry(kcal: 700, meal: .dinner),
        ]
        let totals = DayTotals(entries: entries, goal: Nutrients(kcal: 2000))
        #expect(totals.consumed.kcal == 1500)
    }

    @Test("An entry with unknown nutrition contributes nothing rather than poisoning the total")
    func unknownEntryDoesNotCorruptTotal() {
        let entries = [
            entry(kcal: 300),
            // e.g. logged from a search record that had no calorie figure.
            entry(kcal: nil),
        ]
        let totals = DayTotals(entries: entries, goal: Nutrients(kcal: 2000))
        #expect(totals.consumed.kcal == 300)
    }

    @Test("Totals of an empty day are all unknown, not zero")
    func emptyDayIsEmpty() {
        let totals = DayTotals(entries: [], goal: Nutrients(kcal: 2000))
        #expect(totals.consumed.kcal == nil)
        #expect(totals.consumed.isEmpty)
    }

    @Test("Remaining calories is nil when the goal or the total is unknown")
    func remainingNilWhenUnknown() {
        let totals = DayTotals(consumed: Nutrients(kcal: nil), goal: Nutrients(kcal: 2000))
        #expect(totals.kcalRemaining == nil)
    }

    @Test("Remaining calories subtracts consumed from goal")
    func remainingSubtracts() {
        let totals = DayTotals(consumed: Nutrients(kcal: 1500), goal: Nutrients(kcal: 2000))
        #expect(totals.kcalRemaining == 500)
    }

    @Test("Remaining calories can go negative when over goal")
    func remainingCanBeNegative() {
        let totals = DayTotals(consumed: Nutrients(kcal: 2500), goal: Nutrients(kcal: 2000))
        #expect(totals.kcalRemaining == -500)
    }

    @Test("Progress is clamped to 1 when over goal")
    func progressClampsAtOne() {
        let totals = DayTotals(consumed: Nutrients(kcal: 3000), goal: Nutrients(kcal: 2000))
        #expect(totals.kcalProgress == 1)
    }

    @Test("Progress is zero when the goal is unknown or zero")
    func progressZeroWithoutGoal() {
        let unknownGoal = DayTotals(consumed: Nutrients(kcal: 500), goal: Nutrients(kcal: nil))
        #expect(unknownGoal.kcalProgress == 0)

        let zeroGoal = DayTotals(consumed: Nutrients(kcal: 500), goal: Nutrients(kcal: 0))
        #expect(zeroGoal.kcalProgress == 0)
    }

    @Test("Quantity scaling feeds correctly into the day total")
    func scaledQuantityAffectsTotal() {
        let food = FoodItem(name: "Chicken", nutrientsPer100g: Nutrients(kcal: 120, proteinG: 22.5))
        let entry = DiaryEntry(logging: food, quantity: 1.5, serving: .hundredGrams, meal: .lunch)
        let totals = DayTotals(entries: [entry], goal: Nutrients(kcal: 2000))
        #expect(totals.consumed.kcal == 180)
        #expect(totals.consumed.proteinG == 33.75)
    }
}
