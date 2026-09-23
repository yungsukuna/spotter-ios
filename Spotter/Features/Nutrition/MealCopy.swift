import Foundation

/// A value snapshot of one diary entry's loggable fields.
///
/// Pure logic (``MealCopy``, ``SavedMealLogging``) works over this rather
/// than over `DiaryEntry` itself, so most of it can be tested without a
/// `ModelContext`. ``food`` is the one field that isn't a plain value — it is
/// carried through unchanged, never re-read from, matching the rule that a
/// copy must not pull nutrition back through the live food.
struct DiaryEntrySnapshot {
    var foodName: String
    var brandName: String?
    var quantity: Double
    var servingLabel: String
    var servingGramWeight: Double
    var nutrients: Nutrients
    var food: FoodItem?

    init(
        foodName: String,
        brandName: String? = nil,
        quantity: Double,
        servingLabel: String,
        servingGramWeight: Double,
        nutrients: Nutrients,
        food: FoodItem? = nil
    ) {
        self.foodName = foodName
        self.brandName = brandName
        self.quantity = quantity
        self.servingLabel = servingLabel
        self.servingGramWeight = servingGramWeight
        self.nutrients = nutrients
        self.food = food
    }

    /// Snapshot an already-logged entry.
    init(entry: DiaryEntry) {
        foodName = entry.foodName
        brandName = entry.brandName
        quantity = entry.quantity
        servingLabel = entry.servingLabel
        servingGramWeight = entry.servingGramWeight
        nutrients = entry.nutrients
        food = entry.food
    }
}

/// Copies a set of already-logged entries onto another day and/or meal.
///
/// Used by "Copy from Yesterday" and "Copy from…". The target is always the
/// day currently open in the diary, which may or may not be today — see the
/// note on `NutritionDiaryView`.
enum MealCopy {

    /// Builds new diary entries for `snapshots`, landing on `dayKey`.
    ///
    /// - `loggedAt` is the target day's start plus the *current* time of day,
    ///   so entries sort sensibly against anything else logged that day. If
    ///   the target day is today, `now` is used directly instead — recomputing
    ///   it from components would needlessly risk drifting by a second.
    /// - Each subsequent item gets one more second added, purely to keep the
    ///   source order stable when entries are later sorted by `loggedAt`.
    /// - Every field is copied from the snapshot verbatim, including
    ///   `nutrients` — this never reads back through `food`, so an edited or
    ///   since-corrected food does not change what a copy logs.
    /// - `food?.markUsed()` is still called, because the copy is a genuine
    ///   new log of that food.
    static func copies(
        of snapshots: [DiaryEntrySnapshot],
        into meal: Meal,
        dayKey: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DiaryEntry] {
        let todayKey = DayKey.today(calendar: calendar, now: now)
        let baseTime: Date
        if dayKey == todayKey {
            baseTime = now
        } else if let dayStart = DayKey.date(from: dayKey, calendar: calendar) {
            let timeOfDay = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
            baseTime = calendar.date(byAdding: timeOfDay, to: dayStart) ?? dayStart
        } else {
            baseTime = now
        }

        return snapshots.enumerated().map { index, snapshot in
            let loggedAt = calendar.date(byAdding: .second, value: index, to: baseTime) ?? baseTime
            let entry = DiaryEntry(
                loggedAt: loggedAt,
                meal: meal,
                foodName: snapshot.foodName,
                brandName: snapshot.brandName,
                quantity: snapshot.quantity,
                serving: ServingSize(label: snapshot.servingLabel, gramWeight: snapshot.servingGramWeight),
                nutrients: snapshot.nutrients,
                food: snapshot.food,
                calendar: calendar
            )
            snapshot.food?.markUsed()
            return entry
        }
    }
}
