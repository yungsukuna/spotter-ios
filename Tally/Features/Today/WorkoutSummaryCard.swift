import SwiftData
import SwiftUI

/// Dashboard card: an active session if one is in progress, otherwise the
/// most recent session's summary, otherwise a prompt to start one.
///
/// Reads `Workout` directly rather than any Workouts-tab view type, which
/// belongs to a different workstream.
struct WorkoutSummaryCard: View {
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]

    let weightUnit: WeightUnit

    private var activeWorkout: Workout? {
        workouts.first { $0.isInProgress }
    }

    private var mostRecentFinished: Workout? {
        workouts.first { !$0.isInProgress }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Workout", systemImage: "dumbbell")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.workout)

            if let activeWorkout {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(Theme.Colors.success)
                        .frame(width: 8, height: 8)
                    Text("\(activeWorkout.name) in progress")
                    Spacer()
                    Text(Format.duration(activeWorkout.duration))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            } else if let mostRecentFinished {
                HStack {
                    Text(mostRecentFinished.name)
                    Spacer()
                    Text("\(mostRecentFinished.completedSetCount) sets · \(Format.weight(mostRecentFinished.totalVolumeKG, in: weightUnit))")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Text(mostRecentFinished.startedAt, style: .relative)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else {
                Text("No workouts yet. Start one from the Workouts tab.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .tallyCard()
    }
}

#Preview {
    WorkoutSummaryCard(weightUnit: .kilograms)
        .padding()
        .modelContainer(TallySchema.previewContainer())
}
