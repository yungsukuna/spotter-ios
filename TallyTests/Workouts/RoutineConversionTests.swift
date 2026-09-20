import Foundation
import SwiftData
import Testing

@testable import Tally

@MainActor
@Suite("RoutineConversion")
struct RoutineConversionTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TallySchema.makeContainer(inMemory: true))
    }

    @Test("Saving a workout as a routine copies exercises, order and target sets")
    func savingCopiesStructure() throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press")
        let row = Exercise(name: "Barbell Row")
        context.insert(bench)
        context.insert(row)

        let workout = Workout(name: "Push Pull")
        context.insert(workout)
        let benchEntry = workout.addExercise(bench)
        benchEntry.addSet(weightKG: 60, reps: 8).complete()
        benchEntry.addSet(weightKG: 60, reps: 8).complete()
        benchEntry.addSet(weightKG: 60, reps: 6).complete()
        workout.addExercise(row).addSet(weightKG: 70, reps: 8).complete()

        let routine = RoutineConversion.makeRoutine(from: workout)

        #expect(routine.name == "Push Pull")
        #expect(routine.orderedExercises.map(\.displayName) == ["Bench Press", "Barbell Row"])
        #expect(routine.orderedExercises[0].targetSets == 3)
        #expect(routine.orderedExercises[1].targetSets == 1)
    }

    @Test("Drop sets are not counted as separate targets")
    func dropSetsNotCountedAsTargets() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Lateral Raise")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        let top = entry.addSet(weightKG: 14, reps: 12)
        top.complete()
        DropSetInsertion.insertDropSet(after: top, weightKG: 8, reps: 10)?.complete()

        let routine = RoutineConversion.makeRoutine(from: workout)

        #expect(routine.orderedExercises.first?.targetSets == 1)
    }

    @Test("Superset membership carries over into the routine")
    func supersetMembershipCarriesOver() throws {
        let context = try makeContext()
        let a = Exercise(name: "A")
        let b = Exercise(name: "B")
        context.insert(a)
        context.insert(b)
        let workout = Workout()
        context.insert(workout)
        let entryA = workout.addExercise(a)
        let entryB = workout.addExercise(b)
        SupersetGrouping.groupWithNext(entryA, in: workout)

        let routine = RoutineConversion.makeRoutine(from: workout)

        let ordered = routine.orderedExercises
        #expect(ordered[0].supersetGroup != nil)
        #expect(ordered[0].supersetGroup == ordered[1].supersetGroup)
    }

    @Test("An exercise with zero sets still gets a minimum target of one")
    func zeroSetExerciseGetsMinimumTarget() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Empty Exercise")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        workout.addExercise(exercise)

        let routine = RoutineConversion.makeRoutine(from: workout)

        #expect(routine.orderedExercises.first?.targetSets == 1)
    }

    @Test("A routine built from a workout can start a new session")
    func routineRoundTripsIntoAWorkout() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Overhead Press")
        context.insert(exercise)
        let original = Workout(name: "Shoulder Day")
        context.insert(original)
        original.addExercise(exercise).addSet(weightKG: 40, reps: 8).complete()

        let routine = RoutineConversion.makeRoutine(from: original)
        context.insert(routine)
        let newSession = routine.makeWorkout()

        #expect(newSession.name == "Shoulder Day")
        #expect(newSession.orderedExercises.first?.displayName == "Overhead Press")
        #expect(newSession.completedSetCount == 0)
    }
}
