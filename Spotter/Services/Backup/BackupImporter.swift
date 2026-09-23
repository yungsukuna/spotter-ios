import Foundation
import SwiftData

/// Per-category counts for a planned or completed import, used to build the
/// confirmation summary shown before committing.
struct ImportReport: Sendable, Equatable {
    struct Counts: Sendable, Equatable {
        var toAdd: Int = 0
        var toSkip: Int = 0
    }

    var exercises = Counts()
    var foodItems = Counts()
    var routines = Counts()
    var routineExercises = Counts()
    var workouts = Counts()
    var workoutExercises = Counts()
    var setEntries = Counts()
    var diaryEntries = Counts()
    var savedMeals = Counts()
    var waterEntries = Counts()
    var cardioEntries = Counts()
    var bodyMeasurements = Counts()
    /// True when the (singleton) settings row's fields were copied across.
    var settingsCopied = false

    var totalToAdd: Int {
        [exercises, foodItems, routines, routineExercises, workouts, workoutExercises,
         setEntries, diaryEntries, savedMeals, waterEntries, cardioEntries, bodyMeasurements]
            .reduce(0) { $0 + $1.toAdd }
    }

    var totalToSkip: Int {
        [exercises, foodItems, routines, routineExercises, workouts, workoutExercises,
         setEntries, diaryEntries, savedMeals, waterEntries, cardioEntries, bodyMeasurements]
            .reduce(0) { $0 + $1.toSkip }
    }

    /// User-facing summary for the confirmation dialog, e.g. "Adds 412 diary
    /// entries, 37 workouts. Skips 12 items already present."
    var summary: String {
        var parts: [String] = []
        if diaryEntries.toAdd > 0 { parts.append("\(diaryEntries.toAdd) diary entries") }
        if workouts.toAdd > 0 { parts.append("\(workouts.toAdd) workouts") }
        if setEntries.toAdd > 0 { parts.append("\(setEntries.toAdd) sets") }
        if exercises.toAdd > 0 { parts.append("\(exercises.toAdd) exercises") }
        if routines.toAdd > 0 { parts.append("\(routines.toAdd) routines") }
        if foodItems.toAdd > 0 { parts.append("\(foodItems.toAdd) foods") }
        if savedMeals.toAdd > 0 { parts.append("\(savedMeals.toAdd) saved meals") }
        if waterEntries.toAdd > 0 { parts.append("\(waterEntries.toAdd) water entries") }
        if cardioEntries.toAdd > 0 { parts.append("\(cardioEntries.toAdd) cardio sessions") }
        if bodyMeasurements.toAdd > 0 { parts.append("\(bodyMeasurements.toAdd) weigh-ins") }

        var text = parts.isEmpty ? "Adds nothing new." : "Adds " + parts.joined(separator: ", ") + "."
        if settingsCopied { text += " Copies your goals and preferences." }
        if totalToSkip > 0 { text += " Skips \(totalToSkip) item\(totalToSkip == 1 ? "" : "s") already present." }
        return text
    }
}

/// Imports a ``SpotterBackup`` into a SwiftData store, merge-only: a record
/// whose UUID already exists locally is left untouched. Local data always
/// wins. See `docs/PHASE2-PLAN.md`, Feature 2, Decision 3.
///
/// `dryRun` and `performImport` share the same planning logic, so the
/// confirmation summary a person approves is exactly what gets written.
@MainActor
enum BackupImporter {

    /// Compute what an import would do, without writing anything.
    static func dryRun(_ backup: SpotterBackup, into context: ModelContext) throws -> ImportReport {
        try makePlan(backup, context: context).report
    }

