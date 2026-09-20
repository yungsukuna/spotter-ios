import Foundation

/// Strength calculations shared by the logging screen, the stats screen and the
/// personal-records table.
///
/// Kept as free functions on a caseless enum rather than methods on `SetEntry`
/// so they can be unit-tested without standing up a SwiftData container.
enum StrengthMath {

    // MARK: - Estimated one-rep max

    /// Estimate a one-rep max from a submaximal set.
    ///
    /// Returns nil rather than zero for sets that cannot support an estimate —
    /// zero or negative weight (bodyweight movements), zero reps, or rep counts
    /// high enough that the formulae stop being meaningful. A nil here keeps
    /// bodyweight work out of a strength chart instead of pinning it to the
    /// axis, which is why callers get an optional.
    ///
    /// - Note: A single rep is its own one-rep max, returned unchanged by both
    ///   formulae.
    static func estimatedOneRepMax(
        weightKG: Double,
        reps: Int,
        formula: OneRepMaxFormula = .epley
    ) -> Double? {
        guard weightKG > 0, reps > 0, reps <= maxMeaningfulReps else { return nil }
        guard weightKG.isFinite else { return nil }

        let repsDouble = Double(reps)
        switch formula {
        case .epley:
            // Epley: 1RM = w · (1 + r/30)
            return weightKG * (1 + repsDouble / 30)
        case .brzycki:
            // Brzycki: 1RM = w · 36 / (37 − r)
            // The denominator vanishes at 37 reps; `maxMeaningfulReps` keeps us
            // well clear of it, but guard anyway rather than return an infinity.
            let denominator = 37 - repsDouble
            guard denominator > 0 else { return nil }
            return weightKG * 36 / denominator
        }
    }

    /// Beyond this, rep-max formulae diverge badly from reality and the number
    /// stops being useful. Sets above it are excluded from 1RM estimates.
    static let maxMeaningfulReps = 20

    // MARK: - Volume

    /// Tonnage for a single set.
    static func volume(weightKG: Double, reps: Int) -> Double {
        guard weightKG.isFinite, reps > 0 else { return 0 }
        return weightKG * Double(reps)
    }

    // MARK: - Personal records

    /// The best weight lifted for a given rep count.
    struct RepRecord: Hashable, Identifiable, Sendable {
        var reps: Int
        var weightKG: Double
        var achievedAt: Date
        var workoutID: UUID?

        var id: Int { reps }
    }

    /// Build the rep-record table: for each rep count, the heaviest weight ever
    /// completed at that many reps.
    ///
    /// This is the "rep records" view RepCount puts behind Premium — a row per
    /// rep count from 1 upward, showing the best weight achieved for each.
    ///
    /// - Parameter sets: every completed working set for one exercise, across
    ///   all history. Warm-ups should already be filtered out by the caller.
    static func repRecords(from sets: [CompletedSet]) -> [RepRecord] {
        var best: [Int: RepRecord] = [:]

        for set in sets {
            guard set.reps > 0, set.weightKG > 0 else { continue }
            let candidate = RepRecord(
                reps: set.reps,
                weightKG: set.weightKG,
                achievedAt: set.performedAt,
                workoutID: set.workoutID
            )
            if let existing = best[set.reps] {
                // Ties go to the earlier date: the first time you hit a weight
                // is when you set the record, not the most recent repeat of it.
                if candidate.weightKG > existing.weightKG {
                    best[set.reps] = candidate
                }
            } else {
                best[set.reps] = candidate
            }
        }

        return best.values.sorted { $0.reps < $1.reps }
    }

    /// True when `candidate` would beat every prior set at the same rep count.
    /// Drives the PR badge shown on the logging screen as a set is completed.
    static func isPersonalRecord(
        candidate: CompletedSet,
        against history: [CompletedSet]
    ) -> Bool {
        guard candidate.weightKG > 0, candidate.reps > 0 else { return false }
        let priorBest = history
            .filter { $0.reps == candidate.reps }
            .map(\.weightKG)
            .max()
        guard let priorBest else { return true }
        return candidate.weightKG > priorBest
    }

    /// A flattened, storage-independent view of one completed set.
    ///
    /// Statistics operate on this rather than on `SetEntry` so the maths can be
    /// tested with plain values, and so a set's provenance (which workout, when)
    /// survives being pulled out of the object graph.
    struct CompletedSet: Hashable, Sendable {
        var weightKG: Double
        var reps: Int
        var performedAt: Date
        var workoutID: UUID?

        init(weightKG: Double, reps: Int, performedAt: Date, workoutID: UUID? = nil) {
            self.weightKG = weightKG
            self.reps = reps
            self.performedAt = performedAt
            self.workoutID = workoutID
        }

        var volumeKG: Double { StrengthMath.volume(weightKG: weightKG, reps: reps) }

        func estimatedOneRepMax(formula: OneRepMaxFormula = .epley) -> Double? {
            StrengthMath.estimatedOneRepMax(weightKG: weightKG, reps: reps, formula: formula)
        }
    }
}

extension SetEntry {
    /// Flatten this set for use with ``StrengthMath``. Nil when the set was
    /// never completed, since statistics only ever consider completed work.
    var completedSetValue: StrengthMath.CompletedSet? {
        guard isCompleted else { return nil }
        return StrengthMath.CompletedSet(
            weightKG: weightKG,
            reps: reps,
            performedAt: completedAt ?? workoutExercise?.workout?.startedAt ?? Date(),
            workoutID: workoutExercise?.workout?.id
        )
    }
}
