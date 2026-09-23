import Foundation

/// Builds and inserts a standard warm-up ramp ahead of an exercise's working
/// sets.
///
/// The scheme (empty bar × 10, 40% × 5, 60% × 3, 80% × 2) is computed in the
/// user's display unit and rounded to the nearest loadable increment via
/// `PlateCalculator`, so the numbers it produces are always something that
/// can actually be racked. Steps that round down to at or below the bar are
/// dropped — a bar-only warm-up is still shown once, as the first entry, but
/// never repeated.
enum WarmupGenerator {

    /// One generated warm-up set.
    struct WarmupSet: Equatable {
        var weightKG: Double
        var reps: Int
    }

    /// (fraction of the working weight, reps). The first step ignores the
    /// fraction and uses the bar weight instead — see `generate`.
    private static let scheme: [(fraction: Double, reps: Int)] = [
        (0.0, 10),
        (0.4, 5),
        (0.6, 3),
        (0.8, 2),
    ]

    /// Generates the warm-up ramp for a working weight.
    ///
    /// - Parameters:
    ///   - workingWeightKG: the top working set's weight, in kilograms.
    ///   - barKG: the bar weight, in kilograms.
    ///   - unit: the display unit to round in — see the type-level note.
    /// - Returns: empty when there is no working weight to ramp up to.
    static func generate(workingWeightKG: Double, barKG: Double, unit: WeightUnit) -> [WarmupSet] {
        guard workingWeightKG > 0 else { return [] }

        var result: [WarmupSet] = []
        for (index, step) in scheme.enumerated() {
            let rawKG = step.fraction == 0 ? barKG : workingWeightKG * step.fraction
            let rawDisplay = UnitConverter.weight(rawKG, in: unit)
            let roundedDisplay = PlateCalculator.roundToLoadable(rawDisplay, unit: unit)
            let roundedKG = UnitConverter.weightToKilograms(roundedDisplay, from: unit)

            // Every step after the bar itself is dropped once it rounds down
            // to at or below the bar — there is nothing meaningful left to
            // warm up with at that point.
            if index > 0, roundedKG <= barKG { continue }
            if let last = result.last, abs(last.weightKG - roundedKG) < 0.001 { continue }

            result.append(WarmupSet(weightKG: roundedKG, reps: step.reps))
        }
        return result
    }

    /// Inserts the generated warm-up sets as `SetEntry(isWarmup: true)`
    /// immediately before the exercise's first working set, renumbering the
    /// whole list afterwards — the same pattern `DropSetInsertion` uses.
    ///
    /// - Parameters:
    ///   - entry: the exercise to add warm-ups to.
    ///   - barKG: the bar weight, in kilograms.
    ///   - unit: the display unit to round the scheme in.
    ///   - placeholderWeightKG: the previous session's weight for the first
    ///     working set, used only when that set doesn't have a weight typed
    ///     in yet.
    /// - Returns: the inserted sets, in order. Empty if there is no working
    ///   set to ramp up to, or nothing to warm up with.
    @discardableResult
    static func insertWarmups(
        into entry: WorkoutExercise,
        barKG: Double,
        unit: WeightUnit,
        placeholderWeightKG: Double?
    ) -> [SetEntry] {
        let ordered = entry.orderedSets
        guard let firstWorkingIndex = ordered.firstIndex(where: { !$0.isWarmup && !$0.isDropSet }) else {
            return []
        }

        let firstWorking = ordered[firstWorkingIndex]
        let workingWeightKG = firstWorking.weightKG > 0 ? firstWorking.weightKG : (placeholderWeightKG ?? 0)
        let scheme = generate(workingWeightKG: workingWeightKG, barKG: barKG, unit: unit)
        guard !scheme.isEmpty else { return [] }

        var newSets: [SetEntry] = []
        for warmup in scheme {
            let set = SetEntry(order: 0, weightKG: warmup.weightKG, reps: warmup.reps, isWarmup: true)
            set.workoutExercise = entry
            entry.sets.append(set)
            newSets.append(set)
        }

        var combined = ordered
        combined.insert(contentsOf: newSets, at: firstWorkingIndex)
        for (index, set) in combined.enumerated() {
            set.order = index
        }

        return newSets
    }
}
