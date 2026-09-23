import Foundation
import SwiftData

/// A saved workout template, e.g. "Push Day A".
///
/// Routines hold structure only — which exercises, in what order, how many sets
/// to aim for. They deliberately do not store weights: the weight to use is
/// always taken from the last time that exercise was actually performed, which
/// is what makes the prefill behaviour work without the user maintaining a
/// separate plan.
@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String?
    var createdAt: Date = Date()
    var lastPerformedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise] = []

    /// Sessions started from this routine. Nullify, not cascade — deleting a
    /// routine must not delete the training history performed from it.
    @Relationship(deleteRule: .nullify, inverse: \Workout.sourceRoutine)
    var workouts: [Workout] = []

    init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Exercises in display order. See the ordering note in `Workout.swift`.
    var orderedExercises: [RoutineExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var exerciseCount: Int { exercises.count }

    /// "Bench Press, Incline DB Press, Cable Fly" — the subtitle on the
    /// routine list row.
    var exerciseSummary: String {
        orderedExercises
            .compactMap { $0.exercise?.name }
            .joined(separator: ", ")
    }

    @discardableResult
    func addExercise(_ exercise: Exercise, targetSets: Int = 3) -> RoutineExercise {
        let entry = RoutineExercise(
            exercise: exercise,
            order: (exercises.map(\.order).max() ?? -1) + 1,
            targetSets: targetSets
        )
        entry.routine = self
        exercises.append(entry)
        return entry
    }

    func reorderExercises(to newOrder: [RoutineExercise]) {
        for (index, entry) in newOrder.enumerated() {
            entry.order = index
        }
    }

    func removeExercise(_ entry: RoutineExercise) {
        exercises.removeAll { $0.id == entry.id }
        reorderExercises(to: orderedExercises)
    }

    /// Build a fresh session from this template.
    ///
    /// Sets are created empty and uncompleted; the logging screen fills their
    /// placeholders from the user's last performance of each exercise.
    func makeWorkout(at date: Date = Date(), calendar: Calendar = .current) -> Workout {
        let workout = Workout(
            name: name,
            startedAt: date,
            sourceRoutine: self,
            calendar: calendar
        )
        for routineExercise in orderedExercises {
            let entry = WorkoutExercise(
                exercise: routineExercise.exercise,
                order: routineExercise.order,
                supersetGroup: routineExercise.supersetGroup
            )
            entry.workout = workout
            for setIndex in 0..<max(1, routineExercise.targetSets) {
                let set = SetEntry(order: setIndex)
                set.workoutExercise = entry
                entry.sets.append(set)
            }
            workout.exercises.append(entry)
        }
        return workout
    }
}

/// One exercise slot within a routine.
@Model
final class RoutineExercise {
    var id: UUID = UUID()
    /// Position within the routine. See the ordering note in `Workout.swift`.
    var order: Int = 0
    /// How many sets to create when a session is started from this routine.
    var targetSets: Int = 3
    /// Optional coaching note, e.g. "3 sec eccentric".
    var notes: String?
    /// Mirrors `WorkoutExercise.supersetGroup`; carried through to the session.
    var supersetGroup: Int?

    var exercise: Exercise?
    var routine: Routine?

    init(
        id: UUID = UUID(),
        exercise: Exercise?,
        order: Int,
        targetSets: Int = 3,
        notes: String? = nil,
        supersetGroup: Int? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.targetSets = targetSets
        self.notes = notes
        self.supersetGroup = supersetGroup
    }

    var displayName: String { exercise?.name ?? "Deleted exercise" }
}
