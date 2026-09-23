import Foundation
import SwiftData
import Testing

@testable import Tally

/// Exercises `BackupExporter` and `BackupImporter` together against real
/// in-memory SwiftData stores.
///
/// Dates go through `JSONEncoder.DateEncodingStrategy.iso8601`, which drops
/// sub-second precision, so date comparisons below use a 1-second tolerance
/// rather than exact equality.
@MainActor
@Suite("Backup round trip")
struct BackupRoundTripTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try TallySchema.makeContainer(inMemory: true))
    }

    private func closeEnough(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }

    // MARK: - Full round trip

    @Test("A full backup round-trips into an empty store, preserving nil macros and dayKey")
    func fullRoundTrip() throws {
        let source = try makeContext()

        let food = FoodItem(
            name: "Rolled Oats",
            barcode: "9900011122",
            nutrientsPer100g: Nutrients(kcal: 389, proteinG: 16.9, carbsG: 66.3, fatG: nil)
        )
        source.insert(food)

        let entry = DiaryEntry(
            logging: food,
            quantity: 0.5,
            serving: .hundredGrams,
            meal: .breakfast,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        source.insert(entry)
        let sourceDayKey = entry.dayKey

        let exercise = Exercise(name: "Cable Fly", equipment: .cable, muscleGroup: .chest, isCustom: true)
        source.insert(exercise)

        let workout = Workout(name: "Push Day", startedAt: Date(timeIntervalSince1970: 1_700_100_000))
        source.insert(workout)
        let workoutExercise = workout.addExercise(exercise)
        workoutExercise.addSet(weightKG: 20, reps: 12)

        let routine = Routine(name: "Push Routine")
        source.insert(routine)
        routine.addExercise(exercise, targetSets: 4)

        source.insert(CardioEntry(exerciseName: "Treadmill", durationSeconds: 900, distanceKM: 2.1))
        source.insert(BodyMeasurement(type: .bodyWeight, value: 81.4))
        source.insert(WaterEntry(volumeML: 400))

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
                    // No fat known on this item — must stay nil through the trip.
                    nutrientsSnapshot: Nutrients(kcal: 389, proteinG: 16.9, carbsG: 66.3, fatG: nil)
                ),
            ]
        )
        source.insert(savedMeal)

        let settings = UserSettings.current(in: source)
        settings.dailyKcalGoal = 2450
        settings.heightCM = 178

        try source.save()

        let backup = try BackupExporter.makeBackup(from: source)

        // Encoding/decoding through JSON is part of what's being tested, not
        // just the in-memory DTO translation.
        let data = try BackupCoding.makeEncoder().encode(backup)
        let decoded = try BackupCoding.makeDecoder().decode(TallyBackup.self, from: data)

        let destination = try makeContext()
        let report = try BackupImporter.performImport(decoded, into: destination)

        #expect(report.diaryEntries.toAdd == 1)
        #expect(report.exercises.toAdd == 1)
        #expect(report.foodItems.toAdd == 1)
        #expect(report.settingsCopied)

        #expect(try destination.fetchCount(FetchDescriptor<FoodItem>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<DiaryEntry>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<Workout>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<WorkoutExercise>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<SetEntry>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<Routine>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<RoutineExercise>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<CardioEntry>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<BodyMeasurement>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<WaterEntry>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<SavedMeal>()) == 1)

        let importedEntry = try #require(try destination.fetch(FetchDescriptor<DiaryEntry>()).first)
        #expect(importedEntry.dayKey == sourceDayKey)
        #expect(importedEntry.nutrients.fatG == nil)
        #expect(importedEntry.nutrients.kcal == entry.nutrients.kcal)
        #expect(closeEnough(importedEntry.loggedAt, entry.loggedAt))
        #expect(importedEntry.food?.id == food.id)

        let importedMeal = try #require(try destination.fetch(FetchDescriptor<SavedMeal>()).first)
        #expect(importedMeal.orderedItems.first?.nutrientsSnapshot.fatG == nil)
        #expect(importedMeal.orderedItems.first?.foodID == food.id)

        let importedSettings = try #require(try destination.fetch(FetchDescriptor<UserSettings>()).first)
        #expect(importedSettings.dailyKcalGoal == 2450)
        #expect(importedSettings.heightCM == 178)
        #expect(try destination.fetchCount(FetchDescriptor<UserSettings>()) == 1)
    }

    // MARK: - Idempotency

    @Test("Importing the same backup twice leaves counts unchanged")
    func importingTwiceIsIdempotent() throws {
        let source = try makeContext()
        let food = FoodItem(name: "Banana", nutrientsPer100g: Nutrients(kcal: 89))
        source.insert(food)
        source.insert(DiaryEntry(logging: food, quantity: 1, serving: .hundredGrams, meal: .snack))
        source.insert(WaterEntry(volumeML: 250))
        try source.save()

        let backup = try BackupExporter.makeBackup(from: source)

        let destination = try makeContext()
        let firstReport = try BackupImporter.performImport(backup, into: destination)
        #expect(firstReport.totalToAdd == 3) // food + diary entry + water entry

        let secondReport = try BackupImporter.performImport(backup, into: destination)
        #expect(secondReport.totalToAdd == 0)
        #expect(secondReport.totalToSkip == 3)

        #expect(try destination.fetchCount(FetchDescriptor<FoodItem>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<DiaryEntry>()) == 1)
        #expect(try destination.fetchCount(FetchDescriptor<WaterEntry>()) == 1)
    }

    // MARK: - Built-in exercise remapping

    @Test("Built-in exercises remap by name instead of duplicating the seeded library")
    func builtInExercisesRemapByName() throws {
        let source = try makeContext()
        ExerciseLibrary.seedIfNeeded(in: source)
        let sourceBench = try #require(
            try source.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Barbell Bench Press" })).first
        )

        let workout = Workout(name: "Chest Day")
        source.insert(workout)
        let workoutExercise = workout.addExercise(sourceBench)
        workoutExercise.addSet(weightKG: 100, reps: 5)
        try source.save()

        let backup = try BackupExporter.makeBackup(from: source)

        // The destination is pre-seeded, exactly like a real install: the
        // built-in library exists before any import happens, each with
        // fresh, unrelated UUIDs.
        let destination = try makeContext()
        ExerciseLibrary.seedIfNeeded(in: destination)
        let destinationBench = try #require(
            try destination.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Barbell Bench Press" })).first
        )
        #expect(destinationBench.id != sourceBench.id)

        let report = try BackupImporter.performImport(backup, into: destination)

        // Every seeded exercise already existed by name, so nothing new is
        // inserted, and the workout must still link to it.
        #expect(report.exercises.toAdd == 0)
        #expect(try destination.fetchCount(FetchDescriptor<Exercise>()) == ExerciseLibrary.seeds.count)

        let importedWorkoutExercise = try #require(try destination.fetch(FetchDescriptor<WorkoutExercise>()).first)
        #expect(importedWorkoutExercise.exercise?.id == destinationBench.id)
    }

    // MARK: - Barcode clash

    @Test("A barcode clash maps to the local row and doesn't overwrite it")
    func barcodeClashMapsToLocalRow() throws {
        let source = try makeContext()
        let sourceFood = FoodItem(name: "Renamed Upstream", barcode: "5000112637922", nutrientsPer100g: Nutrients(kcal: 250))
        source.insert(sourceFood)
        try source.save()
        let backup = try BackupExporter.makeBackup(from: source)

        let destination = try makeContext()
        let localFood = FoodItem(name: "My Local Name", barcode: "5000112637922", nutrientsPer100g: Nutrients(kcal: 200))
        destination.insert(localFood)
        try destination.save()

        let report = try BackupImporter.performImport(backup, into: destination)

        #expect(report.foodItems.toAdd == 0)
        #expect(report.foodItems.toSkip == 1)
        #expect(try destination.fetchCount(FetchDescriptor<FoodItem>()) == 1)

        let survivor = try #require(try destination.fetch(FetchDescriptor<FoodItem>()).first)
        #expect(survivor.name == "My Local Name")
        #expect(survivor.nutrientsPer100g.kcal == 200)
        #expect(survivor.id == localFood.id)
    }

    // MARK: - Version rejection

    @Test("A future formatVersion is rejected")
    func futureFormatVersionIsRejected() throws {
        var backup = try BackupExporter.makeBackup(from: try makeContext())
        backup.formatVersion = BackupFormat.supportedVersion + 1

        let destination = try makeContext()

        #expect(throws: BackupError.self) {
            try BackupImporter.performImport(backup, into: destination)
        }
        #expect(throws: BackupError.self) {
            try BackupImporter.dryRun(backup, into: destination)
        }
    }

    // MARK: - Set ordering

    @Test("Set order survives the round trip")
    func setOrderIsPreserved() throws {
        let source = try makeContext()
        let exercise = Exercise(name: "Leg Press", isCustom: true)
        source.insert(exercise)
        let workout = Workout(name: "Leg Day")
        source.insert(workout)
        let workoutExercise = workout.addExercise(exercise)

        // Insert out of visual order; only the `order` field should govern
        // the round trip, matching how the model itself reads sets back.
        let third = SetEntry(order: 2, weightKG: 140, reps: 5)
        let first = SetEntry(order: 0, weightKG: 100, reps: 8)
        let second = SetEntry(order: 1, weightKG: 120, reps: 6)
        for set in [third, first, second] {
            set.workoutExercise = workoutExercise
            workoutExercise.sets.append(set)
        }
        try source.save()

        let backup = try BackupExporter.makeBackup(from: source)
        let destination = try makeContext()
        try BackupImporter.performImport(backup, into: destination)

        let importedExercise = try #require(try destination.fetch(FetchDescriptor<WorkoutExercise>()).first)
        #expect(importedExercise.orderedSets.map(\.weightKG) == [100, 120, 140])
    }
}
