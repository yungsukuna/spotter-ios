import Foundation

/// Aggregated nutrition for one day's diary entries, plus progress against the
/// day's goal.
///
/// A plain struct over already-fetched entries — not a computed property that
/// reaches back into SwiftData — so the aggregation arithmetic (and the
/// "unknown never becomes zero" rule it inherits from ``Nutrients``) can be
/// unit tested without a `ModelContext` at all.
struct DayTotals: Hashable {
    var consumed: Nutrients
    var goal: Nutrients

    /// Sums every entry's already-scaled nutrition snapshot. ``Nutrients/+(_:_:)``
    /// treats "neither side knows this value" as the only case that stays nil,
    /// so a day mixing complete and partial foods still totals correctly.
    init(entries: [DiaryEntry], goal: Nutrients) {
        self.consumed = Nutrients.total(of: entries.map(\.nutrients))
        self.goal = goal
    }

    init(consumed: Nutrients, goal: Nutrients) {
        self.consumed = consumed
        self.goal = goal
    }

    /// Calories left to eat today. Nil when either side is unknown, which
    /// keeps a day containing a food with no calorie figure from producing a
    /// misleadingly precise "remaining" number.
    var kcalRemaining: Double? {
        guard let goalKcal = goal.kcal, let consumedKcal = consumed.kcal else { return nil }
        return goalKcal - consumedKcal
    }

    /// Progress toward the calorie goal, clamped to `0...1` for a progress bar.
    /// Zero rather than crashing or NaN-ing when the goal is unset or zero.
    var kcalProgress: Double {
        guard let goalKcal = goal.kcal, goalKcal > 0, let consumedKcal = consumed.kcal else {
            return 0
        }
        return min(max(consumedKcal / goalKcal, 0), 1)
    }
}
