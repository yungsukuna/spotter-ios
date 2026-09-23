import Charts
import SwiftData
import SwiftUI

/// Per-exercise progress: estimated 1RM, volume and heaviest weight over
/// time, plus the rep-record table. Reachable as a sheet from the logging
/// screen, same as history.
struct ExerciseStatsView: View {
    var exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var range: WorkoutStatsCalculator.DateRange = .threeMonths

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(WorkoutStatsCalculator.DateRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowSeparator(.hidden)

                Section("Estimated 1RM") {
                    seriesChart(oneRepMaxSeries)
                }
                Section("Volume") {
                    seriesChart(volumeSeries)
                }
                Section("Heaviest Weight") {
                    seriesChart(heaviestWeightSeries)
                }
                Section("Rep Records") {
                    if repRecords.isEmpty {
                        Text("No completed sets yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    } else {
                        ForEach(repRecords) { record in
                            HStack {
                                Text("\(record.reps) rep\(record.reps == 1 ? "" : "s")")
                                Spacer()
                                Text(Format.weight(record.weightKG, in: weightUnit))
                                    .font(Theme.Typography.setValue)
                            }
                        }
                    }
                }
            }
            .navigationTitle(exercise.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var settings: UserSettings { UserSettings.current(in: modelContext) }
    private var weightUnit: WeightUnit { settings.weightUnit }

    private var oneRepMaxSeries: [WorkoutStatsCalculator.DataPoint] {
        WorkoutStatsCalculator.oneRepMaxSeries(for: exercise, formula: settings.oneRepMaxFormula, range: range)
    }
    private var volumeSeries: [WorkoutStatsCalculator.DataPoint] {
        WorkoutStatsCalculator.volumeSeries(for: exercise, range: range)
    }
    private var heaviestWeightSeries: [WorkoutStatsCalculator.DataPoint] {
        WorkoutStatsCalculator.heaviestWeightSeries(for: exercise, range: range)
    }
    private var repRecords: [StrengthMath.RepRecord] {
        WorkoutStatsCalculator.repRecords(for: exercise)
    }

    @ViewBuilder
    private func seriesChart(_ points: [WorkoutStatsCalculator.DataPoint]) -> some View {
        if points.isEmpty {
            Text("Not enough data yet.")
                .foregroundStyle(Theme.Colors.secondaryText)
        } else {
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
            }
            .foregroundStyle(Theme.Colors.workout)
            .frame(height: 180)
        }
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let exercise = WorkoutsPreviewData.seedHistory(in: container.mainContext)

    return ExerciseStatsView(exercise: exercise)
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
