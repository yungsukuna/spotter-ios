import Foundation

/// Pure logic for turning a meal section into a reusable ``SavedMeal`` and
/// for logging one back into the diary.
enum SavedMealLogging {

    /// Snapshot diary entries into ``SavedMealItem``s, in order.
    static func items(from entries: [DiaryEntrySnapshot]) -> [SavedMealItem] {
        entries.enumerated().map { index, entry in
            SavedMealItem(
                order: index,
                foodID: entry.food?.id,
                foodName: entry.foodName,
                brandName: entry.brandName,
                quantity: entry.quantity,
                servingLabel: entry.servingLabel,
                servingGramWeight: entry.servingGramWeight,
                nutrientsSnapshot: entry.nutrients
            )
        }
    }

    /// Builds diary entries for logging a saved meal, one per item.
    ///
    /// For each item, if `foodID` resolves to a still-live `FoodItem` in
    /// `resolvingFoods`, the entry is built with `DiaryEntry(logging:...)`,
    /// which reads that food's *current* per-100 g nutrition — the meal was
    /// saved with a live link, so logging it again should reflect any edits
    /// made to the food since. Otherwise the entry falls back to the item's
    /// own `nutrientsSnapshot`, exactly as a deleted food would. Either way
    /// the resulting `DiaryEntry` snapshots at log time, same as every other
    /// diary entry — a later edit to the food never rewrites this log.
    ///
    /// Each item's `loggedAt` gets one more second than the last, purely to
    /// keep the saved order stable when entries are later sorted.
    static func entries(
        for items: [SavedMealItem],
        resolvingFoods: [UUID: FoodItem],
        meal: Meal,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> [DiaryEntry] {
        items.enumerated().map { index, item in
            let loggedAt = calendar.date(byAdding: .second, value: index, to: date) ?? date
            let serving = ServingSize(label: item.servingLabel, gramWeight: item.servingGramWeight)
            if let foodID = item.foodID, let food = resolvingFoods[foodID] {
                return DiaryEntry(
                    logging: food,
                    quantity: item.quantity,
                    serving: serving,
                    meal: meal,
                    at: loggedAt,
                    calendar: calendar
                )
            }
            return DiaryEntry(
                loggedAt: loggedAt,
                meal: meal,
                foodName: item.foodName,
                brandName: item.brandName,
                quantity: item.quantity,
                serving: serving,
                nutrients: item.nutrientsSnapshot,
                calendar: calendar
            )
        }
    }
}
