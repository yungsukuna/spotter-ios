import Charts
import SwiftData
import SwiftUI

/// A 7-day bar chart of daily totals against the goal, so a slump is visible
/// at a glance instead of buried in a list of numbers.
///
/// Fetches every `WaterEntry` unfiltered — this app's data volume is small
/// enough that grouping by day key in Swift, rather than constraining the
/// fetch itself, keeps the query trivially correct at the cost of no
/// measurable performance.
struct WaterHistoryChart: View {
    @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allEntries: [WaterEntry]

    let goalML: Double
    let unit: VolumeUnit

    private let calendar = Calendar.current

    private var days: [WaterAggregation.DayTotal] {
        let keys = DayKey.keys(endingOn: Date(), count: 7, calendar: calendar)
        return WaterAggregation.dailyTotals(records: allEntries.map(\.record), keys: keys, goalML: goalML)
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", weekdayLabel(for: day.dayKey)),
                    y: .value("Volume", UnitConverter.volume(day.totalML, in: unit))
                )
                .foregroundStyle(Theme.Colors.water.gradient)
                .cornerRadius(Theme.Radius.sm)
            }
            RuleMark(y: .value("Goal", UnitConverter.volume(goalML, in: unit)))
                .foregroundStyle(Theme.Colors.water.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 160)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private func weekdayLabel(for dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey, calendar: calendar) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

#Preview {
    WaterHistoryChart(goalML: 2500, unit: .millilitres)
        .padding()
        .modelContainer(SpotterSchema.previewContainer())
}
