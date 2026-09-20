import Foundation

/// Pure maths behind the Today dashboard: nutrition-vs-goal, and the 7-day
/// weekly strip.
///
/// Kept free of SwiftUI and SwiftData, and free of any reference to the
/// Nutrition or Workouts view types (which belong to other workstreams) — it
/// operates on plain `Nutrients` values and day keys, so it can be unit
/// tested directly.
enum DashboardAggregation {

    // MARK: - Nutrition

    /// Kcal and macros consumed against goals, for the headline card and the
    /// macro bars.
    struct NutritionSummary: Hashable, Sendable {
        var consumed: Nutrients
        var goal: Nutrients

        /// Consumed kcal over goal kcal. Zero when the goal itself is zero
        /// (never configured), rather than dividing by zero.
        var kcalFraction: Double {
            guard let goalKcal = goal.kcal, goalKcal > 0 else { return 0 }
            return (consumed.effectiveKcal ?? 0) / goalKcal
        }

        /// Fraction reached for a single macro, e.g. `\.proteinG`. Unknown
        /// consumption reads as zero progress rather than crashing the bar.
        func macroFraction(_ keyPath: KeyPath<Nutrients, Double?>) -> Double {
            guard let goalValue = goal[keyPath: keyPath], goalValue > 0 else { return 0 }
            return (consumed[keyPath: keyPath] ?? 0) / goalValue
        }
    }

    /// Sums nutrition across every logged portion for the day — however many
    /// meals it was split across — against the day's goal.
    static func nutritionSummary(entries: [Nutrients], goal: Nutrients) -> NutritionSummary {
        NutritionSummary(consumed: Nutrients.total(of: entries), goal: goal)
    }

    // MARK: - Weekly strip

    /// One day's at-a-glance status for the weekly strip.
    struct DayGlance: Hashable, Identifiable, Sendable {
        var dayKey: String
        var kcalFraction: Double
        var waterFraction: Double
        var hasWorkout: Bool
        var id: String { dayKey }
    }

    /// Builds one `DayGlance` per key in `keys`, in order.
    ///
    /// A day with nothing logged still appears, at zero on both fractions and
    /// no workout — it must not be dropped from the strip, the same rule
    /// ``WaterAggregation/dailyTotals(records:keys:goalML:)`` follows for the
    /// water history chart.
    static func weekGlances(
        keys: [String],
        nutrientsByDay: [String: [Nutrients]],
        kcalGoal: Double,
        waterByDay: [String: Double],
        waterGoalML: Double,
        workoutDayKeys: Set<String>
    ) -> [DayGlance] {
        keys.map { key in
            let dayTotal = Nutrients.total(of: nutrientsByDay[key] ?? [])
            let kcalFraction = kcalGoal > 0 ? (dayTotal.effectiveKcal ?? 0) / kcalGoal : 0
            let waterFraction = waterGoalML > 0 ? (waterByDay[key] ?? 0) / waterGoalML : 0
            return DayGlance(
                dayKey: key,
                kcalFraction: kcalFraction,
                waterFraction: waterFraction,
                hasWorkout: workoutDayKeys.contains(key)
            )
        }
    }
}
