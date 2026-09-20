import Foundation
import SwiftData
import Testing

@testable import Tally

@MainActor
@Suite("DropSetInsertion")
struct DropSetInsertionTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TallySchema.makeContainer(inMemory: true))
    }

    @Test("A drop set lands directly after its parent")
    func dropSetLandsAfterParent() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Lateral Raise")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        let first = entry.addSet(weightKG: 14, reps: 12)
        let second = entry.addSet(weightKG: 14, reps: 10)

        let drop = try #require(DropSetInsertion.insertDropSet(after: first, weightKG: 8, reps: 10))

        let ordered = entry.orderedSets
        #expect(ordered.map(\.id) == [first.id, drop.id, second.id])
        #expect(ordered.map(\.order) == [0, 1, 2])
        #expect(drop.isDropSet)
    }

    @Test("Inserting after the last set appends it at the end")
    func insertingAfterLastSetAppends() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Cable Curl")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        let only = entry.addSet(weightKG: 20, reps: 12)
        let drop = try #require(DropSetInsertion.insertDropSet(after: only))

        #expect(entry.orderedSets.map(\.id) == [only.id, drop.id])
        #expect(drop.order == 1)
    }

    @Test("Multiple drop sets stack in the order they were added")
    func multipleDropSetsStackInOrder() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Leg Extension")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        let top = entry.addSet(weightKG: 60, reps: 10)
        let firstDrop = try #require(DropSetInsertion.insertDropSet(after: top, weightKG: 45, reps: 10))
        let secondDrop = try #require(DropSetInsertion.insertDropSet(after: firstDrop, weightKG: 30, reps: 10))

        #expect(entry.orderedSets.map(\.id) == [top.id, firstDrop.id, secondDrop.id])
        #expect(entry.orderedSets.map(\.order) == [0, 1, 2])
    }

    @Test("Drop sets still contribute to total volume")
    func dropSetsContributeToVolume() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Tricep Pushdown")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        let top = entry.addSet(weightKG: 30, reps: 10)
        top.complete()
        let drop = try #require(DropSetInsertion.insertDropSet(after: top, weightKG: 20, reps: 10))
        drop.complete()

        #expect(entry.totalVolumeKG == 30 * 10 + 20 * 10)
    }

    @Test("A parent detached from its exercise cannot receive a drop set")
    func detachedParentReturnsNil() throws {
        let set = SetEntry(order: 0, weightKG: 50, reps: 5)
        #expect(DropSetInsertion.insertDropSet(after: set) == nil)
    }
}
