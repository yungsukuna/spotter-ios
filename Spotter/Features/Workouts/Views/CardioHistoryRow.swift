import SwiftUI

/// Compact summary row for a logged cardio session, used wherever workout
/// history is listed — `WorkoutHistoryListView` and the home screen's
/// "Recent Workouts" — merged in by date alongside `WorkoutHistoryRow`.
struct CardioHistoryRow: View {
    var entry: CardioEntry
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "figure.run")
                    .foregroundStyle(Theme.Colors.workout)
                Text(entry.exerciseName)
                    .font(Theme.Typography.cardTitle)
            }
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var subtitle: String {
        var parts = [entry.performedAt.formatted(date: .abbreviated, time: .omitted), Format.duration(entry.durationSeconds)]

        if let distanceKM = entry.distanceKM, distanceKM > 0 {
            parts.append(distanceText(distanceKM))
        }
        if let calories = entry.calories {
            parts.append(Format.energy(calories))
        }
        return parts.joined(separator: " · ")
    }

    private func distanceText(_ km: Double) -> String {
        if weightUnit == .pounds {
            return String(format: "%.1f mi", UnitConverter.kilometresToMiles(km))
        }
        return String(format: "%.1f km", km)
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let entry = WorkoutsPreviewData.makeCardioEntry(in: container.mainContext)

    return List {
        CardioHistoryRow(entry: entry, weightUnit: .kilograms)
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
