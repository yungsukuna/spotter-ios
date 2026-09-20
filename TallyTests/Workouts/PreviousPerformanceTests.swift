import Foundation
import SwiftData
import Testing

@testable import Tally

@MainActor
@Suite("PreviousPerformance")
struct PreviousPerformanceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TallySchema.makeContainer(inMemory: true))
    }

    @Test("A first-ever session has no placeholders")
    func firstEverSessionHasNoPlaceholders() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        workout.addExercise(exercise)

        #expect(PreviousPerformance.placeholders(for: exercise, excludingWorkout: workout).isEmpty)
        #expect(PreviousPerformance.mostRecentEntry(for: exercise, excludingWorkout: workout) == nil)
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

        let placeholder = PreviousPerformance.placeholder(atIndex: 0, for: exercise, excludingWorkout: inProgress)
        #expect(placeholder?.weightKG == 100)
    }

    @Test("A set index beyond the previous session's set count has no placeholder")
    func extraSetHasNoPlaceholder() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Overhead Press")
        context.insert(exercise)

        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let previousEntry = previous.addExercise(exercise)
        previousEntry.addSet(weightKG: 40, reps: 8).complete()
        previousEntry.addSet(weightKG: 40, reps: 7).complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        // This session has a third set that didn't exist last time.
        #expect(PreviousPerformance.placeholder(atIndex: 0, for: exercise)?.weightKG == 40)
        #expect(PreviousPerformance.placeholder(atIndex: 1, for: exercise)?.reps == 7)
        #expect(PreviousPerformance.placeholder(atIndex: 2, for: exercise) == nil)
    }

    @Test("Matching is positional, not by completion state")
    func matchingIsPositional() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Lat Pulldown")
        context.insert(exercise)

        let previous = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(previous)
        let entry = previous.addExercise(exercise)
        entry.addSet(weightKG: 50, reps: 10, isWarmup: true).complete()
        entry.addSet(weightKG: 60, reps: 8).complete()
        previous.finish(at: Date(timeIntervalSince1970: 3600))

        let placeholders = PreviousPerformance.placeholders(for: exercise)
        #expect(placeholders.count == 2)
        #expect(placeholders[0].isWarmup)
        #expect(placeholders[1].weightKG == 60)
    }
}
