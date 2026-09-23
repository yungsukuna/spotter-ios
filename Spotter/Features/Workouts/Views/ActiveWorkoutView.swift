import SwiftData
import SwiftUI
import UIKit

/// The single scrollable logging screen: every exercise in the session and
/// every one of its set rows, inline, with no drill-down. This is the whole
/// point of the RepCount replication — see the note at the top of
/// `CLAUDE.md`'s Workouts section — and every other screen in this feature
/// exists to support this one.
struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    /// Owned by `WorkoutsHomeView`, not this view: navigating back here mid
    /// rest must not destroy the controller, or the pending notification /
    /// Live Activity would be orphaned. See "Must change first" #3 in
    /// `docs/PHASE2-PLAN.md`.
    var restTimer: RestTimerController

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var settings: UserSettings?
    @State private var showingExercisePicker = false
    @State private var showingCardioSheet = false
    @State private var showingDiscardConfirm = false
    @State private var historyExercise: Exercise?
    @State private var statsExercise: Exercise?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(workout.orderedExercises) { entry in
                    ExerciseLogCardView(
                        entry: entry,
                        workout: workout,
                        weightUnit: weightUnit,
                        setEffortDisplay: settings?.setEffortDisplay ?? .off,
                        barbellWeightKG: settings?.barbellWeightKG,
                        bracketPosition: SupersetGrouping.bracketPosition(for: entry, in: workout),
                        canGroupWithNext: hasNextExercise(after: entry),
                        priorCompletedSets: priorCompletedSets(for: entry.exercise),
                        onShowHistory: { historyExercise = entry.exercise },
                        onShowStats: { statsExercise = entry.exercise },
                        onGroupWithNext: { SupersetGrouping.groupWithNext(entry, in: workout) },
                        onUngroup: { SupersetGrouping.ungroup(entry) },
                        onRemove: { workout.removeExercise(entry) },
                        onSetCompleted: handleSetCompleted
                    )
                    .padding(.horizontal, Theme.Layout.cardPadding)
                    .padding(.bottom, gapAfter(entry))
                }

                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, Theme.Layout.cardPadding)

                // A "finisher" logged from inside the session without leaving
                // it — uses the same sheet `WorkoutsHomeView` presents. It
                // does not attach to `workout`; see `CardioEntrySheet`.
                Button {
                    showingCardioSheet = true
                } label: {
                    Label("Log Cardio", systemImage: "figure.run")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.Layout.minimumTapTarget)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, Theme.Layout.cardPadding)
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            // Shown while running *and* while finished — see `RestTimerBar`'s
            // finished style, which is how the app signals expiry when the
            // local notification is suppressed in the foreground.
            if restTimer.state != .idle {
                RestTimerBar(controller: restTimer)
            }
        }
        .background(Theme.Colors.groupedBackground)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive, action: discardTapped)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish", action: finishWorkout)
            }
            // The set fields use number pads, which have no return key.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: dismissKeyboard)
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                let entry = workout.addExercise(exercise)
                NewExerciseSets.populate(entry, excludingWorkout: workout)
            }
        }
        .sheet(isPresented: $showingCardioSheet) {
            CardioEntrySheet()
        }
        .sheet(item: $historyExercise) { exercise in
            ExerciseHistorySheet(exercise: exercise, excludingWorkoutID: workout.id)
        }
        .sheet(item: $statsExercise) { exercise in
            ExerciseStatsView(exercise: exercise)
        }
        .confirmationDialog(
            "Discard this workout? Everything logged will be lost.",
            isPresented: $showingDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard Workout", role: .destructive, action: discardWorkout)
            Button("Keep Logging", role: .cancel) {}
        }
        .task {
            // Settings are read here rather than in `onAppear`, which runs
            // before this task and so could only ever see nil settings.
            let loaded = UserSettings.current(in: modelContext)
            settings = loaded
            UIApplication.shared.isIdleTimerDisabled = loaded.keepScreenAwakeDuringWorkout
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var weightUnit: WeightUnit { settings?.weightUnit ?? .kilograms }

    private func hasNextExercise(after entry: WorkoutExercise) -> Bool {
        let ordered = workout.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == entry.id }) else { return false }
        return index + 1 < ordered.count
    }

    /// Tight spacing between adjacent superset members so the bracket reads
    /// as one continuous run; normal spacing everywhere else.
    private func gapAfter(_ entry: WorkoutExercise) -> CGFloat {
        let ordered = workout.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == entry.id }), index + 1 < ordered.count else {
            return Theme.Spacing.lg
        }
        let next = ordered[index + 1]
        if let group = entry.supersetGroup, group == next.supersetGroup {
            return Theme.Spacing.xxs
        }
        return Theme.Spacing.lg
    }

    /// History for the PR badge: every other completed set of this exercise,
    /// across every *other* workout. Excluding the current session keeps a
    /// set from ever being compared against itself.
    private func priorCompletedSets(for exercise: Exercise?) -> [StrengthMath.CompletedSet] {
        guard let exercise else { return [] }
        return WorkoutStatsCalculator.completedSets(for: exercise).filter { $0.workoutID != workout.id }
    }

    private func handleSetCompleted(_ entry: WorkoutExercise) {
        guard let settings else { return }
        guard let duration = RestDuration.resolve(
            exerciseOverride: entry.exercise?.restTimerSeconds,
            globalDefault: settings.restTimerSeconds,
            autoStart: settings.autoStartRestTimer
        ) else {
            return
        }
        restTimer.start(
            duration: duration,
            notify: settings.restTimerNotifications,
            exerciseName: entry.exercise?.name,
            workoutName: workout.name
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func finishWorkout() {
        // A rest timer outliving its workout would still notify and keep
        // its Live Activity on the Lock Screen.
        restTimer.reset()
        workout.finish()
        try? modelContext.save()
        dismiss()
    }

    private func discardTapped() {
        if workout.hasLoggedAnything {
            showingDiscardConfirm = true
        } else {
            discardWorkout()
        }
    }

    private func discardWorkout() {
        restTimer.reset()
        modelContext.delete(workout)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let container = SpotterSchema.previewContainer()
    let workout = WorkoutsPreviewData.makeInProgressWorkout(in: container.mainContext)

    return NavigationStack {
        ActiveWorkoutView(workout: workout, restTimer: RestTimerController())
    }
    .modelContainer(container)
    .environment(\.appEnvironment, .preview())
}
