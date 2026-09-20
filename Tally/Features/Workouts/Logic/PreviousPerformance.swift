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

    /// The placeholder for the set at `index` (0-based) in the *current*
    /// exercise, matched positionally against the previous session.
    ///
    /// Returns nil when the previous session had fewer sets than this one —
    /// e.g. you added a fourth set this time and there is nothing to prefill
    /// it with.
    static func placeholder(
        atIndex index: Int,
        for exercise: Exercise,
        excludingWorkout: Workout? = nil
    ) -> SetPlaceholder? {
        let all = placeholders(for: exercise, excludingWorkout: excludingWorkout)
        guard index >= 0, index < all.count else { return nil }
        return all[index]
    }
}
