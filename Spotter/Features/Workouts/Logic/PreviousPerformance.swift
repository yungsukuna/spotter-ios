import Foundation

/// Finds what to show as placeholder text in a set row: the numbers from the
/// last time this exercise was actually performed.
///
/// This is the core speed feature RepCount is built around — confirming an
/// unchanged set becomes one tap because the field already shows what you did
/// last time. Kept as a free function over plain model reads (not a view
/// computed property) so it can be unit tested without standing up a view.
enum PreviousPerformance {

    /// A previous set's numbers, flattened out of `SetEntry` so the logging
    /// screen doesn't need to hold a reference to the old, finished workout.
    struct SetPlaceholder: Hashable, Sendable {
        var weightKG: Double
        var reps: Int
        var isWarmup: Bool
        var isDropSet: Bool
    }

    /// A set's identity within its own session, used to match it against the
    /// *same kind* of set in a previous session — the k-th warm-up to the
    /// previous k-th warm-up, the k-th working set to the previous k-th
    /// working set, and a drop set to its parent working set's k-th drop set
    /// — instead of matching by raw position.
    ///
    /// Matching by raw position breaks the moment a warm-up (or an extra drop
    /// set) is inserted, because it shifts every following working set's
    /// placeholder out of alignment with history. See "Must change first" #5
    /// in `docs/PHASE2-PLAN.md`.
    enum SetKind: Hashable {
        case warmup(index: Int)
        case working(index: Int)
        case dropSet(parentWorkingIndex: Int, dropIndex: Int)
    }

    /// The most recent *finished* workout that logged `exercise`, other than
    /// `excludingWorkout` (the session currently being edited, which may
    /// already contain uncompleted sets for the same exercise and must never
    /// be mistaken for history).
    static func mostRecentEntry(
        for exercise: Exercise,
        excludingWorkout: Workout? = nil
    ) -> WorkoutExercise? {
        exercise.workoutEntries
            .filter { entry in
                guard let workout = entry.workout, workout.finishedAt != nil else { return false }
                if let excludingWorkout, workout.id == excludingWorkout.id { return false }
                return true
            }
            .max { lhs, rhs in
                let lhsDate = lhs.workout?.finishedAt ?? lhs.workout?.startedAt ?? .distantPast
                let rhsDate = rhs.workout?.finishedAt ?? rhs.workout?.startedAt ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    /// Every set from the most recent previous session, in order. Empty for a
    /// first-ever session — callers should treat that as "no placeholders",
    /// not as an error.
    static func placeholders(
        for exercise: Exercise,
        excludingWorkout: Workout? = nil
    ) -> [SetPlaceholder] {
        guard let entry = mostRecentEntry(for: exercise, excludingWorkout: excludingWorkout) else {
            return []
        }
        return entry.orderedSets.map {
            SetPlaceholder(
                weightKG: $0.weightKG,
                reps: $0.reps,
                isWarmup: $0.isWarmup,
                isDropSet: $0.isDropSet
            )
        }
    }

    /// Classifies an ordered list of sets into their `SetKind`s, in the same
    /// order as the input. A drop set's parent is the nearest preceding
    /// non-drop-set in the list.
    static func kinds(for orderedSets: [SetEntry]) -> [SetKind] {
        var result: [SetKind] = []
        var warmupCount = 0
        var workingCount = 0
        var currentWorkingIndex = 0
        var dropCountForCurrentWorking = 0

        for set in orderedSets {
            if set.isDropSet {
                result.append(.dropSet(parentWorkingIndex: currentWorkingIndex, dropIndex: dropCountForCurrentWorking))
                dropCountForCurrentWorking += 1
            } else if set.isWarmup {
                result.append(.warmup(index: warmupCount))
                warmupCount += 1
            } else {
                currentWorkingIndex = workingCount
                dropCountForCurrentWorking = 0
                result.append(.working(index: workingCount))
                workingCount += 1
            }
        }
        return result
    }

    /// The previous session's placeholder for the set at `index` within
    /// `orderedSets` — the *current* session's full ordered set list, needed
    /// to classify that set's `SetKind` — matched by kind rather than
    /// position against the most recent previous session.
    ///
    /// Returns nil when there is no previous session, or when it has no set
    /// of the matching kind (e.g. you added a fourth working set this time,
    /// or this is the first time this exercise got warm-ups).
    static func placeholder(
        atIndex index: Int,
        in orderedSets: [SetEntry],
        for exercise: Exercise,
        excludingWorkout: Workout? = nil
    ) -> SetPlaceholder? {
        guard index >= 0, index < orderedSets.count else { return nil }
        guard let previousEntry = mostRecentEntry(for: exercise, excludingWorkout: excludingWorkout) else {
            return nil
        }

        let targetKind = kinds(for: orderedSets)[index]
        let previousOrdered = previousEntry.orderedSets
        let previousKinds = kinds(for: previousOrdered)

        guard let previousIndex = previousKinds.firstIndex(of: targetKind) else { return nil }
        let previousSet = previousOrdered[previousIndex]
        return SetPlaceholder(
            weightKG: previousSet.weightKG,
            reps: previousSet.reps,
            isWarmup: previousSet.isWarmup,
            isDropSet: previousSet.isDropSet
        )
    }
}
