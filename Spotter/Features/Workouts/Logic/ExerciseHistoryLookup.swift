import Foundation

/// Backs the "exercise history" sheet reachable from inside the logging
/// screen: every finished session that logged a given exercise.
enum ExerciseHistoryLookup {

    /// One past session's sets for a single exercise.
    struct PastSession: Identifiable, Hashable, Sendable {
        /// The workout's own id — sessions are unique per workout.
        var id: UUID
        var date: Date
        var sets: [StrengthMath.CompletedSet]
        /// That session's note for this exercise (`WorkoutExercise.notes`),
        /// if one was left.
        var notes: String?
    }

    /// Finished sessions that logged `exercise`, most recent first.
    ///
    /// `excludingWorkoutID` leaves out the session currently being edited: its
    /// sets are still in progress and do not belong in "history" yet, even
    /// once a few of them are ticked off.
    static func pastSessions(
        for exercise: Exercise,
        excludingWorkoutID: UUID? = nil
    ) -> [PastSession] {
        exercise.workoutEntries
            .compactMap { entry -> PastSession? in
                guard let workout = entry.workout,
                      workout.finishedAt != nil,
                      workout.id != excludingWorkoutID
                else {
                    return nil
                }
                let completed = entry.orderedSets.compactMap(\.completedSetValue)
                guard !completed.isEmpty else { return nil }
                return PastSession(id: workout.id, date: workout.startedAt, sets: completed, notes: entry.notes)
            }
            .sorted { $0.date > $1.date }
    }
}
