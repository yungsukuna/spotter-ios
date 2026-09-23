import SwiftData
import SwiftUI

/// Dashboard card: today's water total against goal, as a small version of
/// the Water tab's own progress ring, so the two screens read as one system.
struct WaterSummaryCard: View {
    @Query private var todayEntries: [WaterEntry]

    let goalML: Double
    let unit: VolumeUnit

    init(goalML: Double, unit: VolumeUnit, calendar: Calendar = .current) {
        self.goalML = goalML
        self.unit = unit
        let todayKey = DayKey.today(calendar: calendar)
        _todayEntries = Query(filter: #Predicate<WaterEntry> { $0.dayKey == todayKey })
    }

    private var totalML: Double {
        WaterAggregation.totalML(todayEntries.map(\.record))
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            WaterProgressRing(
                fraction: WaterAggregation.progressFraction(totalML: totalML, goalML: goalML),
                lineWidth: 8
            )
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Label("Water", systemImage: "drop")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.water)
                Text("\(Format.volume(totalML, in: unit)) of \(Format.volume(goalML, in: unit))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spotterCard()
    }
}

#Preview {
    WaterSummaryCard(goalML: 2500, unit: .millilitres)
        .padding()
        .modelContainer(SpotterSchema.previewContainer())
}
