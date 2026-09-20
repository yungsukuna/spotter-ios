import Foundation
import SwiftData
import Testing

@testable import Tally

@MainActor
@Suite("WorkoutStatsCalculator")
struct WorkoutStatsCalculatorTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TallySchema.makeContainer(inMemory: true))
    }

    /// Log one completed set for `exercise` inside a finished workout dated
    /// `daysAgo` days before `now`.
    @discardableResult
    private func logSession(
        exercise: Exercise,
        weightKG: Double,
        reps: Int,
        daysAgo: Double,
        now: Date,
        context: ModelContext,
        isWarmup: Bool = false
    ) -> Workout {
        let startedAt = now.addingTimeInterval(-daysAgo * 86400)
        let workout = Workout(startedAt: startedAt)
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet(weightKG: weightKG, reps: reps, isWarmup: isWarmup).complete()
        workout.finish(at: startedAt.addingTimeInterval(1800))
        return workout
    }

    @Test("Volume series has one point per session")
    func volumeSeriesHasOnePointPerSession() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let now = Date()

        logSession(exercise: exercise, weightKG: 100, reps: 5, daysAgo: 10, now: now, context: context)
        logSession(exercise: exercise, weightKG: 105, reps: 5, daysAgo: 3, now: now, context: context)

        let series = WorkoutStatsCalculator.volumeSeries(for: exercise, range: .allTime)

        #expect(series.count == 2)
        #expect(series.map(\.value) == [500, 525])
    }

    @Test("Date range excludes sessions outside the window")
    func dateRangeExcludesOldSessions() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        let now = Date()

        logSession(exercise: exercise, weightKG: 100, reps: 5, daysAgo: 200, now: now, context: context)
        logSession(exercise: exercise, weightKG: 110, reps: 5, daysAgo: 5, now: now, context: context)

        let recent = WorkoutStatsCalculator.volumeSeries(for: exercise, range: .oneMonth)
        let all = WorkoutStatsCalculator.volumeSeries(for: exercise, range: .allTime)

        #expect(recent.count == 1)
        #expect(all.count == 2)
    }

    @Test("Warm-ups are excluded from every series")
    func warmupsExcludedFromSeries() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Overhead Press")
        context.insert(exercise)
        let now = Date()

        logSession(
            exercise: exercise, weightKG: 20, reps: 10, daysAgo: 1, now: now,
            context: context, isWarmup: true
        )

        #expect(WorkoutStatsCalculator.volumeSeries(for: exercise).isEmpty)
        #expect(WorkoutStatsCalculator.heaviestWeightSeries(for: exercise).isEmpty)
        #expect(WorkoutStatsCalculator.oneRepMaxSeries(for: exercise).isEmpty)
    }

    @Test("Heaviest weight series tracks the top set per session")
    func heaviestWeightTracksTopSet() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Deadlift")
        context.insert(exercise)
        let now = Date()
        let startedAt = now.addingTimeInterval(-86400)
        let workout = Workout(startedAt: startedAt)
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet(weightKG: 140, reps: 3).complete()
        entry.addSet(weightKG: 150, reps: 1).complete()
        workout.finish(at: startedAt.addingTimeInterval(3600))

        let series = WorkoutStatsCalculator.heaviestWeightSeries(for: exercise)

        #expect(series.count == 1)
        #expect(series.first?.value == 150)
    }

    @Test("Rep records match StrengthMath across the exercise's full history")
    func repRecordsMatchAcrossHistory() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Barbell Row")
        context.insert(exercise)
        let now = Date()

        logSession(exercise: exercise, weightKG: 80, reps: 5, daysAgo: 20, now: now, context: context)
        logSession(exercise: exercise, weightKG: 85, reps: 5, daysAgo: 10, now: now, context: context)
        logSession(exercise: exercise, weightKG: 60, reps: 10, daysAgo: 5, now: now, context: context)

        let records = WorkoutStatsCalculator.repRecords(for: exercise)

        #expect(records.count == 2)
        #expect(records.first { $0.reps == 5 }?.weightKG == 85)
        #expect(records.first { $0.reps == 10 }?.weightKG == 60)
    }

    @Test("An exercise with no history produces empty series")
    func noHistoryProducesEmptySeries() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "New Movement")
        context.insert(exercise)

        #expect(WorkoutStatsCalculator.volumeSeries(for: exercise).isEmpty)
        #expect(WorkoutStatsCalculator.oneRepMaxSeries(for: exercise).isEmpty)
        #expect(WorkoutStatsCalculator.repRecords(for: exercise).isEmpty)
    }
}
