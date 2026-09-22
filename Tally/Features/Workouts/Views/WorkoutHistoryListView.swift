import SwiftData
import SwiftUI

/// One row of the merged history list: either a finished strength workout or
/// a logged cardio session, ordered together by date.
private enum HistoryItem: Identifiable, Hashable {
    case workout(Workout)
    case cardio(CardioEntry)

    var id: String {
        switch self {
        case .workout(let workout): "workout-\(workout.id)"
        case .cardio(let entry): "cardio-\(entry.id)"
        }
    }

    var date: Date {
        switch self {
        case .workout(let workout): workout.startedAt
        case .cardio(let entry): entry.performedAt
        }
    }
}

/// The full list of finished workouts and logged cardio sessions, merged by
/// date. `WorkoutsHomeView` only shows the five most recent; this is "See All
/// History".
struct WorkoutHistoryListView: View {
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \CardioEntry.performedAt, order: .reverse) private var cardioEntries: [CardioEntry]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            ForEach(items) { item in
                switch item {
                case .workout(let workout):
                    NavigationLink(value: workout) {
                        WorkoutHistoryRow(workout: workout)
                    }
                case .cardio(let entry):
                    CardioHistoryRow(entry: entry, weightUnit: weightUnit)
                }
            }
        }
        .navigationTitle("History")
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Workouts Yet",
                    systemImage: "clock",
                    description: Text("Finished sessions will show up here.")
                )
            }
        }
    }

    private var weightUnit: WeightUnit { UserSettings.current(in: modelContext).weightUnit }

    private var finished: [Workout] { workouts.filter { $0.finishedAt != nil } }

    private var items: [HistoryItem] {
        (finished.map(HistoryItem.workout) + cardioEntries.map(HistoryItem.cardio))
            .sorted { $0.date > $1.date }
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    _ = WorkoutsPreviewData.seedHistory(in: container.mainContext)
    WorkoutsPreviewData.makeCardioEntry(in: container.mainContext)

    return NavigationStack {
        WorkoutHistoryListView()
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
