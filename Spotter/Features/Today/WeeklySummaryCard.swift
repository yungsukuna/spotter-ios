import SwiftData
import SwiftUI

/// Dashboard card: the calendar week so far — days logged, average kcal
/// against goal, protein-goal hit days, workouts and volume, cardio minutes,
/// and the change in trend body weight.
///
/// Fetches every entry of each model unfiltered and groups by day key in
/// Swift, the same trade-off `WeeklyStripCard` makes.
struct WeeklySummaryCard: View {
    @Query private var diaryEntries: [DiaryEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var workouts: [Workout]
    @Query private var cardioEntries: [CardioEntry]
    @Query private var bodyMeasurements: [BodyMeasurement]

    let kcalGoal: Double
    let proteinGoalG: Double
    let waterGoalML: Double
    let weightUnit: WeightUnit

    private let calendar: Calendar

    init(
        kcalGoal: Double,
        proteinGoalG: Double,
        waterGoalML: Double,
        weightUnit: WeightUnit,
        calendar: Calendar = .current
    ) {
        self.kcalGoal = kcalGoal
        self.proteinGoalG = proteinGoalG
        self.waterGoalML = waterGoalML
        self.weightUnit = weightUnit
        self.calendar = calendar
    }

    private var weekKeys: [String] {
        WeeklySummary.weekKeys(calendar: calendar)
    }

    /// This week's change in trend body weight, from `BodyWeightTrend`. Built
    /// from every `bodyWeight` measurement on record, not just this week's —
    /// the trend needs history before the week started to be meaningful.
    private var trendWeightChangeKG: Double? {
        let bodyWeightRaw = MeasurementType.bodyWeight.rawValue
        let weighIns = bodyMeasurements
            .filter { $0.typeRaw == bodyWeightRaw }
            .map { BodyWeightTrend.WeighIn(dayKey: $0.dayKey, kg: $0.value) }
        let points = BodyWeightTrend.trend(BodyWeightTrend.dailyMeans(weighIns), calendar: calendar)
        return BodyWeightTrend.weeklyRate(points, calendar: calendar)
    }

    private var summary: WeeklySummary.Result {
        let keySet = Set(weekKeys)
        let relevantDiary = diaryEntries.filter { keySet.contains($0.dayKey) }
        let relevantWater = waterEntries.filter { keySet.contains($0.dayKey) }
        let relevantWorkouts = workouts.filter { !$0.isInProgress && keySet.contains($0.dayKey) }
        let relevantCardio = cardioEntries.filter { keySet.contains($0.dayKey) }

        let diaryByDay = Dictionary(grouping: relevantDiary, by: \.dayKey)
            .mapValues { entries in entries.map(\.nutrients) }
        let waterByDay = Dictionary(grouping: relevantWater, by: \.dayKey)
            .mapValues { WaterAggregation.totalML($0.map(\.record)) }
        let workoutDayKeys = Set(relevantWorkouts.map(\.dayKey))
        let workoutVolumeByDay = Dictionary(grouping: relevantWorkouts, by: \.dayKey)
            .mapValues { entries in entries.reduce(0) { $0 + $1.totalVolumeKG } }
        let cardioSecondsByDay = Dictionary(grouping: relevantCardio, by: \.dayKey)
            .mapValues { entries in entries.reduce(0) { $0 + $1.durationSeconds } }

        return WeeklySummary.make(
            weekKeys: weekKeys,
            diaryByDay: diaryByDay,
            waterByDay: waterByDay,
            goals: WeeklySummary.Goals(kcal: kcalGoal, proteinG: proteinGoalG, waterML: waterGoalML),
            workoutDayKeys: workoutDayKeys,
            workoutVolumeByDay: workoutVolumeByDay,
            cardioSecondsByDay: cardioSecondsByDay,
            trendWeightChangeKG: trendWeightChangeKG
        )
    }

    /// "+0.4 kg this week" / "-1.1 lb this week", or nil with too little
    /// weigh-in history to compare.
    private var trendWeightText: String? {
        guard let change = summary.trendWeightChangeKG else { return nil }
        let convertedMagnitude = UnitConverter.weight(abs(change), in: weightUnit)
        let number = String(format: "%.1f", convertedMagnitude)
            .replacingOccurrences(of: ".0", with: "")
        let sign = change >= 0 ? "+" : "-"
        return "Trend weight \(sign)\(number) \(weightUnit.abbreviation) this week"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("This Week So Far")
                .font(Theme.Typography.sectionHeader)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Days logged \(summary.daysLogged)/\(summary.totalDays)")

                if let averageKcal = summary.averageKcal {
                    Text("Avg \(Format.energy(averageKcal)) vs \(Format.energy(kcalGoal)) goal")
                }

                Text("Protein goal hit \(summary.proteinGoalHitDays)/\(summary.totalDays) days")

                Text("Workouts \(summary.workoutDays) · \(Format.weight(summary.totalVolumeKG, in: weightUnit))")

                if summary.cardioMinutes > 0 {
                    Text("Cardio \(Int(summary.cardioMinutes.rounded())) min")
                }

                if let trendWeightText {
                    Text(trendWeightText)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spotterCard()
    }
}

#Preview {
    WeeklySummaryCard(kcalGoal: 2000, proteinGoalG: 150, waterGoalML: 2500, weightUnit: .kilograms)
        .padding()
        .modelContainer(SpotterSchema.previewContainer())
}