    /// Apply the import: insert every record the plan calls for, remapping
    /// relationships to local IDs, then save once. On any error, nothing is
    /// left in the context to save, so the caller's `try context.save()`
    /// failure (or the throw here) means no partial write.
    @discardableResult
    static func performImport(_ backup: SpotterBackup, into context: ModelContext) throws -> ImportReport {
        guard backup.formatVersion <= BackupFormat.supportedVersion else {
            throw BackupError.unsupportedVersion(found: backup.formatVersion, supported: BackupFormat.supportedVersion)
        }

        let plan = try makePlan(backup, context: context)

        // Bulk-fetch every existing parent once, rather than one fetch per
        // relationship — both cheaper and simpler than re-querying per row.
        var exercisesByID = try Dictionary(
            uniqueKeysWithValues: context.fetch(FetchDescriptor<Exercise>()).map { ($0.id, $0) }
        )
        var foodsByID = try Dictionary(
            uniqueKeysWithValues: context.fetch(FetchDescriptor<FoodItem>()).map { ($0.id, $0) }
        )
        var routinesByID = try Dictionary(
            uniqueKeysWithValues: context.fetch(FetchDescriptor<Routine>()).map { ($0.id, $0) }
        )
        var workoutsByID = try Dictionary(
            uniqueKeysWithValues: context.fetch(FetchDescriptor<Workout>()).map { ($0.id, $0) }
        )
        var workoutExercisesByID = try Dictionary(
            uniqueKeysWithValues: context.fetch(FetchDescriptor<WorkoutExercise>()).map { ($0.id, $0) }
        )

        // MARK: Parents first

        for dto in plan.exercisesToInsert {
            let exercise = Exercise(
                id: dto.id,
                name: dto.name,
                equipment: Equipment(rawValue: dto.equipmentRaw) ?? .other,
                muscleGroup: MuscleGroup(rawValue: dto.muscleGroupRaw) ?? .fullBody,
                isCustom: dto.isCustom,
                isCardio: dto.isCardio,
                notes: dto.notes,
                restTimerSeconds: dto.restTimerSeconds,
                createdAt: dto.createdAt
            )
            exercise.isArchived = dto.isArchived
            context.insert(exercise)
            exercisesByID[dto.id] = exercise
        }

        for dto in plan.foodItemsToInsert {
            let food = FoodItem(
                id: dto.id,
                name: dto.name,
                brand: dto.brand,
                barcode: dto.barcode,
                source: FoodSource(rawValue: dto.sourceRaw) ?? .custom,
                nutrientsPer100g: dto.nutrientsPer100g,
                servings: dto.servings,
                isCustom: dto.isCustom,
                createdAt: dto.createdAt
            )
            food.lastUsedAt = dto.lastUsedAt
            food.useCount = dto.useCount
            context.insert(food)
            foodsByID[dto.id] = food
        }

        for dto in plan.routinesToInsert {
            let routine = Routine(id: dto.id, name: dto.name, notes: dto.notes, createdAt: dto.createdAt)
            routine.lastPerformedAt = dto.lastPerformedAt
            context.insert(routine)
            routinesByID[dto.id] = routine
        }

        // MARK: Children needing parents

        for dto in plan.workoutsToInsert {
            let workout = Workout(
                id: dto.id,
                name: dto.name,
                startedAt: dto.startedAt,
                finishedAt: dto.finishedAt,
                notes: dto.notes,
                calendar: .current
            )
            workout.dayKey = dto.dayKey
            if let sourceRoutineID = dto.sourceRoutineID {
                workout.sourceRoutine = routinesByID[plan.routineIDMap[sourceRoutineID] ?? sourceRoutineID]
            }
            context.insert(workout)
            workoutsByID[dto.id] = workout
        }

        for dto in plan.routineExercisesToInsert {
            guard let routine = routinesByID[plan.routineIDMap[dto.routineID] ?? dto.routineID] else { continue }
            let exercise = dto.exerciseID.flatMap { exercisesByID[plan.exerciseIDMap[$0] ?? $0] }
            let entry = RoutineExercise(
                id: dto.id,
                exercise: exercise,
                order: dto.order,
                targetSets: dto.targetSets,
                notes: dto.notes,
                supersetGroup: dto.supersetGroup
            )
            entry.routine = routine
            routine.exercises.append(entry)
            context.insert(entry)
        }

        for dto in plan.workoutExercisesToInsert {
            guard let workout = workoutsByID[plan.workoutIDMap[dto.workoutID] ?? dto.workoutID] else { continue }
            let exercise = dto.exerciseID.flatMap { exercisesByID[plan.exerciseIDMap[$0] ?? $0] }
            let entry = WorkoutExercise(
                id: dto.id,
                exercise: exercise,
                order: dto.order,
                notes: dto.notes,
                supersetGroup: dto.supersetGroup
            )
            entry.workout = workout
            workout.exercises.append(entry)
            context.insert(entry)
            workoutExercisesByID[dto.id] = entry
        }

        for dto in plan.setEntriesToInsert {
            guard let workoutExercise = workoutExercisesByID[plan.workoutExerciseIDMap[dto.workoutExerciseID] ?? dto.workoutExerciseID] else { continue }
            let set = SetEntry(
                id: dto.id,
                order: dto.order,
                weightKG: dto.weightKG,
                reps: dto.reps,
                isCompleted: dto.isCompleted,
                isWarmup: dto.isWarmup,
                isDropSet: dto.isDropSet,
                rpe: dto.rpe,
                completedAt: dto.completedAt
            )
            set.workoutExercise = workoutExercise
            workoutExercise.sets.append(set)
            context.insert(set)
        }

        for dto in plan.diaryEntriesToInsert {
            let food = dto.foodID.flatMap { foodsByID[plan.foodIDMap[$0] ?? $0] }
            let entry = DiaryEntry(
                id: dto.id,
                loggedAt: dto.loggedAt,
                meal: Meal(rawValue: dto.mealRaw) ?? .snack,
                foodName: dto.foodName,
                brandName: dto.brandName,
                quantity: dto.quantity,
                serving: ServingSize(label: dto.servingLabel, gramWeight: dto.servingGramWeight),
                nutrients: dto.nutrients,
                food: food
            )
            // The initializer recomputes dayKey from loggedAt; the backup's
            // dayKey is the source of truth, so restore it afterward.
            entry.dayKey = dto.dayKey
            context.insert(entry)
        }

        for dto in plan.savedMealsToInsert {
            let remappedItems = dto.items.map { item -> SavedMealItem in
                var copy = item
                if let foodID = item.foodID {
                    copy.foodID = plan.foodIDMap[foodID] ?? foodID
                }
                return copy
            }
            let meal = SavedMeal(
                id: dto.id,
                name: dto.name,
                createdAt: dto.createdAt,
                lastUsedAt: dto.lastUsedAt,
                useCount: dto.useCount,
                items: remappedItems
            )
            meal.defaultMealRaw = dto.defaultMealRaw
            context.insert(meal)
        }

        for dto in plan.waterEntriesToInsert {
            let entry = WaterEntry(id: dto.id, loggedAt: dto.loggedAt, volumeML: dto.volumeML, presetLabel: dto.presetLabel)
            entry.dayKey = dto.dayKey
            context.insert(entry)
        }

        for dto in plan.cardioEntriesToInsert {
            let exercise = dto.exerciseID.flatMap { exercisesByID[plan.exerciseIDMap[$0] ?? $0] }
            let entry = CardioEntry(
                id: dto.id,
                performedAt: dto.performedAt,
                exerciseName: dto.exerciseName,
                durationSeconds: dto.durationSeconds,
                distanceKM: dto.distanceKM,
                calories: dto.calories,
                notes: dto.notes,
                exercise: exercise
            )
            entry.dayKey = dto.dayKey
            context.insert(entry)
        }

        for dto in plan.bodyMeasurementsToInsert {
            let measurement = BodyMeasurement(
                id: dto.id,
                recordedAt: dto.recordedAt,
                type: MeasurementType(rawValue: dto.typeRaw) ?? .bodyWeight,
                value: dto.value,
                notes: dto.notes
            )
            measurement.dayKey = dto.dayKey
            context.insert(measurement)
        }

        if plan.report.settingsCopied, let dto = backup.userSettings {
            let settings = UserSettings.current(in: context)
            settings.dailyKcalGoal = dto.dailyKcalGoal
            settings.dailyProteinGoalG = dto.dailyProteinGoalG
            settings.dailyCarbsGoalG = dto.dailyCarbsGoalG
            settings.dailyFatGoalG = dto.dailyFatGoalG
            settings.dailyWaterGoalML = dto.dailyWaterGoalML
            settings.waterPresets = dto.waterPresets
            settings.weightUnitRaw = dto.weightUnitRaw
            settings.volumeUnitRaw = dto.volumeUnitRaw
            settings.restTimerSeconds = dto.restTimerSeconds
            settings.autoStartRestTimer = dto.autoStartRestTimer
            settings.restTimerNotifications = dto.restTimerNotifications
            settings.oneRepMaxFormulaRaw = dto.oneRepMaxFormulaRaw
            settings.keepScreenAwakeDuringWorkout = dto.keepScreenAwakeDuringWorkout
            settings.openFoodFactsContact = dto.openFoodFactsContact
            settings.heightCM = dto.heightCM
            settings.birthYear = dto.birthYear
            settings.sexRaw = dto.sexRaw
            settings.activityLevelRaw = dto.activityLevelRaw
            settings.weightGoalRaw = dto.weightGoalRaw
            settings.weeklyRateKG = dto.weeklyRateKG
            settings.proteinGPerKG = dto.proteinGPerKG
            settings.goalWeightKG = dto.goalWeightKG
            settings.barbellWeightKG = dto.barbellWeightKG
            settings.setEffortDisplayRaw = dto.setEffortDisplayRaw
        }

        try context.save()
        return plan.report
    }

