import SwiftData
import SwiftUI

/// Root of the Today tab — a read-mostly dashboard summarising nutrition,
/// water and workouts, plus a 7-day strip.
///
/// Self-contained by design: it reads `DiaryEntry`, `WaterEntry` and
/// `Workout` directly rather than importing the Nutrition or Workouts tabs'
/// own view types, which belong to other workstreams. Every card degrades to
/// a plain empty-state message when its section has no data for the day.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings {
        settingsList.first ?? UserSettings.current(in: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    NutritionSummaryCard(goal: settings.nutritionGoal)
                    WaterSummaryCard(goalML: settings.dailyWaterGoalML, unit: settings.volumeUnit)
                    StreakSummaryCard(waterGoalML: settings.dailyWaterGoalML)
                    WorkoutSummaryCard(weightUnit: settings.weightUnit)
                    BodyWeightCard(weightUnit: settings.weightUnit, goalWeightKG: settings.goalWeightKG)
                    WeeklyStripCard(kcalGoal: settings.dailyKcalGoal, waterGoalML: settings.dailyWaterGoalML)
                    WeeklySummaryCard(
                        kcalGoal: settings.dailyKcalGoal,
                        proteinGoalG: settings.dailyProteinGoalG,
                        waterGoalML: settings.dailyWaterGoalML,
                        weightUnit: settings.weightUnit
                    )
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.groupedBackground)
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(SpotterSchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
