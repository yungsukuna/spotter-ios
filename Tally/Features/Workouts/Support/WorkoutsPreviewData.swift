import Foundation
import SwiftData

/// Seed data for Workouts feature previews.
///
/// Not used by the app itself — every `#Preview` in this feature calls into
/// here so previews show realistic sessions and history instead of an empty
/// screen, per the house style described in `CLAUDE.md`.
enum WorkoutsPreviewData {

    /// An in-progress "Push Day" with one finished session behind it, so the
    /// active logging screen shows real placeholder text.
    @discardableResult
    static func makeInProgressWorkout(in context: ModelContext) -> Workout {
        let bench = Exercise(name: "Barbell Bench Press", equipment: .barbell, muscleGroup: .chest)
        let row = Exercise(name: "Seated Cable Row", equipment: .cable, muscleGroup: .back)
        context.insert(bench)
        context.insert(row)

        let previous = Workout(name: "Push Day", startedAt: .now.addingTimeInterval(-7 * 86400))
        context.insert(previous)
        let previousEntry = previous.addExercise(bench)
        for (weight, reps) in [(60.0, 8), (65.0, 6), (65.0, 5)] {
            previousEntry.addSet(weightKG: weight, reps: reps).complete()
        }
        previous.finish(at: previous.startedAt.addingTimeInterval(3000))

        let workout = Workout(name: "Push Day")
        context.insert(workout)
        let benchEntry = workout.addExercise(bench)
        benchEntry.addSet()
        benchEntry.addSet()
        if let firstSet = benchEntry.orderedSets.first {
            firstSet.weightKG = 65
            firstSet.reps = 8
            firstSet.complete()
        }

        let rowEntry = workout.addExercise(row)
        rowEntry.addSet(weightKG: 50, reps: 10)

        try? context.save()
        return workout
    }

    /// A single finished "Leg Day", for read-only detail previews.
    @discardableResult
    static func makeFinishedWorkout(in context: ModelContext) -> Workout {
        let squat = Exercise(name: "Back Squat", equipment: .barbell, muscleGroup: .quads)
        context.insert(squat)
        let workout = Workout(name: "Leg Day", startedAt: .now.addingTimeInterval(-2 * 86400))
        context.insert(workout)
        let entry = workout.addExercise(squat)
        for (weight, reps) in [(100.0, 5), (110.0, 5), (110.0, 4)] {
            entry.addSet(weightKG: weight, reps: reps).complete()
        }
        workout.finish(at: workout.startedAt.addingTimeInterval(2700))
        try? context.save()
        return workout
    }

    /// An exercise with several finished sessions behind it, trending
    /// upward, for the history sheet and stats charts.
    @discardableResult
    static func seedHistory(in context: ModelContext) -> Exercise {
        let deadlift = Exercise(name: "Deadlift", equipment: .barbell, muscleGroup: .back)
        context.insert(deadlift)

        let sessions: [(daysAgo: Double, sets: [(Double, Int)])] = [
            (28, [(120, 5), (130, 5), (130, 4)]),
            (21, [(125, 5), (135, 5), (135, 5)]),
            (14, [(130, 5), (140, 4), (140, 3)]),
            (7, [(135, 5), (145, 3), (145, 3)]),
        ]

        for session in sessions {
            let workout = Workout(name: "Pull Day", startedAt: .now.addingTimeInterval(-session.daysAgo * 86400))
            context.insert(workout)
            let entry = workout.addExercise(deadlift)
            for (weight, reps) in session.sets {
                entry.addSet(weightKG: weight, reps: reps).complete()
            }
            workout.finish(at: workout.startedAt.addingTimeInterval(3600))
        }

        try? context.save()
        return deadlift
    }

    /// A two-exercise "Leg Day" routine.
    @discardableResult
    static func seedRoutine(in context: ModelContext) -> Routine {
        let squat = Exercise(name: "Front Squat", equipment: .barbell, muscleGroup: .quads)
        let lunge = Exercise(name: "Walking Lunge", equipment: .dumbbell, muscleGroup: .quads)
        context.insert(squat)
        context.insert(lunge)

        let routine = Routine(name: "Leg Day")
        context.insert(routine)
        routine.addExercise(squat, targetSets: 4)
        routine.addExercise(lunge, targetSets: 3)

        try? context.save()
        return routine
    }

    /// A bit of everything, for `WorkoutsHomeView`'s own preview.
    static func seedHomeScreen(in context: ModelContext) {
        seedRoutine(in: context)
        makeFinishedWorkout(in: context)
    }
}