    // MARK: - Planning

    /// Everything needed to either report on or apply an import, computed
    /// once from read-only fetches against `context`.
    private struct Plan {
        var report = ImportReport()

        var exerciseIDMap: [UUID: UUID] = [:] // backup id -> local id (already present)
        var exercisesToInsert: [ExerciseDTO] = []

        var foodIDMap: [UUID: UUID] = [:]
        var foodItemsToInsert: [FoodItemDTO] = []

        var routineIDMap: [UUID: UUID] = [:]
        var routinesToInsert: [RoutineDTO] = []

        var workoutIDMap: [UUID: UUID] = [:]
        var workoutsToInsert: [WorkoutDTO] = []

        var routineExercisesToInsert: [RoutineExerciseDTO] = []
        var workoutExerciseIDMap: [UUID: UUID] = [:]
        var workoutExercisesToInsert: [WorkoutExerciseDTO] = []
        var setEntriesToInsert: [SetEntryDTO] = []
        var diaryEntriesToInsert: [DiaryEntryDTO] = []
        var savedMealsToInsert: [SavedMealDTO] = []
        var waterEntriesToInsert: [WaterEntryDTO] = []
        var cardioEntriesToInsert: [CardioEntryDTO] = []
        var bodyMeasurementsToInsert: [BodyMeasurementDTO] = []
    }

