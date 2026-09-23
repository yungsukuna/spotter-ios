import Foundation
import SwiftData

// MARK: - Ordering
//
// SwiftData relationship arrays are UNORDERED. Every to-many relationship in
// the workout graph therefore carries an explicit `order: Int` on the child,
// and each parent exposes an `ordered...` computed property that sorts by it.
//
// Always read through the `ordered...` accessor and always renumber through
// the provided mutators. Reading the raw relationship array and trusting its
// sequence is the single easiest way to produce a workout whose exercises
// silently shuffle between launches.

/// A training session: one visit to the gym.
@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = "Workout"
    var startedAt: Date = Date()
    /// Nil while the session is in progress. Exactly one workout may be
    /// unfinished at a time — see `WorkoutStore.activeWorkout`.
    var finishedAt: Date?
    var notes: String?
    /// `yyyy-MM-dd`, see the note on `DiaryEntry.dayKey`.
    var dayKey: String = ""

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise] = []

    /// The routine this session was started from, if any. Nullify on delete:
    /// deleting a routine must not delete the sessions performed from it.
    var sourceRoutine: Routine?

    init(
        id: UUID = UUID(),
        name: String = "Workout",
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        notes: String? = nil,
        sourceRoutine: Routine? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.notes = notes
        self.dayKey = DayKey.make(from: startedAt, calendar: calendar)
        self.sourceRoutine = sourceRoutine
    }

    /// Exercises in display order. Always read through this.
    var orderedExercises: [WorkoutExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var isInProgress: Bool { finishedAt == nil }

    /// Wall-clock length of the session.
    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    /// Total tonnage: the sum of weight × reps over every completed set.
    /// Warm-up sets are excluded — they are not working volume.
    var totalVolumeKG: Double {
        exercises.reduce(0) { $0 + $1.totalVolumeKG }
    }

    /// Count of completed working sets.
    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.completedSets.count }
    }

    /// True once at least one set has been logged. Used to decide whether
    /// discarding the session needs a confirmation prompt.
    var hasLoggedAnything: Bool {
        exercises.contains { !$0.completedSets.isEmpty }
    }

    /// Append an exercise at the end, assigning the next order index.
    @discardableResult
    func addExercise(_ exercise: Exercise) -> WorkoutExercise {
        let entry = WorkoutExercise(
            exercise: exercise,
            order: (exercises.map(\.order).max() ?? -1) + 1
        )
        entry.workout = self
        exercises.append(entry)
        return entry
    }

    /// Reassign `order` to match the given sequence, e.g. after a drag to
    /// reorder. Pass the full list in its new order.
    func reorderExercises(to newOrder: [WorkoutExercise]) {
        for (index, entry) in newOrder.enumerated() {
            entry.order = index
        }
    }

    /// Remove an exercise and close the gap in the ordering.
    func removeExercise(_ entry: WorkoutExercise) {
        exercises.removeAll { $0.id == entry.id }
        reorderExercises(to: orderedExercises)
    }

    func finish(at date: Date = Date()) {
        finishedAt = date
    }
}

