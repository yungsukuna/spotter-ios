import Foundation
import SwiftData
import Testing

@testable import Spotter

@Suite("WarmupGenerator")
struct WarmupGeneratorTests {

    @Test("100 kg working weight gives the standard four-step ramp")
    func standardKilogramRamp() {
        let sets = WarmupGenerator.generate(workingWeightKG: 100, barKG: 20, unit: .kilograms)
        #expect(sets == [
            .init(weightKG: 20, reps: 10),
            .init(weightKG: 40, reps: 5),
            .init(weightKG: 60, reps: 3),
            .init(weightKG: 80, reps: 2),
        ])
    }

    @Test("Rounding happens in pounds when the display unit is pounds")
    func poundsRounding() {
        let workingWeightKG = UnitConverter.poundsToKilograms(225)
        let barKG = UnitConverter.poundsToKilograms(45)
        let sets = WarmupGenerator.generate(workingWeightKG: workingWeightKG, barKG: barKG, unit: .pounds)

        let poundValues = sets.map { UnitConverter.kilogramsToPounds($0.weightKG).rounded() }
        #expect(poundValues == [45, 90, 135, 180])
        #expect(sets.map(\.reps) == [10, 5, 3, 2])
    }

    @Test("A light working weight collapses steps that round to at or below the bar")
    func lightWeightCollapsesNearBarSteps() {
        // 40% and 60% of 76 lb round (to the nearest 5 lb) to at or below a
        // 45 lb bar, so only the bar and the 80% step survive.
        let workingWeightKG = UnitConverter.poundsToKilograms(76)
        let barKG = UnitConverter.poundsToKilograms(45)
        let sets = WarmupGenerator.generate(workingWeightKG: workingWeightKG, barKG: barKG, unit: .pounds)

        #expect(sets.count == 2)
        #expect(sets.first?.reps == 10)
        #expect(sets.last?.reps == 2)
    }

    @Test("A zero or negative working weight generates nothing")
    func zeroWorkingWeightGeneratesNothing() {
        #expect(WarmupGenerator.generate(workingWeightKG: 0, barKG: 20, unit: .kilograms).isEmpty)
        #expect(WarmupGenerator.generate(workingWeightKG: -10, barKG: 20, unit: .kilograms).isEmpty)
    }

    // MARK: - Insertion

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @MainActor
    @Test("Warm-ups are inserted before the first working set and everything is renumbered")
    func insertionOrderAndRenumbering() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Back Squat", equipment: .barbell)
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        let working1 = entry.addSet(weightKG: 100, reps: 5)
        let working2 = entry.addSet(weightKG: 100, reps: 5)

        let inserted = WarmupGenerator.insertWarmups(
            into: entry,
            barKG: 20,
            unit: .kilograms,
            placeholderWeightKG: nil
        )

        #expect(inserted.count == 4)
        let ordered = entry.orderedSets
        #expect(ordered.count == 6)
        #expect(ordered.map(\.order) == [0, 1, 2, 3, 4, 5])
        // Evaluated outside #expect: the macro's expansion of a key-path
        // argument to `allSatisfy` does not compile.
        let firstFourAreWarmups = ordered.prefix(4).allSatisfy { $0.isWarmup }
        #expect(firstFourAreWarmups)
        #expect(ordered[4].id == working1.id)
        #expect(ordered[5].id == working2.id)
    }

    @MainActor
    @Test("Insertion falls back to the placeholder weight when the first working set has none typed yet")
    func insertionUsesPlaceholderWeight() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Front Squat", equipment: .barbell)
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet() // untyped: weightKG defaults to 0

        let inserted = WarmupGenerator.insertWarmups(
            into: entry,
            barKG: 20,
            unit: .kilograms,
            placeholderWeightKG: 100
        )

        #expect(inserted.map(\.weightKG) == [20, 40, 60, 80])
    }

    @MainActor
    @Test("No working set means nothing is inserted")
    func noWorkingSetInsertsNothing() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press", equipment: .barbell)
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet(isWarmup: true)

        let inserted = WarmupGenerator.insertWarmups(
            into: entry,
            barKG: 20,
            unit: .kilograms,
            placeholderWeightKG: nil
        )

        #expect(inserted.isEmpty)
        #expect(entry.orderedSets.count == 1)
    }
}
