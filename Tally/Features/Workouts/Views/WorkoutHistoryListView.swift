import SwiftData
import SwiftUI

/// The full list of finished workouts. `WorkoutsHomeView` only shows the
/// five most recent; this is "See All History".
struct WorkoutHistoryListView: View {
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]

    var body: some View {
        List {
            ForEach(finished) { workout in
                NavigationLink(value: workout) {
                    WorkoutHistoryRow(workout: workout)
                }
            }
        }
        .navigationTitle("History")
        .overlay {
            if finished.isEmpty {
                ContentUnavailableView(
                    "No Workouts Yet",
                    systemImage: "clock",
                    description: Text("Finished sessions will show up here.")
                )
            }
        }
    }

    private var finished: [Workout] { workouts.filter { $0.finishedAt != nil } }
}

#Preview {
    let container = TallySchema.previewContainer()
    _ = WorkoutsPreviewData.seedHistory(in: container.mainContext)

    return NavigationStack {
        WorkoutHistoryListView()
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
