import Foundation
import Testing

@testable import Tally

@Suite("CardioCalories")
struct CardioCaloriesTests {

    @Test("The MET formula: kcal = MET × kg × hours")
    func metFormula() {
        // Cycling MET is 6.8. 80 kg for 1 hour (3600s).
        let kcal = CardioCalories.estimate(
            exerciseName: "Cycling",
            durationSeconds: 3600,
            distanceKM: nil,
            bodyWeightKG: 80
        )
        #expect(kcal != nil)
        #expect(abs((kcal ?? 0) - 6.8 * 80) < 0.0001)
    }

    @Test("Running with a distance uses the distance-based formula instead of the MET")
    func distanceBasedRunning() {
        // ~1 kcal/kg/km, 80 kg over 10 km, regardless of duration.
        let kcal = CardioCalories.estimate(
            exerciseName: "Running",
            durationSeconds: 3000,
            distanceKM: 10,
            bodyWeightKG: 80
        )
        #expect(kcal != nil)
        #expect(abs((kcal ?? 0) - 800) < 0.0001)
    }

    @Test("Running without a distance falls back to the MET formula")
    func runningWithoutDistanceUsesMET() {
        let kcal = CardioCalories.estimate(
            exerciseName: "Running",
            durationSeconds: 1800,
            distanceKM: nil,
            bodyWeightKG: 70
        )
        #expect(kcal != nil)
        #expect(abs((kcal ?? 0) - 9.8 * 70 * 0.5) < 0.0001)
    }

    @Test("No known body weight gives nil, never a guess")
    func noWeightGivesNil() {
        let kcal = CardioCalories.estimate(
            exerciseName: "Treadmill",
            durationSeconds: 1800,
            distanceKM: nil,
            bodyWeightKG: nil
        )
        #expect(kcal == nil)
    }

    @Test("An unknown (custom) exercise name gives nil")
    func unknownExerciseGivesNil() {
        let kcal = CardioCalories.estimate(
            exerciseName: "Backyard Obstacle Course",
            durationSeconds: 1800,
            distanceKM: nil,
            bodyWeightKG: 80
        )
        #expect(kcal == nil)
    }

    @Test("Zero duration gives nil rather than zero kcal")
    func zeroDurationGivesNil() {
        let kcal = CardioCalories.estimate(
            exerciseName: "Rowing Machine",
            durationSeconds: 0,
            distanceKM: nil,
            bodyWeightKG: 80
        )
        #expect(kcal == nil)
    }
}
