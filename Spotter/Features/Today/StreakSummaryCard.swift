import SwiftData
import SwiftUI

/// Dashboard card: the logging streak, this week's water-goal hit rate, and
/// how many days were trained this week.
///
/// "Logging streak" counts consecutive days with at least one `DiaryEntry`
/// (Decision 6 in `docs/PHASE2-PLAN.md`). "Trained" counts a day with either
/// a finished `Workout` or any `CardioEntry` (Decision 5) — a cardio-only day
/// still lights this up, matching `WeeklyStripCard`'s workout marker.
///
/// Fetches every entry of each model unfiltered and groups by day key in
/// Swift, the same trade-off `WeeklyStripCard` makes.
struct StreakSummaryCard: View {
    @Query private var diaryEntries: [DiaryEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var workouts: [Workout]
    @Query private var cardioEntries: [CardioEntry]

    let waterGoalML: Double

    private let calendar: Calendar

    init(waterGoalML: Double, calendar: Calendar = .current) {
        self.waterGoalML = waterGoalML
        self.calendar = calendar
    }

    private var diaryDayKeys: Set<String> {
        Set(diaryEntries.map(\.dayKey))
    }

    private var streak: StreakCalculator.StreakResult {
        StreakCalculator.currentStreak(days: diaryDayKeys, calendar: calendar)
    }

    private var weekKeys: [String] {
        WeeklySummary.weekKeys(calendar: calendar)
    }

    private var summary: WeeklySummary.Result {
        let keySet = Set(weekKeys)
        let relevantWater = waterEntries.filter { keySet.contains($0.dayKey) }
        let relevantWorkouts = workouts.filter { !$0.isInProgress && keySet.contains($0.dayKey) }
        let relevantCardio = cardioEntries.filter { keySet.contains($0.dayKey) }

        let waterByDay = Dictionary(grouping: relevantWater, by: \.dayKey)
            .mapValues { WaterAggregation.totalML($0.map(\.record)) }
        let workoutDayKeys = Set(relevantWorkouts.map(\.dayKey))
        let workoutVolumeByDay = Dictionary(grouping: relevantWorkouts, by: \.dayKey)
            .mapValues { entries in entries.reduce(0) { $0 + $1.totalVolumeKG } }
        let cardioSecondsByDay = Dictionary(grouping: relevantCardio, by: \.dayKey)
            .mapValues { entries in entries.reduce(0) { $0 + $1.durationSeconds } }

        return WeeklySummary.make(
            weekKeys: weekKeys,
            diaryByDay: [:],
            waterByDay: waterByDay,
            goals: WeeklySummary.Goals(kcal: 0, proteinG: 0, waterML: waterGoalML),
            workoutDayKeys: workoutDayKeys,
            workoutVolumeByDay: workoutVolumeByDay,
            cardioSecondsByDay: cardioSecondsByDay,
            trendWeightChangeKG: nil
        )
    }

    private var streakText: String {
        if streak.todayPending {
            return streak.length > 0
                ? "Log today to keep your \(streak.length)-day streak"
                : "Log today to start a streak"
        }
        return "\(streak.length)-day logging streak"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(streakText, systemImage: "flame.fill")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.warning)

            Text("Water goal hit \(summary.waterGoalHitDays)/\(summary.totalDays) days")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text("Workouts this week: \(summary.trainedDays)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spotterCard()
    }
}

#Preview {
    StreakSummaryCard(waterGoalML: 2500)
        .padding()
        .modelContainer(SpotterSchema.previewContainer())
}
