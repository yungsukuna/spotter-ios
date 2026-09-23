import Foundation
import SwiftData
import Testing

@testable import Spotter

@MainActor
@Suite("SupersetGrouping")
struct SupersetGroupingTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    private func makeWorkout(exerciseNames: [String], context: ModelContext) -> (Workout, [WorkoutExercise]) {
        let workout = Workout()
        context.insert(workout)
        var entries: [WorkoutExercise] = []
        for name in exerciseNames {
            let exercise = Exercise(name: name)
            context.insert(exercise)
            entries.append(workout.addExercise(exercise))
        }
        return (workout, entries)
    }

    @Test("Grouping two adjacent exercises assigns them the same group")
    func groupingAdjacentExercises() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B", "C"], context: context)

        let didGroup = SupersetGrouping.groupWithNext(entries[0], in: workout)

        #expect(didGroup)
        #expect(entries[0].supersetGroup != nil)
        #expect(entries[0].supersetGroup == entries[1].supersetGroup)
        #expect(entries[2].supersetGroup == nil)
    }

    @Test("Grouping the last exercise with 'next' is a no-op")
    func groupingLastExerciseIsNoOp() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B"], context: context)

        let didGroup = SupersetGrouping.groupWithNext(entries[1], in: workout)

        #expect(!didGroup)
        #expect(entries[1].supersetGroup == nil)
    }

    @Test("Grouping a third exercise into an existing pair joins the same group")
    func groupingThirdExerciseJoinsExistingGroup() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B", "C"], context: context)

        SupersetGrouping.groupWithNext(entries[0], in: workout) // A + B
        SupersetGrouping.groupWithNext(entries[1], in: workout) // B (already grouped) + C

        let group = entries[0].supersetGroup
        #expect(group != nil)
        #expect(entries[1].supersetGroup == group)
        #expect(entries[2].supersetGroup == group)
    }

    @Test("Ungrouping one member leaves the others grouped")
    func ungroupingOneMemberLeavesOthers() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B", "C"], context: context)
        SupersetGrouping.groupWithNext(entries[0], in: workout)
        SupersetGrouping.groupWithNext(entries[1], in: workout)

        SupersetGrouping.ungroup(entries[0])

        #expect(entries[0].supersetGroup == nil)
        #expect(entries[1].supersetGroup != nil)
        #expect(entries[1].supersetGroup == entries[2].supersetGroup)
    }

    @Test("Bracket position reflects a run's edges")
    func bracketPositionReflectsRunEdges() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B", "C", "D"], context: context)
        SupersetGrouping.groupWithNext(entries[0], in: workout)
        SupersetGrouping.groupWithNext(entries[1], in: workout)

        #expect(SupersetGrouping.bracketPosition(for: entries[0], in: workout) == .first)
        #expect(SupersetGrouping.bracketPosition(for: entries[1], in: workout) == .middle)
        #expect(SupersetGrouping.bracketPosition(for: entries[2], in: workout) == .last)
        #expect(SupersetGrouping.bracketPosition(for: entries[3], in: workout) == .none)
    }

    @Test("A superset of one reports as a single bracket")
    func singleMemberGroupReportsAsSingle() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B"], context: context)
        entries[0].supersetGroup = 1

        #expect(SupersetGrouping.bracketPosition(for: entries[0], in: workout) == .single)
    }

    @Test("Adjacency holds for a contiguous run")
    func adjacencyHoldsForContiguousRun() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B", "C"], context: context)

        #expect(SupersetGrouping.isContiguous([entries[0], entries[1]], in: workout))
        #expect(SupersetGrouping.isContiguous(Array(entries[0...2]), in: workout))
    }

    @Test("Adjacency fails for a non-contiguous selection")
    func adjacencyFailsForNonContiguousSelection() throws {
        let context = try makeContext()
        let (workout, entries) = makeWorkout(exerciseNames: ["A", "B", "C"], context: context)

        #expect(!SupersetGrouping.isContiguous([entries[0], entries[2]], in: workout))
    }
}
