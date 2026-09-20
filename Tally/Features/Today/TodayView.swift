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
                    WorkoutSummaryCard(weightUnit: settings.weightUnit)
                    WeeklyStripCard(kcalGoal: settings.dailyKcalGoal, waterGoalML: settings.dailyWaterGoalML)
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
        .modelContainer(TallySchema.previewContainer())
        .environment(\.appEnvironment, .preview())
}
