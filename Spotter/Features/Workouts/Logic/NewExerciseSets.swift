import Foundation

/// The rows an exercise starts with when it is added to a session mid-workout.
///
/// Mirrors the set structure of the last time the exercise was performed —
/// same number of warm-ups, working sets and drop sets, in the same order —
/// so every row lines up with a `PreviousPerformance` placeholder and an
/// unchanged workout is one tap per set. The sets themselves are left empty;
/// the numbers come from the placeholders. A first-ever exercise gets a
/// single empty set so there is always something to type into.
enum NewExerciseSets {

    static func populate(_ entry: WorkoutExercise, excludingWorkout: Workout? = nil) {
        guard entry.sets.isEmpty else { return }
        let previous = entry.exercise.map {
            PreviousPerformance.placeholders(for: $0, excludingWorkout: excludingWorkout)
        } ?? []

        guard !previous.isEmpty else {
            entry.addSet()
            return
        }
        for placeholder in previous {
            let set = entry.addSet(isWarmup: placeholder.isWarmup)
            set.isDropSet = placeholder.isDropSet
        }
    }
}
