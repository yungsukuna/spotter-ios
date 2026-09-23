import Foundation

/// Builds a reusable `Routine` template out of a finished `Workout`.
///
/// The reverse of `Routine.makeWorkout()`. Only structure is copied — which
/// exercises, in what order, which supersets, and how many sets to aim for
/// next time — never weights, for the same reason `Routine` never stores
/// weights: the number to lift next time comes from `PreviousPerformance`,
/// not from a plan.
enum RoutineConversion {

    @discardableResult
    static func makeRoutine(from workout: Workout, name: String? = nil) -> Routine {
        let routine = Routine(name: name ?? workout.name)
        for entry in workout.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            // Drop sets are not a separate "set to aim for" — they hang off a
            // working set rather than standing as their own target.
            let workingSetCount = entry.orderedSets.filter { !$0.isDropSet }.count
            let routineEntry = routine.addExercise(exercise, targetSets: max(1, workingSetCount))
            routineEntry.supersetGroup = entry.supersetGroup
        }
        return routine
    }
}
