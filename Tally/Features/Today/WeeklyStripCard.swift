import SwiftData
import SwiftUI

/// Dashboard card: the last 7 days at a glance — a small ring per day for
/// calorie-goal progress, tinted with a workout marker when one happened.
///
/// Fetches every entry of each model unfiltered and groups by day key in
/// Swift; see the note on `WaterHistoryChart` for why that trade-off is fine
/// at this app's scale.
struct WeeklyStripCard: View {
    @Query private var diaryEntries: [DiaryEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var workouts: [Workout]

    let kcalGoal: Double
    let waterGoalML: Double

    private let calendar = Calendar.current

    private var dayKeys: [String] {
        DayKey.keys(endingOn: Date(), count: 7, calendar: calendar)
    }

    private var glances: [DashboardAggregation.DayGlance] {
        let keySet = Set(dayKeys)
        let relevantDiary = diaryEntries.filter { keySet.contains($0.dayKey) }
        let relevantWater = waterEntries.filter { keySet.contains($0.dayKey) }
        let relevantWorkouts = workouts.filter { keySet.contains($0.dayKey) }

        let nutrientsByDay = Dictionary(grouping: relevantDiary, by: \.dayKey)
            .mapValues { $0.map(\.nutrients) }
        let waterByDay = Dictionary(grouping: relevantWater, by: \.dayKey)
            .mapValues { WaterAggregation.totalML($0.map(\.record)) }
        let workoutDayKeys = Set(relevantWorkouts.map(\.dayKey))

        return DashboardAggregation.weekGlances(
            keys: dayKeys,
            nutrientsByDay: nutrientsByDay,
            kcalGoal: kcalGoal,
            waterByDay: waterByDay,
            waterGoalML: waterGoalML,
            workoutDayKeys: workoutDayKeys
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("This Week")
                .font(Theme.Typography.sectionHeader)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(glances) { glance in
                    DayGlanceColumn(glance: glance, calendar: calendar)
                }
            }
        }
        .tallyCard()
    }
}

/// One day's column in the weekly strip: a small ring plus a workout marker.
private struct DayGlanceColumn: View {
    let glance: DashboardAggregation.DayGlance
    let calendar: Calendar

    private var weekdayLabel: String {
        guard let date = DayKey.date(from: glance.dayKey, calendar: calendar) else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.nutrition.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(glance.kcalFraction, 0), 1))
                    .stroke(Theme.Colors.nutrition, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if glance.hasWorkout {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.workout)
                }
            }
            .frame(width: 28, height: 28)
            Text(weekdayLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    WeeklyStripCard(kcalGoal: 2000, waterGoalML: 2500)
        .padding()
        .modelContainer(TallySchema.previewContainer())
}
