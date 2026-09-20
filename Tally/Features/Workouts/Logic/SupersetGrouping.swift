import Foundation

/// Rules for grouping and ungrouping exercises into a superset.
///
/// RepCount's supersets are always adjacent exercises performed alternately,
/// drawn as one continuous bracket down the group. Adjacency is enforced by
/// construction here — the only grouping operation offered is "merge with the
/// exercise immediately after this one" — rather than by validating an
/// arbitrary selection after the fact.
enum SupersetGrouping {

    /// Where an exercise sits within its superset's visual bracket.
    enum BracketPosition: Equatable {
        /// Not in a superset.
        case none
        /// In a "superset" of one — should not normally occur, but drawn as
        /// a self-contained bracket rather than crashing.
        case single
        case first
        case middle
        case last
    }

    /// The bracket position for `entry`, derived from its neighbours in the
    /// workout's ordering.
    static func bracketPosition(for entry: WorkoutExercise, in workout: Workout) -> BracketPosition {
        guard let group = entry.supersetGroup else { return .none }
        let ordered = workout.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == entry.id }) else { return .none }

        let sameBefore = index > 0 && ordered[index - 1].supersetGroup == group
        let sameAfter = index < ordered.count - 1 && ordered[index + 1].supersetGroup == group

        switch (sameBefore, sameAfter) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    /// True when every one of `entries` sits contiguously, in some order,
    /// within `workout`'s ordering — the only shape a bracket can draw.
    ///
    /// Exposed mainly to document and test the invariant ``groupWithNext(_:in:)``
    /// relies on for correctness, since that operation only ever merges with a
    /// literal neighbour and therefore can never violate it.
    static func isContiguous(_ entries: [WorkoutExercise], in workout: Workout) -> Bool {
        guard !entries.isEmpty else { return false }
        let ids = Set(entries.map(\.id))
        let ordered = workout.orderedExercises
        guard let firstIndex = ordered.firstIndex(where: { ids.contains($0.id) }) else { return false }
        let end = firstIndex + entries.count
        guard end <= ordered.count else { return false }
        let slice = ordered[firstIndex..<end]
        return Set(slice.map(\.id)) == ids
    }

    /// Merge `entry` with the exercise immediately after it into one
    /// superset.
    ///
    /// If the next exercise already belongs to a group, `entry` joins that
    /// group — which is how a superset grows past two exercises, one
    /// "group with next" at a time. If neither is grouped, a fresh group id
    /// is allocated. A no-op when `entry` is already last.
    @discardableResult
    static func groupWithNext(_ entry: WorkoutExercise, in workout: Workout) -> Bool {
        let ordered = workout.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == entry.id }), index + 1 < ordered.count else {
            return false
        }
        let next = ordered[index + 1]

        if let nextGroup = next.supersetGroup {
            entry.supersetGroup = nextGroup
        } else if let ownGroup = entry.supersetGroup {
            next.supersetGroup = ownGroup
        } else {
            let newGroup = (workout.exercises.compactMap(\.supersetGroup).max() ?? 0) + 1
            entry.supersetGroup = newGroup
            next.supersetGroup = newGroup
        }
        return true
    }

    /// Remove `entry` from whatever superset it belongs to. Other members are
    /// left grouped with each other.
    static func ungroup(_ entry: WorkoutExercise) {
        entry.supersetGroup = nil
    }
}
