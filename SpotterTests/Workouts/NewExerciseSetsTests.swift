import Foundation
import SwiftData
import Testing

@testable import Spotter

@MainActor
@Suite("NewExerciseSets")
struct NewExerciseSetsTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @Test("A first-ever exercise starts with one empty set")
    func firstEverExerciseGetsOneSet() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)

        let entry = workout.addExercise(exercise)
        NewExerciseSets.populate(entry, excludingWorkout: workout)

        #expect(entry.orderedSets.count == 1)
        #expect(entry.orderedSets.first?.weightKG == 0)
        #expect(entry.orderedSets.first?.isCompleted == false)
    }

    @Test("Sets mirror the structure of the last session, without its numbers")
    func setsMirrorLastSession() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)

        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let previousEntry = previous.addExercise(exercise)
        previousEntry.addSet(weightKG: 40, reps: 10, isWarmup: true).complete()
        let top = previousEntry.addSet(weightKG: 100, reps: 5)
        top.complete()
        DropSetInsertion.insertDropSet(after: top, weightKG: 80, reps: 8)?.complete()
        previousEntry.addSet(weightKG: 100, reps: 5).complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        let workout = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        NewExerciseSets.populate(entry, excludingWorkout: workout)

        let sets = entry.orderedSets
        #expect(sets.map(\.isWarmup) == [true, false, false, false])
        #expect(sets.map(\.isDropSet) == [false, false, true, false])
        #expect(sets.allSatisfy { $0.weightKG == 0 && $0.reps == 0 && !$0.isCompleted })
    }

    @Test("An entry that already has sets is left alone")
    func existingSetsAreLeftAlone() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Row")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet()
        entry.addSet()

        NewExerciseSets.populate(entry, excludingWorkout: workout)

        #expect(entry.orderedSets.count == 2)
    }
}
