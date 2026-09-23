import Charts
import SwiftData
import SwiftUI

/// Dashboard card: the smoothed trend weight, the 7-day rate of change and a
/// mini sparkline. Tapping the card pushes `BodyWeightView`; the "+" button
/// opens `WeighInSheet` directly, without navigating first.
///
/// Fetches every `BodyMeasurement` unfiltered and filters to `.bodyWeight` in
/// Swift, matching the trade-off other Today cards make at this app's scale.
struct BodyWeightCard: View {
    @Query(sort: \BodyMeasurement.recordedAt, order: .reverse) private var allMeasurements: [BodyMeasurement]

    let weightUnit: WeightUnit
    let goalWeightKG: Double?

    @State private var showingWeighInSheet = false

    private var bodyWeightMeasurements: [BodyMeasurement] {
        allMeasurements.filter { $0.type == .bodyWeight }
    }

    private var trendPoints: [BodyWeightTrend.TrendPoint] {
        let weighIns = bodyWeightMeasurements.map { BodyWeightTrend.WeighIn(dayKey: $0.dayKey, kg: $0.value) }
        return BodyWeightTrend.trend(BodyWeightTrend.dailyMeans(weighIns))
    }

    private var latestTrendKG: Double? { trendPoints.last?.trend }
    private var weeklyRateKG: Double? { BodyWeightTrend.weeklyRate(trendPoints) }

    private var lastValueInUnit: Double? {
        guard let latest = bodyWeightMeasurements.first?.value else { return nil }
        return UnitConverter.weight(latest, in: weightUnit)
    }

    var body: some View {
        NavigationLink {
            BodyWeightView(weightUnit: weightUnit, goalWeightKG: goalWeightKG)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                showingWeighInSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.workout)
            }
            .frame(width: Theme.Layout.minimumTapTarget, height: Theme.Layout.minimumTapTarget)
        }
        .sheet(isPresented: $showingWeighInSheet) {
            WeighInSheet(unit: weightUnit, lastValueInUnit: lastValueInUnit)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Body Weight", systemImage: "scalemass")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.workout)

            if let latestTrendKG {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(Format.weight(latestTrendKG, in: weightUnit))
                        .font(Theme.Typography.metricSmall)
                    if let weeklyRateKG {
                        Text(rateLabel(weeklyRateKG))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Spacer()
                }
                sparkline
            } else {
                Text("No weigh-ins yet. Tap + to log your weight.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .spotterCard()
    }

    @ViewBuilder
    private var sparkline: some View {
        if trendPoints.count > 1 {
            Chart(trendPoints) { point in
                LineMark(
                    x: .value("Date", DayKey.date(from: point.dayKey) ?? Date()),
                    y: .value("Trend", UnitConverter.weight(point.trend, in: weightUnit))
                )
                .interpolationMethod(.catmullRom)
            }
            .foregroundStyle(Theme.Colors.workout)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 32)
        }
    }

    private func rateLabel(_ rateKG: Double) -> String {
        let magnitude = Format.weight(abs(rateKG), in: weightUnit)
        return (rateKG < 0 ? "-\(magnitude)" : "+\(magnitude)") + " / wk"
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    BodyPreviewData.seedWeighIns(in: container.mainContext)

    return NavigationStack {
        BodyWeightCard(weightUnit: .kilograms, goalWeightKG: 78)
            .padding()
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
