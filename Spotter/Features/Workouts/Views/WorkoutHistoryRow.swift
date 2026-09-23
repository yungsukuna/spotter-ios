import Foundation
import SwiftData
import SwiftUI

/// Compact summary row for a finished workout, used on the home screen and
/// the full history list.
struct WorkoutHistoryRow: View {
    var workout: Workout

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(workout.name)
                .font(Theme.Typography.cardTitle)
            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var subtitle: String {
        let dateText = workout.startedAt.formatted(date: .abbreviated, time: .omitted)
        let weightUnit = UserSettings.current(in: modelContext).weightUnit
        let volumeText = Format.weight(workout.totalVolumeKG, in: weightUnit)
        return "\(dateText) · \(volumeText) · \(workout.completedSetCount) sets"
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let workout = WorkoutsPreviewData.makeFinishedWorkout(in: container.mainContext)

    return List {
        WorkoutHistoryRow(workout: workout)
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
