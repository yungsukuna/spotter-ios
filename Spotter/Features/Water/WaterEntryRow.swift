import SwiftData
import SwiftUI

/// One row in today's (or a past day's) list of logged drinks.
struct WaterEntryRow: View {
    let entry: WaterEntry
    let unit: VolumeUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(Format.volume(entry.volumeML, in: unit))
                    .font(Theme.Typography.metricSmall)
                if let presetLabel = entry.presetLabel {
                    Text(presetLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Spacer()
            Text(entry.loggedAt, style: .time)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(minHeight: Theme.Layout.minimumTapTarget)
    }
}

#Preview {
    List {
        WaterEntryRow(entry: WaterEntry(volumeML: 250, presetLabel: "Glass"), unit: .millilitres)
        WaterEntryRow(entry: WaterEntry(volumeML: 473.18), unit: .fluidOunces)
    }
    .modelContainer(SpotterSchema.previewContainer())
}
