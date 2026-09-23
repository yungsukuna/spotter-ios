import Foundation
import SwiftData
import Testing

@testable import Tally

/// These exercise the SwiftData layer against an in-memory store.
///
/// The schema tests earn their place: a `@Model` type missing from
/// `TallySchema.models`, or a relationship whose inverse does not line up,
/// compiles perfectly well and only fails at runtime on first insert. Standing
/// the container up in CI turns that into a test failure instead of a crash on
/// someone's phone.
@MainActor
@Suite("Persistence")
struct PersistenceTests {

    private func makeContext() throws -> ModelContext {
        let container = try TallySchema.makeContainer(inMemory: true)
        return ModelContext(container)
    }

    @Test("The schema builds and every model can be inserted")
    func schemaAcceptsEveryModel() throws {
        let context = try makeContext()

        let food = FoodItem(name: "Test Food", nutrientsPer100g: Nutrients(kcal: 100))
        context.insert(food)
        context.insert(
            DiaryEntry(
                logging: food,
                quantity: 1,
                serving: .hundredGrams,
                meal: .lunch
            )
        )
        context.insert(WaterEntry(volumeML: 250))

        let exercise = Exercise(name: "Test Lift", equipment: .barbell, muscleGroup: .chest)
        context.insert(exercise)

        let workout = Workout(name: "Test Session")
        context.insert(workout)
        let workoutExercise = workout.addExercise(exercise)
        workoutExercise.addSet(weightKG: 100, reps: 5)

        let routine = Routine(name: "Test Routine")
        context.insert(routine)
        routine.addExercise(exercise, targetSets: 3)

        context.insert(CardioEntry(exerciseName: "Running", durationSeconds: 1800))
        context.insert(BodyMeasurement(type: .bodyWeight, value: 82.5))
        context.insert(UserSettings())

        let savedMeal = SavedMeal(
            name: "Breakfast Combo",
            items: [
                SavedMealItem(
                    order: 0,
                    foodID: food.id,
                    foodName: food.name,
                    quantity: 1,
                    servingLabel: "100 g",
                    servingGramWeight: 100,
                    nutrientsSnapshot: Nutrients(kcal: 100, proteinG: 10)
                ),
                SavedMealItem(
                    order: 1,
                    foodID: nil,
                    foodName: "Mystery Item",
                    quantity: 1,
                    servingLabel: "1 serving",
                    servingGramWeight: 50,
                    nutrientsSnapshot: Nutrients(kcal: 80)
                ),
            ]
        )
        context.insert(savedMeal)

        // Saving is what actually validates the schema.
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<FoodItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 1)
    }

    @Test("SavedMeal items round-trip, preserving nil macros")
    func savedMealItemsRoundTrip() throws {
        let context = try makeContext()

        let meal = SavedMeal(
            name: "Post-Workout",
            items: [
                SavedMealItem(
                    order: 1,
                    foodName: "Protein Shake",
                    quantity: 1,
                    servingLabel: "1 scoop",
                    servingGramWeight: 30,
                    // No macros known — must stay nil, not become 0, through
                    // the SQLite-backed round trip.
                    nutrientsSnapshot: Nutrients(kcal: 120)
                ),
                SavedMealItem(
                    order: 0,
                    foodName: "Banana",
                    quantity: 1,
                    servingLabel: "1 medium",
                    servingGramWeight: 118,
                    nutrientsSnapshot: Nutrients(kcal: 105, proteinG: 1.3, carbsG: 27, fatG: 0.4)
                ),
            ]
        )
        context.insert(meal)
        try context.save()

        let refetched = try #require(try context.fetch(FetchDescriptor<SavedMeal>()).first)

        // orderedItems must read back in `order`, not insertion order.
        #expect(refetched.orderedItems.map(\.foodName) == ["Banana", "Protein Shake"])

        let shake = try #require(refetched.orderedItems.first { $0.foodName == "Protein Shake" })
        #expect(shake.nutrientsSnapshot.kcal == 120)
        #expect(shake.nutrientsSnapshot.proteinG == nil)
        #expect(shake.nutrientsSnapshot.carbsG == nil)
        #expect(shake.nutrientsSnapshot.fatG == nil)

        #expect(refetched.totalNutrients.kcal == 225)
        // Protein is known on only one item; totalling still treats the
        // other's nil as "no data" rather than corrupting the sum, per
        // `Nutrients.+`.
        #expect(refetched.totalNutrients.proteinG == 1.3)
    }

    @Test("Exercise.cardioEntries links when a CardioEntry references it")
    func cardioEntriesLinkToExercise() throws {
        let context = try makeContext()

        let exercise = Exercise(name: "Treadmill Run", isCardio: true)
        context.insert(exercise)
        let entry = CardioEntry(exerciseName: "Treadmill Run", durationSeconds: 1200, exercise: exercise)
        context.insert(entry)
        try context.save()

        let refetched = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(refetched.cardioEntries.map(\.id) == [entry.id])

        // Deleting the exercise must not delete the cardio history — the
        // relationship is nullify, matching workoutEntries.
        context.delete(exercise)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<CardioEntry>()) == 1)
        let survivor = try #require(try context.fetch(FetchDescriptor<CardioEntry>()).first)
        #expect(survivor.exercise == nil)
    }

    @Test("Settings are a singleton, created on first access")
    func settingsSingleton() throws {
        let context = try makeContext()

        let first = UserSettings.current(in: context)
        first.dailyKcalGoal = 2600
        try context.save()

        let second = UserSettings.current(in: context)

        #expect(second.dailyKcalGoal == 2600)
        #expect(try context.fetchCount(FetchDescriptor<UserSettings>()) == 1)
    }

    @Test("Seeding the exercise library is idempotent")
    func seedingIsIdempotent() throws {
        let context = try makeContext()

        let firstRun = ExerciseLibrary.seedIfNeeded(in: context)
        #expect(firstRun == ExerciseLibrary.seeds.count)

        // Running again on an already-seeded store must add nothing, because
        // it happens on every launch.
        let secondRun = ExerciseLibrary.seedIfNeeded(in: context)
        #expect(secondRun == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == ExerciseLibrary.seeds.count)
    }

    @Test("Seeding leaves custom exercises alone")
    func seedingPreservesCustomExercises() throws {
        let context = try makeContext()
        context.insert(Exercise(name: "My Weird Machine", isCustom: true))
        try context.save()

        ExerciseLibrary.seedIfNeeded(in: context)

        let custom = try context.fetch(
            FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom })
        )
        #expect(custom.count == 1)
    }

    @Test("Seed names are unique")
    func seedNamesAreUnique() {
        // Seeding matches on lowercased name, so a duplicate in the list would
        // silently drop one entry.
        let names = ExerciseLibrary.seeds.map { $0.name.lowercased() }
        #expect(names.count == Set(names).count)
    }

    @Test("Deleting a food keeps its diary history")
    func deletingFoodPreservesHistory() throws {
        let context = try makeContext()

        let food = FoodItem(name: "Doomed Food", nutrientsPer100g: Nutrients(kcal: 200))
        context.insert(food)
        let entry = DiaryEntry(
            logging: food,
            quantity: 1,
            serving: .hundredGrams,
            meal: .dinner
        )
        context.insert(entry)
        try context.save()

        context.delete(food)
        try context.save()

        // The entry survives with its snapshot intact — this is the whole
        // reason the snapshot exists.
        let entries = try context.fetch(FetchDescriptor<DiaryEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.foodName == "Doomed Food")
        #expect(entries.first?.nutrients.kcal == 200)
        #expect(entries.first?.food == nil)
    }

    @Test("Deleting a workout cascades to its sets")
    func deletingWorkoutCascades() throws {
        let context = try makeContext()

        let exercise = Exercise(name: "Bench")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet(weightKG: 100, reps: 5)
        entry.addSet(weightKG: 100, reps: 5)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 2)

        context.delete(workout)
        try context.save()

        // Sets have no meaning without their workout, so they go too.
        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 0)
        // The exercise definition itself must survive.
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test("Deleting an exercise keeps the training history")
    func deletingExercisePreservesHistory() throws {
        let context = try makeContext()

        let exercise = Exercise(name: "Obsolete Machine")
        context.insert(exercise)
        let workout = Workout()
        context.insert(workout)
        let entry = workout.addExercise(exercise)
        entry.addSet(weightKG: 50, reps: 10)
        try context.save()

        context.delete(exercise)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<SetEntry>()) == 1)
        let entries = try context.fetch(FetchDescriptor<WorkoutExercise>())
        #expect(entries.first?.displayName == "Deleted exercise")
    }

    @Test("Ordering survives a save and refetch")
    func orderingIsStable() throws {
        let context = try makeContext()

        let names = ["First", "Second", "Third"]
        let workout = Workout()
        context.insert(workout)
        for name in names {
            let exercise = Exercise(name: name)
            context.insert(exercise)
            workout.addExercise(exercise)
        }
        try context.save()

        // SwiftData relationship arrays are unordered; `orderedExercises` is
        // what makes the sequence deterministic.
        let refetched = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(refetched.orderedExercises.map(\.displayName) == names)
    }

    @Test("Starting a routine builds an empty session of the right shape")
    func routineMakesWorkout() throws {
        let context = try makeContext()

        let routine = Routine(name: "Push Day")
        context.insert(routine)
        for name in ["Bench Press", "Overhead Press"] {
            let exercise = Exercise(name: name)
            context.insert(exercise)
            routine.addExercise(exercise, targetSets: 3)
        }
        try context.save()

        let workout = routine.makeWorkout()
        context.insert(workout)
        try context.save()

        #expect(workout.name == "Push Day")
        #expect(workout.orderedExercises.count == 2)
        // Three empty sets per exercise, none completed — the logging screen
        // fills their placeholders from the last session.
        #expect(workout.orderedExercises.allSatisfy { $0.orderedSets.count == 3 })
        #expect(workout.completedSetCount == 0)
        #expect(workout.sourceRoutine?.id == routine.id)
    }

    @Test("Deleting a routine keeps the sessions performed from it")
    func deletingRoutinePreservesWorkouts() throws {
        let context = try makeContext()

        let routine = Routine(name: "Leg Day")
        context.insert(routine)
        let workout = routine.makeWorkout()
        context.insert(workout)
        try context.save()

        context.delete(routine)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Workout>()).first?.sourceRoutine == nil)
    }
}
