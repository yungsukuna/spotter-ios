import Charts
import SwiftUI

/// Weigh-in scatter plus the smoothed trend line, with an optional dashed
/// goal line. Pure over already-computed points — no querying here, so
/// `BodyWeightView` owns the range and `BodyWeightTrend` owns the maths.
struct BodyWeightChart: View {
    let points: [BodyWeightTrend.TrendPoint]
    let unit: WeightUnit
    let goalWeightKG: Double?
    var calendar: Calendar = .current

    var body: some View {
        Chart {
            ForEach(points) { point in
                PointMark(
                    x: .value("Date", date(for: point.dayKey)),
                    y: .value("Weight", UnitConverter.weight(point.raw, in: unit))
                )
                .foregroundStyle(Theme.Colors.workout.opacity(0.35))
                .symbolSize(30)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Date", date(for: point.dayKey)),
                    y: .value("Trend", UnitConverter.weight(point.trend, in: unit))
                )
                .foregroundStyle(Theme.Colors.workout)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            if let goalWeightKG {
                RuleMark(y: .value("Goal", UnitConverter.weight(goalWeightKG, in: unit)))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .frame(height: 220)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private func date(for dayKey: String) -> Date {
        DayKey.date(from: dayKey, calendar: calendar) ?? Date()
    }
}

#Preview {
    let means = BodyWeightTrend.dailyMeans(BodyPreviewData.sampleWeighIns)
    let points = BodyWeightTrend.trend(means)

    return BodyWeightChart(points: points, unit: .kilograms, goalWeightKG: 78)
        .padding()
}
