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

    /// Calories left to eat today. Uses ``Nutrients/effectiveKcal`` so a food
    /// with macros but no stated calorie figure still counts, matching the
    /// Today tab. Nil only when even the Atwater estimate is unavailable.
    var kcalRemaining: Double? {
        guard let goalKcal = goal.kcal, let consumedKcal = consumed.effectiveKcal else { return nil }
        return goalKcal - consumedKcal
    }

    /// Progress toward the calorie goal, clamped to `0...1` for a progress bar.
    /// Uses ``Nutrients/effectiveKcal`` so this matches
    /// ``DashboardAggregation.NutritionSummary/kcalFraction`` for the same day.
    /// Zero rather than crashing or NaN-ing when the goal is unset or zero.
    var kcalProgress: Double {
        guard let goalKcal = goal.kcal, goalKcal > 0 else { return 0 }
        guard let consumedKcal = consumed.effectiveKcal else { return 0 }
        return min(max(consumedKcal / goalKcal, 0), 1)
    }
}
