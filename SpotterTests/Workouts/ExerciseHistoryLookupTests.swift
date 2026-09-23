import Foundation
import SwiftData
import Testing

@testable import Spotter

@MainActor
@Suite("ExerciseHistoryLookup")
struct ExerciseHistoryLookupTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @Test("Past sessions are sorted most recent first")
    func pastSessionsSortedMostRecentFirst() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)

        let older = Workout(startedAt: Date(timeIntervalSince1970: 0))
        context.insert(older)
        older.addExercise(exercise).addSet(weightKG: 60, reps: 8).complete()
        older.finish(at: Date(timeIntervalSince1970: 3600))

        let newer = Workout(startedAt: Date(timeIntervalSince1970: 86400))
        context.insert(newer)
        newer.addExercise(exercise).addSet(weightKG: 65, reps: 6).complete()
        newer.finish(at: Date(timeIntervalSince1970: 90000))

        let sessions = ExerciseHistoryLookup.pastSessions(for: exercise)

        #expect(sessions.count == 2)
        #expect(sessions.first?.id == newer.id)
    }

    @Test("An unfinished workout never appears in history")
    func unfinishedWorkoutNeverAppears() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        let inProgress = Workout()
        context.insert(inProgress)
        inProgress.addExercise(exercise).addSet(weightKG: 100, reps: 5).complete()

        #expect(ExerciseHistoryLookup.pastSessions(for: exercise).isEmpty)
    }

    @Test("The currently-edited workout is excluded by id")
    func currentWorkoutExcludedById() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Deadlift")
        context.insert(exercise)

        let finished = Workout()
        context.insert(finished)
        finished.addExercise(exercise).addSet(weightKG: 120, reps: 5).complete()
        finished.finish()

        let sessions = ExerciseHistoryLookup.pastSessions(for: exercise, excludingWorkoutID: finished.id)
        #expect(sessions.isEmpty)
    }

    @Test("A session with no completed sets does not appear")
    func sessionWithNoCompletedSetsOmitted() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Leg Press")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        workout.addExercise(exercise).addSet(weightKG: 100, reps: 10) // never completed
        workout.finish()

        #expect(ExerciseHistoryLookup.pastSessions(for: exercise).isEmpty)
    }
}