    private static func makePlan(_ backup: SpotterBackup, context: ModelContext) throws -> Plan {
        guard backup.formatVersion <= BackupFormat.supportedVersion else {
            throw BackupError.unsupportedVersion(found: backup.formatVersion, supported: BackupFormat.supportedVersion)
        }

        var plan = Plan()

        // MARK: Exercises — skip by UUID, then remap built-ins by lowercased name

        let existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        let existingExerciseIDs = Set(existingExercises.map(\.id))
        // ExerciseLibrary.seedIfNeeded matches on lowercased name regardless
        // of source; mirror that rule here so a restored library doesn't
        // duplicate the seeded one.
        var existingExerciseByLowercasedName: [String: UUID] = [:]
        for exercise in existingExercises {
            existingExerciseByLowercasedName[exercise.name.lowercased()] = exercise.id
        }

        var seenExerciseIDsInBackup = Set<UUID>()
        for dto in backup.exercises {
            guard !seenExerciseIDsInBackup.contains(dto.id) else { continue }
            seenExerciseIDsInBackup.insert(dto.id)

            if existingExerciseIDs.contains(dto.id) {
                plan.exerciseIDMap[dto.id] = dto.id
                plan.report.exercises.toSkip += 1
            } else if !dto.isCustom, let localID = existingExerciseByLowercasedName[dto.name.lowercased()] {
                plan.exerciseIDMap[dto.id] = localID
                plan.report.exercises.toSkip += 1
            } else {
                plan.exerciseIDMap[dto.id] = dto.id
                plan.exercisesToInsert.append(dto)
                plan.report.exercises.toAdd += 1
                // A second built-in with the same name later in the same
                // backup should remap to this one too, not insert again.
                if !dto.isCustom {
                    existingExerciseByLowercasedName[dto.name.lowercased()] = dto.id
                }
            }
        }

        // MARK: Food items — skip by UUID, then remap barcode clashes

        let existingFoods = try context.fetch(FetchDescriptor<FoodItem>())
        let existingFoodIDs = Set(existingFoods.map(\.id))
        var existingFoodByBarcode: [String: UUID] = [:]
        for food in existingFoods {
            if let barcode = food.barcode { existingFoodByBarcode[barcode] = food.id }
        }

        var seenFoodIDsInBackup = Set<UUID>()
        for dto in backup.foodItems {
            guard !seenFoodIDsInBackup.contains(dto.id) else { continue }
            seenFoodIDsInBackup.insert(dto.id)

            if existingFoodIDs.contains(dto.id) {
                plan.foodIDMap[dto.id] = dto.id
                plan.report.foodItems.toSkip += 1
            } else if let barcode = dto.barcode, let localID = existingFoodByBarcode[barcode] {
                // Local row wins: map to it, never overwrite its fields.
                plan.foodIDMap[dto.id] = localID
                plan.report.foodItems.toSkip += 1
            } else {
                plan.foodIDMap[dto.id] = dto.id
                plan.foodItemsToInsert.append(dto)
                plan.report.foodItems.toAdd += 1
                if let barcode = dto.barcode {
                    existingFoodByBarcode[barcode] = dto.id
                }
            }
        }

        // MARK: Routines

        let existingRoutineIDs = Set(try context.fetch(FetchDescriptor<Routine>()).map(\.id))
        for dto in backup.routines {
            if existingRoutineIDs.contains(dto.id) {
                plan.routineIDMap[dto.id] = dto.id
                plan.report.routines.toSkip += 1
            } else {
                plan.routineIDMap[dto.id] = dto.id
                plan.routinesToInsert.append(dto)
                plan.report.routines.toAdd += 1
            }
        }

        // MARK: Workouts

        let existingWorkoutIDs = Set(try context.fetch(FetchDescriptor<Workout>()).map(\.id))
        for dto in backup.workouts {
            if existingWorkoutIDs.contains(dto.id) {
                plan.workoutIDMap[dto.id] = dto.id
                plan.report.workouts.toSkip += 1
            } else {
                plan.workoutIDMap[dto.id] = dto.id
                plan.workoutsToInsert.append(dto)
                plan.report.workouts.toAdd += 1
            }
        }

        // MARK: Routine exercises

        let existingRoutineExerciseIDs = Set(try context.fetch(FetchDescriptor<RoutineExercise>()).map(\.id))
        for dto in backup.routineExercises {
            if existingRoutineExerciseIDs.contains(dto.id) {
                plan.report.routineExercises.toSkip += 1
            } else {
                plan.routineExercisesToInsert.append(dto)
                plan.report.routineExercises.toAdd += 1
            }
        }

        // MARK: Workout exercises

        let existingWorkoutExercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        let existingWorkoutExerciseIDs = Set(existingWorkoutExercises.map(\.id))
        for dto in backup.workoutExercises {
            if existingWorkoutExerciseIDs.contains(dto.id) {
                plan.workoutExerciseIDMap[dto.id] = dto.id
                plan.report.workoutExercises.toSkip += 1
            } else {
                plan.workoutExerciseIDMap[dto.id] = dto.id
                plan.workoutExercisesToInsert.append(dto)
                plan.report.workoutExercises.toAdd += 1
            }
        }

        // MARK: Set entries

        let existingSetEntryIDs = Set(try context.fetch(FetchDescriptor<SetEntry>()).map(\.id))
        for dto in backup.setEntries {
            if existingSetEntryIDs.contains(dto.id) {
                plan.report.setEntries.toSkip += 1
            } else {
                plan.setEntriesToInsert.append(dto)
                plan.report.setEntries.toAdd += 1
            }
        }

        // MARK: Diary entries

        let existingDiaryEntryIDs = Set(try context.fetch(FetchDescriptor<DiaryEntry>()).map(\.id))
        for dto in backup.diaryEntries {
            if existingDiaryEntryIDs.contains(dto.id) {
                plan.report.diaryEntries.toSkip += 1
            } else {
                plan.diaryEntriesToInsert.append(dto)
                plan.report.diaryEntries.toAdd += 1
            }
        }

        // MARK: Saved meals

        let existingSavedMealIDs = Set(try context.fetch(FetchDescriptor<SavedMeal>()).map(\.id))
        for dto in backup.savedMeals {
            if existingSavedMealIDs.contains(dto.id) {
                plan.report.savedMeals.toSkip += 1
            } else {
                plan.savedMealsToInsert.append(dto)
                plan.report.savedMeals.toAdd += 1
            }
        }

        // MARK: Water entries

        let existingWaterEntryIDs = Set(try context.fetch(FetchDescriptor<WaterEntry>()).map(\.id))
        for dto in backup.waterEntries {
            if existingWaterEntryIDs.contains(dto.id) {
                plan.report.waterEntries.toSkip += 1
            } else {
                plan.waterEntriesToInsert.append(dto)
                plan.report.waterEntries.toAdd += 1
            }
        }

        // MARK: Cardio entries

        let existingCardioEntryIDs = Set(try context.fetch(FetchDescriptor<CardioEntry>()).map(\.id))
        for dto in backup.cardioEntries {
            if existingCardioEntryIDs.contains(dto.id) {
                plan.report.cardioEntries.toSkip += 1
            } else {
                plan.cardioEntriesToInsert.append(dto)
                plan.report.cardioEntries.toAdd += 1
            }
        }

        // MARK: Body measurements

        let existingBodyMeasurementIDs = Set(try context.fetch(FetchDescriptor<BodyMeasurement>()).map(\.id))
        for dto in backup.bodyMeasurements {
            if existingBodyMeasurementIDs.contains(dto.id) {
                plan.report.bodyMeasurements.toSkip += 1
            } else {
                plan.bodyMeasurementsToInsert.append(dto)
                plan.report.bodyMeasurements.toAdd += 1
            }
        }

        // MARK: Settings — never a second row; copy fields only into a fresh store

        if backup.userSettings != nil {
            // Hoisted: `try` is not allowed inside the autoclosure on the
            // right-hand side of `&&`.
            let existingRoutineCount = try context.fetchCount(FetchDescriptor<Routine>())
            let isFreshStore =
                existingDiaryEntryIDs.isEmpty
                && existingSavedMealIDs.isEmpty
                && existingWaterEntryIDs.isEmpty
                && existingWorkoutIDs.isEmpty
                && existingWorkoutExerciseIDs.isEmpty
                && existingSetEntryIDs.isEmpty
                && existingRoutineCount == 0
                && existingRoutineExerciseIDs.isEmpty
                && existingCardioEntryIDs.isEmpty
                && existingBodyMeasurementIDs.isEmpty
                && !existingFoods.contains { $0.isCustom }
            plan.report.settingsCopied = isFreshStore
        }

        return plan
    }
}