/// One exercise as performed within one workout, holding its sets.
@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    /// Position within the workout. See the ordering note at the top of this file.
    var order: Int = 0
    var notes: String?

    /// Exercises sharing a superset group are performed alternately.
    ///
    /// Nil means "not in a superset". Group identity is scoped to the workout,
    /// and groups must be made up of adjacent exercises — the UI enforces this
    /// so the bracket can be drawn as one continuous run.
    var supersetGroup: Int?

    /// Nil only if the underlying exercise was deleted. The name snapshot on
    /// each set is what keeps history readable in that case.
    var exercise: Exercise?
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workoutExercise)
    var sets: [SetEntry] = []

    init(
        id: UUID = UUID(),
        exercise: Exercise?,
        order: Int,
        notes: String? = nil,
        supersetGroup: Int? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.notes = notes
        self.supersetGroup = supersetGroup
    }

    /// Sets in display order. Always read through this.
    var orderedSets: [SetEntry] {
        sets.sorted { $0.order < $1.order }
    }

    /// Completed working sets — excludes warm-ups and anything not ticked off.
    var completedSets: [SetEntry] {
        orderedSets.filter { $0.isCompleted && !$0.isWarmup }
    }

    var displayName: String { exercise?.name ?? "Deleted exercise" }

    var isInSuperset: Bool { supersetGroup != nil }

    /// Tonnage for this exercise within this session.
    var totalVolumeKG: Double {
        completedSets.reduce(0) { $0 + $1.volumeKG }
    }

    /// Heaviest completed working set.
    var topSetWeightKG: Double? {
        completedSets.map(\.weightKG).max()
    }

    /// Best estimated one-rep max across the completed sets.
    func bestEstimatedOneRepMax(formula: OneRepMaxFormula = .epley) -> Double? {
        completedSets.compactMap { $0.estimatedOneRepMax(formula: formula) }.max()
    }

    /// Append a set at the end, assigning the next order index.
    @discardableResult
    func addSet(weightKG: Double = 0, reps: Int = 0, isWarmup: Bool = false) -> SetEntry {
        let entry = SetEntry(
            order: (sets.map(\.order).max() ?? -1) + 1,
            weightKG: weightKG,
            reps: reps,
            isWarmup: isWarmup
        )
        entry.workoutExercise = self
        sets.append(entry)
        return entry
    }

    func removeSet(_ entry: SetEntry) {
        sets.removeAll { $0.id == entry.id }
        for (index, set) in orderedSets.enumerated() {
            set.order = index
        }
    }
}

/// A single set: a weight, a rep count, and whether it actually happened.
///
/// A set exists in the UI before it is performed — that is how the "tap to
/// confirm last session's numbers" flow works. ``isCompleted`` is what
/// separates a planned row from a logged one, and uncompleted sets are excluded
/// from every statistic.
@Model
final class SetEntry {
    var id: UUID = UUID()
    /// Position within the exercise. See the ordering note at the top of this file.
    var order: Int = 0

    /// Always kilograms. Converted for display when the user prefers pounds.
    var weightKG: Double = 0
    var reps: Int = 0

    var isCompleted: Bool = false
    /// Warm-ups are logged but excluded from volume, PRs and 1RM estimates.
    var isWarmup: Bool = false

    /// A drop set hangs off the set above it rather than standing alone. It is
    /// modelled as an ordinary set with this flag so it still counts toward
    /// volume, while the UI renders it indented under its parent.
    var isDropSet: Bool = false

    /// Rate of perceived exertion, 1–10. Optional.
    var rpe: Double?

    var completedAt: Date?
    var workoutExercise: WorkoutExercise?

    init(
        id: UUID = UUID(),
        order: Int,
        weightKG: Double = 0,
        reps: Int = 0,
        isCompleted: Bool = false,
        isWarmup: Bool = false,
        isDropSet: Bool = false,
        rpe: Double? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.weightKG = weightKG
        self.reps = reps
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.isDropSet = isDropSet
        self.rpe = rpe
        self.completedAt = completedAt
    }

    /// Tonnage contributed by this set.
    var volumeKG: Double { weightKG * Double(reps) }

    /// Estimated one-rep max, or nil when the set cannot support an estimate.
    ///
    /// Bodyweight sets (0 kg) and empty sets yield nil rather than 0, so they
    /// do not drag a strength chart down to the axis.
    func estimatedOneRepMax(formula: OneRepMaxFormula = .epley) -> Double? {
        StrengthMath.estimatedOneRepMax(weightKG: weightKG, reps: reps, formula: formula)
    }

    /// Mark done and stamp the time, which is what starts the rest timer.
    func complete(at date: Date = Date()) {
        isCompleted = true
        completedAt = date
    }

    func uncomplete() {
        isCompleted = false
        completedAt = nil
    }
}
