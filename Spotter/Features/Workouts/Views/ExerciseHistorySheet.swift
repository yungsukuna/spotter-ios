import Foundation
import SwiftData
import SwiftUI

/// Past sessions of one exercise, reachable as a sheet from inside the
/// logging screen — not a separate destination, so checking your history
/// never means leaving the workout you are in the middle of logging.
struct ExerciseHistorySheet: View {
    var exercise: Exercise
    /// The session currently being logged, if any — left out of its own
    /// history.
    var excludingWorkoutID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished sessions of \(exercise.name) will show up here.")
                    )
                } else {
                    ForEach(sessions) { session in
                        Section(session.date.formatted(date: .abbreviated, time: .omitted)) {
                            if let notes = session.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            ForEach(session.sets, id: \.self) { set in
                                HStack {
                                    Text(Format.weight(set.weightKG, in: weightUnit))
                                    Text("×")
                                        .foregroundStyle(Theme.Colors.tertiaryText)
                                    Text("\(set.reps)")
                                    Spacer()
                                }
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

    private var weightUnit: WeightUnit { UserSettings.current(in: modelContext).weightUnit }

    private var sessions: [ExerciseHistoryLookup.PastSession] {
        ExerciseHistoryLookup.pastSessions(for: exercise, excludingWorkoutID: excludingWorkoutID)
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let exercise = WorkoutsPreviewData.seedHistory(in: container.mainContext)

    return ExerciseHistorySheet(exercise: exercise)
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
