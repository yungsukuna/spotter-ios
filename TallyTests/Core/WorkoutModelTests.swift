import Foundation
import SwiftData
import Testing

@testable import Tally

/// Behaviour of the workout object graph — ordering, superset grouping, and
/// which sets count toward statistics.
@MainActor
@Suite("Workout model")
struct WorkoutModelTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TallySchema.makeContainer(inMemory: true))
    }

    @Test("Warm-up sets are excluded from volume")
    func warmupsExcludedFromVolume() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        // A warm-up is logged but is not working volume.
        let warmup = entry.addSet(weightKG: 60, reps: 10, isWarmup: true)
        warmup.complete()
        let working = entry.addSet(weightKG: 100, reps: 5)
        working.complete()

        #expect(entry.totalVolumeKG == 500)
        #expect(entry.completedSets.count == 1)
    }

    @Test("Uncompleted sets are excluded from volume")
    func uncompletedExcludedFromVolume() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Squat")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        // Sets exist on screen before they are performed; only ticked-off work
        // counts.
        entry.addSet(weightKG: 100, reps: 5)
        let done = entry.addSet(weightKG: 100, reps: 5)
        done.complete()

        #expect(workout.totalVolumeKG == 500)
        #expect(workout.completedSetCount == 1)
    }

    @Test("Drop sets still count toward volume")
    func dropSetsCountTowardVolume() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Lateral Raise")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        let top = entry.addSet(weightKG: 14, reps: 12)
        top.complete()
        let drop = entry.addSet(weightKG: 8, reps: 10)
        drop.isDropSet = true
        drop.complete()

        // A drop set is real work; it is rendered differently, not discounted.
        #expect(entry.totalVolumeKG == 14 * 12 + 8 * 10)
        #expect(entry.completedSets.count == 2)
    }

    @Test("Removing a set closes the gap in the ordering")
    func removingSetRenumbers() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Row")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        entry.addSet(weightKG: 60, reps: 10)
        let middle = entry.addSet(weightKG: 65, reps: 8)
        entry.addSet(weightKG: 70, reps: 6)

        entry.removeSet(middle)

        #expect(entry.orderedSets.map(\.order) == [0, 1])
        #expect(entry.orderedSets.map(\.weightKG) == [60, 70])
    }

    @Test("Removing an exercise closes the gap in the ordering")
    func removingExerciseRenumbers() throws {
        let context = try makeContext()
        let workout = Workout()
        context.insert(workout)

        var entries: [WorkoutExercise] = []
        for name in ["A", "B", "C"] {
            let exercise = Exercise(name: name)
            context.insert(exercise)
            entries.append(workout.addExercise(exercise))
        }

        workout.removeExercise(entries[1])

        #expect(workout.orderedExercises.map(\.order) == [0, 1])
        #expect(workout.orderedExercises.map(\.displayName) == ["A", "C"])
    }

    @Test("Reordering reassigns the order indices")
    func reorderingReassignsIndices() throws {
        let context = try makeContext()
        let workout = Workout()
        context.insert(workout)

        var entries: [WorkoutExercise] = []
        for name in ["A", "B", "C"] {
            let exercise = Exercise(name: name)
            context.insert(exercise)
            entries.append(workout.addExercise(exercise))
        }

        workout.reorderExercises(to: [entries[2], entries[0], entries[1]])

        #expect(workout.orderedExercises.map(\.displayName) == ["C", "A", "B"])
    }

    @Test("Best estimated one-rep max picks the strongest set")
    func bestEstimatedOneRepMax() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Bench Press")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)

        // 100×5 (Epley 116.7) beats 110×1 (Epley 113.7) despite the lighter bar.
        for (weight, reps) in [(100.0, 5), (110.0, 1)] {
            let set = entry.addSet(weightKG: weight, reps: reps)
            set.complete()
        }

        let best = try #require(entry.bestEstimatedOneRepMax(formula: .epley))
        #expect(abs(best - 116.6667) < 0.001)
    }

    @Test("A bodyweight-only exercise has no estimable one-rep max")
    func bodyweightHasNoOneRepMax() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Push-Up", equipment: .bodyweight)
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet(weightKG: 0, reps: 25).complete()

        #expect(entry.bestEstimatedOneRepMax() == nil)
        #expect(entry.topSetWeightKG == 0)
    }

    @Test("A workout is in progress until it is finished")
    func workoutLifecycle() throws {
        let context = try makeContext()
        let workout = Workout(startedAt: Date(timeIntervalSince1970: 1000))
        context.insert(workout)

        #expect(workout.isInProgress)
        #expect(!workout.hasLoggedAnything)

        workout.finish(at: Date(timeIntervalSince1970: 4600))

        #expect(!workout.isInProgress)
        #expect(workout.duration == 3600)
    }

    @Test("A workout counts as having content once a set is completed")
    func hasLoggedAnything() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Curl")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        let set = entry.addSet(weightKG: 20, reps: 12)

        // An exercise with empty rows is not yet worth warning about on discard.
        #expect(!workout.hasLoggedAnything)
        set.complete()
        #expect(workout.hasLoggedAnything)
    }

    @Test("Completing a set stamps the time; uncompleting clears it")
    func completionStampsTime() throws {
        let context = try makeContext()
        let exercise = Exercise(name: "Press")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let set = workout.addExercise(exercise).addSet(weightKG: 40, reps: 8)

        let when = Date(timeIntervalSince1970: 5000)
        set.complete(at: when)
        // The completion timestamp is what the rest timer counts from.
        #expect(set.completedAt == when)

        set.uncomplete()
        #expect(set.completedAt == nil)
        #expect(!set.isCompleted)
    }

    @Test("Superset membership is reported from the group")
    func supersetMembership() throws {
        let context = try makeContext()
        let workout = Workout()
        context.insert(workout)

        var entries: [WorkoutExercise] = []
        for name in ["A", "B", "C"] {
            let exercise = Exercise(name: name)
            context.insert(exercise)
            entries.append(workout.addExercise(exercise))
        }

        entries[0].supersetGroup = 1
        entries[1].supersetGroup = 1

        #expect(entries[0].isInSuperset)
        #expect(entries[1].isInSuperset)
        #expect(!entries[2].isInSuperset)

        let grouped = workout.orderedExercises.filter { $0.supersetGroup == 1 }
        #expect(grouped.count == 2)
        // Superset members must be adjacent so the bracket draws as one run.
        #expect(grouped.map(\.order) == [0, 1])
    }

    @Test("A diary entry's day key follows an edited timestamp")
    func editingTimestampUpdatesDayKey() throws {
        let context = try makeContext()
        let food = FoodItem(name: "Toast", nutrientsPer100g: Nutrients(kcal: 250))
        context.insert(food)
        let entry = DiaryEntry(
            logging: food,
            quantity: 1,
            serving: .hundredGrams,
            meal: .breakfast,
            at: Date(timeIntervalSince1970: 1_758_240_000)
        )
        context.insert(entry)

        let original = entry.dayKey
        // Moving an entry to a different day must move it in the diary too —
        // the key is not derived at read time, so it has to be maintained.
        entry.updateLoggedAt(Date(timeIntervalSince1970: 1_758_240_000 + 86_400 * 3))

        #expect(entry.dayKey != original)
    }

    @Test("Portion description reads naturally")
    func portionDescription() throws {
        let context = try makeContext()
        let food = FoodItem(
            name: "Bread",
            nutrientsPer100g: Nutrients(kcal: 250),
            servings: [ServingSize(label: "1 slice", gramWeight: 40)]
        )
        context.insert(food)
        let serving = food.defaultServing

        let single = DiaryEntry(logging: food, quantity: 1, serving: serving, meal: .breakfast)
        // "1 × 1 slice" would be clumsy.
        #expect(single.portionDescription == "1 slice")

        let double = DiaryEntry(logging: food, quantity: 2.5, serving: serving, meal: .breakfast)
        #expect(double.portionDescription == "2.5 × 1 slice")
    }

    @Test("Logged nutrition scales by quantity and serving weight")
    func loggedNutritionScales() throws {
        let context = try makeContext()
        let food = FoodItem(
            name: "Bread",
            nutrientsPer100g: Nutrients(kcal: 250, proteinG: 9),
            servings: [ServingSize(label: "1 slice", gramWeight: 40)]
        )
        context.insert(food)

        let entry = DiaryEntry(
            logging: food,
            quantity: 2,
            serving: food.defaultServing,
            meal: .breakfast
        )

        // 2 slices × 40 g = 80 g → 200 kcal, 7.2 g protein.
        #expect(entry.totalGrams == 80)
        #expect(entry.nutrients.kcal == 200)
        #expect(abs((entry.nutrients.proteinG ?? 0) - 7.2) < 0.0001)
    }

    @Test("Every food offers a 100 g serving")
    func normalisedServingsAlwaysIncludeHundredGrams() {
        let food = FoodItem(
            name: "Odd Product",
            servings: [ServingSize(label: "1 sachet", gramWeight: 17)]
        )
        // The user can always fall back to weighing, whatever the source said.
        #expect(food.normalisedServings.contains { $0.gramWeight == 100 })
        // But the source's own serving stays the default.
        #expect(food.defaultServing.label == "1 sachet")
    }
}
