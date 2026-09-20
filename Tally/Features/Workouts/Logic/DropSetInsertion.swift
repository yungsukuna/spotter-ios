import Foundation

/// Inserts a drop set directly beneath its parent, renumbering everything
/// after it.
///
/// A drop set is an ordinary `SetEntry` with `isDropSet` set — see the note on
/// that property — so "add a drop set" is really "insert a new set at
/// `parent.order + 1` and shift the rest down", which is easy to get off by
/// one. Isolated here so the ordering can be tested without a view.
enum DropSetInsertion {

    /// Insert a new, uncompleted drop set immediately after `parent`.
    ///
    /// Returns nil if `parent` is not attached to a `WorkoutExercise` (should
    /// not happen for a set already on screen, but nothing here should force
    /// -unwrap a relationship).
    @discardableResult
    static func insertDropSet(
        after parent: SetEntry,
        weightKG: Double = 0,
        reps: Int = 0
    ) -> SetEntry? {
        guard let workoutExercise = parent.workoutExercise else { return nil }

        // Compute the correct final sequence explicitly rather than relying on
        // sort-stability to break the tie between the new set and whatever
        // used to occupy this order index — `orderedSets` after a bare
        // `sets.append` would otherwise depend on the raw relationship
        // array's incidental ordering.
        var ordered = workoutExercise.orderedSets
        guard let parentIndex = ordered.firstIndex(where: { $0.id == parent.id }) else { return nil }

        let dropSet = SetEntry(
            order: parentIndex + 1,
            weightKG: weightKG,
            reps: reps,
            isDropSet: true
        )
        dropSet.workoutExercise = workoutExercise
        workoutExercise.sets.append(dropSet)
        ordered.insert(dropSet, at: parentIndex + 1)

        for (index, set) in ordered.enumerated() {
            set.order = index
        }

        return dropSet
    }
}
