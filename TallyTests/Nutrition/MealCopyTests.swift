import Foundation
import Testing

@testable import Tally

@MainActor
@Suite("MealCopy")
struct MealCopyTests {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    private func snapshot(
        name: String,
        kcal: Double?,
        food: FoodItem? = nil,
        quantity: Double = 1
    ) -> DiaryEntrySnapshot {
        DiaryEntrySnapshot(
            foodName: name,
            quantity: quantity,
            servingLabel: "100 g",
            servingGramWeight: 100,
            nutrients: Nutrients(kcal: kcal),
            food: food
        )
    }

    @Test("Copied entries land on the target day, not today")
    func copiedEntriesLandOnTargetDay() {
        let calendar = calendar("UTC")
        let targetKey = "2025-01-10"
        let entries = MealCopy.copies(
            of: [snapshot(name: "Oats", kcal: 200)],
            into: .breakfast,
            dayKey: targetKey,
            now: Date(),
            calendar: calendar
        )
        #expect(entries.count == 1)
        #expect(entries[0].dayKey == targetKey)
    }

    @Test("A DST-transition target day still keys correctly, in Pacific/Auckland")
    func dstTransitionTargetDayKeysCorrectly() {
        let calendar = calendar("Pacific/Auckland")
        // NZ daylight saving began 28 September 2025, so this calendar day
        // is only 23 hours long.
        let targetKey = "2025-09-28"
        let entries = MealCopy.copies(
            of: [snapshot(name: "Eggs", kcal: 150), snapshot(name: "Toast", kcal: 180)],
            into: .breakfast,
            dayKey: targetKey,
            now: Date(),
            calendar: calendar
        )
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.dayKey == targetKey })
    }

    @Test("A malformed target day key falls back without crashing")
    func malformedDayKeyDoesNotCrash() {
        let calendar = calendar("UTC")
        let entries = MealCopy.copies(
            of: [snapshot(name: "Oats", kcal: 200)],
            into: .breakfast,
            dayKey: "not-a-key",
            now: Date(),
            calendar: calendar
        )
        #expect(entries.count == 1)
    }

    @Test("Order is preserved via ascending timestamps")
    func orderIsPreserved() {
        let calendar = calendar("UTC")
        let entries = MealCopy.copies(
            of: [
                snapshot(name: "First", kcal: 100),
                snapshot(name: "Second", kcal: 200),
                snapshot(name: "Third", kcal: 300),
            ],
            into: .lunch,
            dayKey: "2025-03-01",
            now: Date(),
            calendar: calendar
        )
        #expect(entries.map(\.foodName) == ["First", "Second", "Third"])
        #expect(entries[0].loggedAt < entries[1].loggedAt)
        #expect(entries[1].loggedAt < entries[2].loggedAt)
    }

    @Test("nil nutrients stay nil after copying")
    func nilNutrientsStayNil() {
        let calendar = calendar("UTC")
        let entries = MealCopy.copies(
            of: [snapshot(name: "Mystery", kcal: nil)],
            into: .snack,
            dayKey: "2025-03-01",
            now: Date(),
            calendar: calendar
        )
        #expect(entries[0].nutrients.kcal == nil)
        #expect(entries[0].nutrients.isEmpty)
    }

    @Test("A copied entry of a deleted (unlinked) food keeps its snapshot")
    func copiedEntryOfDeletedFoodKeepsSnapshot() {
        let calendar = calendar("UTC")
        let entries = MealCopy.copies(
            of: [snapshot(name: "Discontinued Bar", kcal: 250, food: nil)],
            into: .snack,
            dayKey: "2025-03-01",
            now: Date(),
            calendar: calendar
        )
        #expect(entries[0].food == nil)
        #expect(entries[0].foodName == "Discontinued Bar")
        #expect(entries[0].nutrients.kcal == 250)
    }

    @Test("New entries get new IDs distinct from each other")
    func newIDsAreDistinct() {
        let calendar = calendar("UTC")
        let snap = snapshot(name: "Oats", kcal: 200)
        let entries = MealCopy.copies(
            of: [snap, snap],
            into: .breakfast,
            dayKey: "2025-03-01",
            now: Date(),
            calendar: calendar
        )
        #expect(entries[0].id != entries[1].id)
    }

    @Test("Copying into today's own day key uses the current time for the first item")
    func copyingIntoTodayUsesNow() {
        let calendar = calendar("UTC")
        let now = Date()
        let todayKey = DayKey.today(calendar: calendar, now: now)
        let entries = MealCopy.copies(
            of: [snapshot(name: "Oats", kcal: 200)],
            into: .breakfast,
            dayKey: todayKey,
            now: now,
            calendar: calendar
        )
        #expect(abs(entries[0].loggedAt.timeIntervalSince(now)) < 1)
    }

    @Test("Copying a food-backed entry keeps the food link and marks it used")
    func copyingKeepsFoodLinkAndMarksUsed() {
        let calendar = calendar("UTC")
        let food = FoodItem(name: "Chicken", nutrientsPer100g: Nutrients(kcal: 120))
        #expect(food.useCount == 0)

        let entries = MealCopy.copies(
            of: [snapshot(name: "Chicken", kcal: 120, food: food)],
            into: .lunch,
            dayKey: "2025-03-01",
            now: Date(),
            calendar: calendar
        )

        #expect(entries[0].food === food)
        #expect(food.useCount == 1)
        // The copy uses the snapshot's own nutrients, not a fresh read
        // through the food.
        #expect(entries[0].nutrients.kcal == 120)
    }

    @Test("Empty input produces no entries")
    func emptyInputProducesNoEntries() {
        let calendar = calendar("UTC")
        let entries = MealCopy.copies(of: [], into: .lunch, dayKey: "2025-03-01", now: Date(), calendar: calendar)
        #expect(entries.isEmpty)
    }
}
