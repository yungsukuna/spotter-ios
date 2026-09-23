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
    @Query(sort: \CardioEntry.performedAt, order: .reverse) private var cardioEntries: [CardioEntry]

    @State private var path = NavigationPath()
    @State private var showingCardioSheet = false
    /// Owns the rest timer for the lifetime of the tab, not just the logging
    /// screen — see "Must change first" #3 in `docs/PHASE2-PLAN.md`.
    /// Navigating back to this screen mid-rest must not tear down the
    /// pending notification or Live Activity.
    @State private var restTimer = RestTimerController(
        notifier: SystemRestTimerNotifier(),
        activityPresenter: SystemRestTimerActivityPresenter()
    )

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
                    ActiveWorkoutView(workout: workout, restTimer: restTimer)
                } else {
                    WorkoutDetailView(workout: workout)
                }
            }
            .navigationDestination(for: Routine.self) { routine in
                RoutineEditorView(routine: routine)
            }
            .sheet(isPresented: $showingCardioSheet) {
                CardioEntrySheet()
            }
        }
        .task {
            // Sweep any Live Activity left behind by an app kill mid-rest
            // (`SystemRestTimerActivityPresenter.end()` also does this on
            // every ordinary skip/finish, but that path never runs if the
            // app was terminated instead).
            //
            // `.task` re-runs every time this screen reappears — switching
            // tabs, or popping back from the logging screen mid-rest — so
            // only sweep when no timer is live, or it would cancel the rest
            // the lifter is in the middle of.
            if restTimer.state == .idle {
                restTimer.reset()
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
                Button {
                    showingCardioSheet = true
                } label: {
                    Label("Log Cardio", systemImage: "figure.run")
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
            if recentItems.isEmpty {
                Text("No workouts logged yet.")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            ForEach(recentItems) { item in
                switch item {
                case .workout(let workout):
                    NavigationLink(value: workout) {
                        WorkoutHistoryRow(workout: workout)
                    }
                case .cardio(let entry):
                    CardioHistoryRow(entry: entry, weightUnit: weightUnit)
                }
            }
            NavigationLink("See All History") {
                WorkoutHistoryListView()
            }
        }
    }

    // MARK: - Data

    /// One row of the merged "Recent Workouts" section: a finished strength
    /// workout or a logged cardio session, ordered together by date.
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

    private var activeWorkout: Workout? {
        allWorkouts.first { $0.finishedAt == nil }
    }

    private var finishedWorkouts: [Workout] {
        allWorkouts.filter { $0.finishedAt != nil }
    }

    private var weightUnit: WeightUnit { UserSettings.current(in: modelContext).weightUnit }

    private var recentItems: [HistoryItem] {
        let merged = finishedWorkouts.map(HistoryItem.workout) + cardioEntries.map(HistoryItem.cardio)
        return Array(merged.sorted { $0.date > $1.date }.prefix(5))
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
    let container = SpotterSchema.previewContainer()
    WorkoutsPreviewData.seedHomeScreen(in: container.mainContext)

    return WorkoutsHomeView()
        .modelContainer(container)
        .environment(\.appEnvironment, .preview())
}
