import Foundation

/// Estimates calories burned for a cardio session.
///
/// Deliberately rough — see the note on `CardioEntry` in `Exercise.swift`:
/// this is a strength app with a basic cardio log attached, not a running
/// tracker. The estimate is shown as an editable placeholder in
/// `CardioEntrySheet`, never forced on the user.
///
/// **Not added to the calorie budget** (Decision 4 in `docs/PHASE2-PLAN.md`).
/// If an opt-in "count toward budget" setting is ever added, switch to net
/// METs (`MET − 1`) there to avoid double-counting resting energy; this
/// estimator stays gross, which is the right number for a stand-alone
/// display figure.
enum CardioCalories {

    /// Gross MET values (approximate Compendium of Physical Activities
    /// figures), keyed by the seed exercise name in `ExerciseLibrary`. A
    /// custom cardio exercise's name won't be in here, which is intentional —
    /// see ``estimate(exerciseName:durationSeconds:distanceKM:bodyWeightKG:)``.
    static let metTable: [String: Double] = [
        "Treadmill": 6.0,
        "Running": 9.8,
        "Cycling": 6.8,
        "Rowing Machine": 7.0,
        "Elliptical": 5.0,
        "Stair Climber": 9.0,
        "Swimming": 5.8,
        "Jump Rope": 11.8,
    ]

    /// Exercises that get the distance-based formula instead of a MET when a
    /// distance is entered, because it tracks effort more accurately than a
    /// single fixed MET across a wide range of paces.
    private static let distanceBasedNames: Set<String> = ["Running", "Treadmill"]

    /// Rough constant for running/walking-style locomotion: about 1 kcal per
    /// kilogram of body weight per kilometre covered, independent of pace.
    private static let kcalPerKGPerKM = 1.0

    /// Estimated kcal burned, or nil when it can't be estimated.
    ///
    /// - Nil body weight (Feature 1's trend has no data yet) always gives
    ///   nil — an unknown figure must never be guessed at as zero.
    /// - A custom exercise (or any name outside ``metTable``) gives nil
    ///   unless a distance is given for a distance-based name.
    static func estimate(
        exerciseName: String,
        durationSeconds: Double,
        distanceKM: Double?,
        bodyWeightKG: Double?
    ) -> Double? {
        guard let bodyWeightKG, bodyWeightKG > 0 else { return nil }
        guard durationSeconds > 0 else { return nil }

        if let distanceKM, distanceKM > 0, distanceBasedNames.contains(exerciseName) {
            return kcalPerKGPerKM * bodyWeightKG * distanceKM
        }

        guard let met = metTable[exerciseName] else { return nil }
        let hours = durationSeconds / 3600
        return met * bodyWeightKG * hours
    }
}
