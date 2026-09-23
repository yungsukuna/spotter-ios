import Foundation
import SwiftData
import Testing

@testable import Spotter

@MainActor
@Suite("PreviousPerformance")
struct PreviousPerformanceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @Test("A first-ever session has no placeholders")
    func firstEverSessionHasNoPlaceholders() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet()

        #expect(PreviousPerformance.placeholders(for: exercise, excludingWorkout: workout).isEmpty)
        #expect(PreviousPerformance.mostRecentEntry(for: exercise, excludingWorkout: workout) == nil)
        #expect(PreviousPerformance.placeholder(atIndex: 0, in: entry.orderedSets, for: exercise, excludingWorkout: workout) == nil)
    }

    @Test("Placeholders come from the most recent finished session")
    func placeholdersComeFromMostRecentSession() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)

        let older = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(older)
        older.addExercise(exercise).addSet(weightKG: 80, reps: 5).complete()
        older.finish(at: Date(timeIntervalSince1970: 3600))

        let newer = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(newer)
        newer.addExercise(exercise).addSet(weightKG: 90, reps: 5).complete()
        newer.finish(at: Date(timeIntervalSince1970: 90000))

        let placeholders = PreviousPerformance.placeholders(for: exercise)
        #expect(placeholders.count == 1)
        #expect(placeholders.first?.weightKG == 90)
    }

    @Test("An unfinished session is never used as history")
    func unfinishedSessionIsNotHistory() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Deadlift")
        context.insert(exercise)

        let finished = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(finished)
        finished.addExercise(exercise).addSet(weightKG: 100, reps: 5).complete()
        finished.finish(at: Date(timeIntervalSince1970: 3600))

        let inProgress = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(inProgress)
        let currentEntry = inProgress.addExercise(exercise)
        currentEntry.addSet()

        let placeholder = PreviousPerformance.placeholder(
            atIndex: 0,
            in: currentEntry.orderedSets,
            for: exercise,
            excludingWorkout: inProgress
        )
        #expect(placeholder?.weightKG == 100)
    }

    @Test("A working set beyond the previous session's working-set count has no placeholder")
    func extraWorkingSetHasNoPlaceholder() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Overhead Press")
        context.insert(exercise)

        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let previousEntry = previous.addExercise(exercise)
        previousEntry.addSet(weightKG: 40, reps: 8).complete()
        previousEntry.addSet(weightKG: 40, reps: 7).complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        let current = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(current)
        let currentEntry = current.addExercise(exercise)
        currentEntry.addSet()
        currentEntry.addSet()
        currentEntry.addSet() // a third set that didn't exist last time

        let ordered = currentEntry.orderedSets
        #expect(PreviousPerformance.placeholder(atIndex: 0, in: ordered, for: exercise, excludingWorkout: current)?.weightKG == 40)
        #expect(PreviousPerformance.placeholder(atIndex: 1, in: ordered, for: exercise, excludingWorkout: current)?.reps == 7)
        #expect(PreviousPerformance.placeholder(atIndex: 2, in: ordered, for: exercise, excludingWorkout: current) == nil)
    }

    @Test("Matching is by kind, not by completion state")
    func matchingIsByKindNotCompletionState() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Lat Pulldown")
        context.insert(exercise)

        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let previousEntry = previous.addExercise(exercise)
        previousEntry.addSet(weightKG: 50, reps: 10, isWarmup: true).complete()
        previousEntry.addSet(weightKG: 60, reps: 8).complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        let current = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(current)
        let currentEntry = current.addExercise(exercise)
        currentEntry.addSet(isWarmup: true) // uncompleted, unlike the previous session's
        currentEntry.addSet()

        let ordered = currentEntry.orderedSets
        let warmupPlaceholder = PreviousPerformance.placeholder(atIndex: 0, in: ordered, for: exercise, excludingWorkout: current)
        let workingPlaceholder = PreviousPerformance.placeholder(atIndex: 1, in: ordered, for: exercise, excludingWorkout: current)
        #expect(warmupPlaceholder?.isWarmup == true)
        #expect(warmupPlaceholder?.weightKG == 50)
        #expect(workingPlaceholder?.weightKG == 60)
    }

    @Test("Inserting warm-ups doesn't shift the working-set placeholders")
    func warmupsDontShiftWorkingSetPlaceholders() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Front Squat")
        context.insert(exercise)

        // A previous session with no warm-ups, three working sets.
        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let previousEntry = previous.addExercise(exercise)
        previousEntry.addSet(weightKG: 80, reps: 5).complete()
        previousEntry.addSet(weightKG: 85, reps: 5).complete()
        previousEntry.addSet(weightKG: 85, reps: 4).complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        // This session adds two warm-ups ahead of the same three working sets.
        let current = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(current)
        let currentEntry = current.addExercise(exercise)
        currentEntry.addSet(isWarmup: true)
        currentEntry.addSet(isWarmup: true)
        currentEntry.addSet() // working set 1
        currentEntry.addSet() // working set 2
        currentEntry.addSet() // working set 3

        let ordered = currentEntry.orderedSets

        // Positional matching would have offered the previous session's
        // *first* working set (80/5) here, since this is raw index 2. Kind
        // matching still finds working set 1 correctly.
        let firstWorking = PreviousPerformance.placeholder(atIndex: 2, in: ordered, for: exercise, excludingWorkout: current)
        #expect(firstWorking?.weightKG == 80)
        #expect(firstWorking?.reps == 5)

        let secondWorking = PreviousPerformance.placeholder(atIndex: 3, in: ordered, for: exercise, excludingWorkout: current)
        #expect(secondWorking?.weightKG == 85)
        #expect(secondWorking?.reps == 5)

        let thirdWorking = PreviousPerformance.placeholder(atIndex: 4, in: ordered, for: exercise, excludingWorkout: current)
        #expect(thirdWorking?.weightKG == 85)
        #expect(thirdWorking?.reps == 4)

        // Neither warm-up has a match, since the previous session had none.
        #expect(PreviousPerformance.placeholder(atIndex: 0, in: ordered, for: exercise, excludingWorkout: current) == nil)
        #expect(PreviousPerformance.placeholder(atIndex: 1, in: ordered, for: exercise, excludingWorkout: current) == nil)
    }

    @Test("A drop set matches its parent working set's drop sets, in order")
    func dropSetsMatchParentsDropSetsInOrder() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Lateral Raise")
        context.insert(exercise)

        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let previousEntry = previous.addExercise(exercise)
        let previousTop = previousEntry.addSet(weightKG: 14, reps: 12)
        previousTop.complete()
        let previousDrop = DropSetInsertion.insertDropSet(after: previousTop, weightKG: 10, reps: 10)
        previousDrop?.complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        let current = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(current)
        let currentEntry = current.addExercise(exercise)
        let currentTop = currentEntry.addSet()
        let currentDrop = DropSetInsertion.insertDropSet(after: currentTop)
        _ = currentDrop

        let ordered = currentEntry.orderedSets
        let dropPlaceholder = PreviousPerformance.placeholder(atIndex: 1, in: ordered, for: exercise, excludingWorkout: current)
        #expect(dropPlaceholder?.isDropSet == true)
        #expect(dropPlaceholder?.weightKG == 10)
        #expect(dropPlaceholder?.reps == 10)
    }
}
