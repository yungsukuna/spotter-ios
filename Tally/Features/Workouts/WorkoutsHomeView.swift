import SwiftData
import SwiftUI

/// Root of the Workouts tab: the active-session banner (or a way to start
/// one), the routine list, and recent history.
///
/// A deliberate replication of RepCount — see `CLAUDE.md`'s Workouts section
/// for the priority-ordered list of what makes it RepCount rather than a
/// generic workout logger. The logging screen itself is `ActiveWorkoutView`.
struct WorkoutsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.startedAt, order: .reverse) private var allWorkouts: [Workout]
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                activeSection
                routinesSection
                historySection
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: Workout.self) { workout in
                if workout.isInProgress {
                    ActiveWorkoutView(workout: workout)
                } else {
                    WorkoutDetailView(workout: workout)
                }
            }
            .navigationDestination(for: Routine.self) { routine in
                RoutineEditorView(routine: routine)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var activeSection: some View {
        if let active = activeWorkout {
            Section {
                NavigationLink(value: active) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label("Workout in Progress", systemImage: "bolt.fill")
                            .font(Theme.Typography.sectionHeader)
                            .foregroundStyle(Theme.Colors.workout)
                        Text(active.name)
                            .font(Theme.Typography.cardTitle)
                        Text("\(Format.duration(active.duration)) elapsed · \(active.completedSetCount) sets")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        } else {
            Section {
                Button {
                    startEmptyWorkout()
                } label: {
                    Label("Start Empty Workout", systemImage: "plus.circle.fill")
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
            }
        }
    }

    private var routinesSection: some View {
        Section("Routines") {
            if routines.isEmpty {
                Text("No routines yet.")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            ForEach(routines.prefix(5)) { routine in
                Button {
                    start(from: routine)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(routine.name)
                                .foregroundStyle(Theme.Colors.primaryText)
                            Text(routine.exerciseSummary)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                            .foregroundStyle(Theme.Colors.workout)
                    }
                    .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
                .disabled(activeWorkout != nil)
            }
            NavigationLink("Manage Routines") {
                RoutineListView()
            }
        }
    }

    private var historySection: some View {
        Section("Recent Workouts") {
            if finishedWorkouts.isEmpty {
                Text("No workouts logged yet.")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            ForEach(Array(finishedWorkouts.prefix(5))) { workout in
                NavigationLink(value: workout) {
                    WorkoutHistoryRow(workout: workout)
                }
            }
            NavigationLink("See All History") {
                WorkoutHistoryListView()
            }
        }
    }

    // MARK: - Data

    private var activeWorkout: Workout? {
        allWorkouts.first { $0.finishedAt == nil }
    }

    private var finishedWorkouts: [Workout] {
        allWorkouts.filter { $0.finishedAt != nil }
    }

    // MARK: - Actions

    private func startEmptyWorkout() {
        let workout = Workout()
        modelContext.insert(workout)
        try? modelContext.save()
        path.append(workout)
    }

    private func start(from routine: Routine) {
        let workout = routine.makeWorkout()
        modelContext.insert(workout)
        routine.lastPerformedAt = workout.startedAt
        try? modelContext.save()
        path.append(workout)
    }
}

#Preview {
    let container = TallySchema.previewContainer()
    WorkoutsPreviewData.seedHomeScreen(in: container.mainContext)

    return WorkoutsHomeView()
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
