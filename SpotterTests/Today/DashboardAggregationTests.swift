import Foundation
import Testing

@testable import Spotter

/// The pure maths behind the Today dashboard: nutrition-vs-goal and the
/// 7-day weekly strip. See `DashboardAggregation`.
@Suite("DashboardAggregation")
struct DashboardAggregationTests {

    @Test("Nutrition totals sum across every logged meal")
    func nutritionSummaryAggregatesAcrossMeals() {
        let breakfast = Nutrients(kcal: 300, proteinG: 20, carbsG: 30, fatG: 10)
        let lunch = Nutrients(kcal: 500, proteinG: 30, carbsG: 40)
        let goal = Nutrients(kcal: 2000, proteinG: 150, carbsG: 200, fatG: 67)

        let summary = DashboardAggregation.nutritionSummary(entries: [breakfast, lunch], goal: goal)

        #expect(summary.consumed.kcal == 800)
        #expect(summary.consumed.proteinG == 50)
        #expect(summary.consumed.carbsG == 70)
        // Lunch had no fat figure at all; per `Nutrients.+`, a value known on
        // only one side still contributes rather than poisoning the sum.
        #expect(summary.consumed.fatG == 10)
        #expect(abs(summary.kcalFraction - 0.4) < 0.0001)
    }

    @Test("Nutrition summary over no entries is empty, not a crash")
    func nutritionSummaryOverNoEntries() {
        let summary = DashboardAggregation.nutritionSummary(entries: [], goal: Nutrients(kcal: 2000))
        #expect(summary.consumed.isEmpty)
        #expect(summary.kcalFraction == 0)
    }

    @Test("Kcal fraction uses effectiveKcal so a macros-only food still counts")
    func kcalFractionUsesEffectiveKcal() {
        let summary = DashboardAggregation.NutritionSummary(
            consumed: Nutrients(kcal: nil, proteinG: 25, carbsG: 0, fatG: 0),
            goal: Nutrients(kcal: 1000)
        )
        #expect(abs(summary.kcalFraction - 0.1) < 0.0001)
    }

    @Test("Kcal fraction is zero when the goal is unset, not a division-by-zero crash")
    func kcalFractionGuardsMissingGoal() {
        let summary = DashboardAggregation.NutritionSummary(consumed: Nutrients(kcal: 500), goal: Nutrients())
        #expect(summary.kcalFraction == 0)
    }

    @Test("Macro fraction is zero when that macro's goal is zero")
    func macroFractionGuardsZeroGoal() {
        let summary = DashboardAggregation.NutritionSummary(
            consumed: Nutrients(proteinG: 10),
            goal: Nutrients(proteinG: 0)
        )
        #expect(summary.macroFraction(\.proteinG) == 0)
    }

    @Test("Macro fraction divides consumed by that macro's goal")
    func macroFractionDividesConsumedByGoal() {
        let summary = DashboardAggregation.NutritionSummary(
            consumed: Nutrients(proteinG: 75),
            goal: Nutrients(proteinG: 150)
        )
        #expect(summary.macroFraction(\.proteinG) == 0.5)
    }

    @Test("A day with no logged data appears in the weekly series at zero, not missing")
    func weekGlancesFillsGapDays() {
        let keys = ["2026-09-13", "2026-09-14", "2026-09-15"]

        let glances = DashboardAggregation.weekGlances(
            keys: keys,
            nutrientsByDay: ["2026-09-13": [Nutrients(kcal: 1000)]],
            kcalGoal: 2000,
            waterByDay: ["2026-09-15": 1250],
            waterGoalML: 2500,
            workoutDayKeys: ["2026-09-15"]
        )

        #expect(glances.map(\.dayKey) == keys)
        #expect(glances[0].kcalFraction == 0.5)

        // The middle day has nothing logged at all — it must still be
        // present, at zero on every fraction, rather than dropped.
        #expect(glances[1].kcalFraction == 0)
        #expect(glances[1].waterFraction == 0)
        #expect(!glances[1].hasWorkout)

        #expect(glances[2].waterFraction == 0.5)
        #expect(glances[2].hasWorkout)
        #expect(!glances[0].hasWorkout)
    }

    @Test("A cardio-only day counts as trained, same as a strength workout day")
    func cardioOnlyDayCountsAsTrained() {
        // `weekGlances`'s signature is unchanged (Feature 5, Decision 5):
        // `WeeklyStripCard` unions cardio day keys into `workoutDayKeys`
        // itself before calling in, so this just confirms a key present only
        // because of a cardio session still lights up `hasWorkout`.
        let keys = ["2026-09-13", "2026-09-14"]
        let cardioOnlyDayKeys: Set<String> = ["2026-09-14"]

        let glances = DashboardAggregation.weekGlances(
            keys: keys,
            nutrientsByDay: [:],
            kcalGoal: 2000,
            waterByDay: [:],
            waterGoalML: 2500,
            workoutDayKeys: cardioOnlyDayKeys
        )

        #expect(!glances[0].hasWorkout)
        #expect(glances[1].hasWorkout)
    }

    @Test("Weekly series over an entirely empty history is still one glance per key")
    func weekGlancesOverEmptyHistory() {
        let keys = ["2026-09-13", "2026-09-14"]
        let glances = DashboardAggregation.weekGlances(
            keys: keys,
            nutrientsByDay: [:],
            kcalGoal: 2000,
            waterByDay: [:],
            waterGoalML: 2500,
            workoutDayKeys: []
        )
        #expect(glances.count == 2)
        #expect(glances.allSatisfy { $0.kcalFraction == 0 && $0.waterFraction == 0 && !$0.hasWorkout })
    }
}
