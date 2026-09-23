import SwiftData
import SwiftUI

/// Full body-weight history: a range-limited trend chart plus the list of
/// individual weigh-ins, with tap-to-edit and swipe-to-delete.
///
/// Fetches every `BodyMeasurement` unfiltered and filters to `.bodyWeight` in
/// Swift, matching the trade-off `WeeklyStripCard` and `WaterHistoryChart`
/// already make at this app's data scale.
struct BodyWeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurement.recordedAt, order: .reverse) private var allMeasurements: [BodyMeasurement]

    let weightUnit: WeightUnit
    let goalWeightKG: Double?

    @State private var range: WorkoutStatsCalculator.DateRange = .threeMonths
    @State private var showingAddSheet = false
    @State private var editingMeasurement: BodyMeasurement?

    private let calendar = Calendar.current

    private var bodyWeightMeasurements: [BodyMeasurement] {
        allMeasurements.filter { $0.type == .bodyWeight }
    }

    private var rangedMeasurements: [BodyMeasurement] {
        guard let cutoff = range.cutoff(from: Date(), calendar: calendar) else { return bodyWeightMeasurements }
        return bodyWeightMeasurements.filter { $0.recordedAt >= cutoff }
    }

    private var trendPoints: [BodyWeightTrend.TrendPoint] {
        let weighIns = rangedMeasurements.map { BodyWeightTrend.WeighIn(dayKey: $0.dayKey, kg: $0.value) }
        return BodyWeightTrend.trend(BodyWeightTrend.dailyMeans(weighIns), calendar: calendar)
    }

    private var lastValueInUnit: Double? {
        guard let latest = bodyWeightMeasurements.first?.value else { return nil }
        return UnitConverter.weight(latest, in: weightUnit)
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(WorkoutStatsCalculator.DateRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if trendPoints.isEmpty {
                    Text("No weigh-ins in this range.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                } else {
                    BodyWeightChart(points: trendPoints, unit: weightUnit, goalWeightKG: goalWeightKG, calendar: calendar)
                }
            }
            .listRowSeparator(.hidden)

            Section("Weigh-Ins") {
                if bodyWeightMeasurements.isEmpty {
                    Text("No weigh-ins yet. Tap + to log your weight.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                } else {
                    ForEach(bodyWeightMeasurements) { measurement in
                        Button {
                            editingMeasurement = measurement
                        } label: {
                            weighInRow(measurement)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteMeasurements)
                }
            }
        }
        .navigationTitle("Body Weight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            WeighInSheet(unit: weightUnit, lastValueInUnit: lastValueInUnit)
        }
        .sheet(item: $editingMeasurement) { measurement in
            WeighInSheet(existing: measurement, unit: weightUnit)
        }
    }

    private func weighInRow(_ measurement: BodyMeasurement) -> some View {
        HStack {
            Text(measurement.recordedAt, format: .dateTime.month(.abbreviated).day().year())
                .foregroundStyle(Theme.Colors.primaryText)
            Spacer()
            Text(Format.weight(measurement.value, in: weightUnit))
                .font(Theme.Typography.setValue)
                .foregroundStyle(Theme.Colors.primaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
        .contentShape(Rectangle())
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(bodyWeightMeasurements[index])
        }
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    BodyPreviewData.seedWeighIns(in: container.mainContext)

    return NavigationStack {
        BodyWeightView(weightUnit: .kilograms, goalWeightKG: 78)
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
