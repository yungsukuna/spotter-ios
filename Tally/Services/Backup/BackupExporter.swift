import Foundation
import SwiftData

/// Builds a ``TallyBackup`` from the current SwiftData store, and encodes it
/// to a file ready for `ShareLink`.
///
/// Runs on the main actor and reads every model in the schema. That is fine
/// at this app's data scale — see the note in `docs/PHASE2-PLAN.md`.
@MainActor
enum BackupExporter {

    /// Read every model out of `context` into DTOs.
    static func makeBackup(from context: ModelContext) throws -> TallyBackup {
        var backup = TallyBackup(
            formatVersion: BackupFormat.supportedVersion,
            exportedAt: Date(),
            appVersion: AppConfiguration.appVersion
        )

        backup.exercises = try context.fetch(FetchDescriptor<Exercise>()).map { exercise in
            ExerciseDTO(
                id: exercise.id,
                name: exercise.name,
                equipmentRaw: exercise.equipmentRaw,
                muscleGroupRaw: exercise.muscleGroupRaw,
                isCustom: exercise.isCustom,
                notes: exercise.notes,
                createdAt: exercise.createdAt,
                isArchived: exercise.isArchived,
                isCardio: exercise.isCardio,
                restTimerSeconds: exercise.restTimerSeconds
            )
        }

        backup.foodItems = try context.fetch(FetchDescriptor<FoodItem>()).map { food in
            FoodItemDTO(
                id: food.id,
                name: food.name,
                brand: food.brand,
                barcode: food.barcode,
                sourceRaw: food.sourceRaw,
                nutrientsPer100g: food.nutrientsPer100g,
                servings: food.servings,
                isCustom: food.isCustom,
                createdAt: food.createdAt,
                lastUsedAt: food.lastUsedAt,
                useCount: food.useCount
            )
        }

        backup.routines = try context.fetch(FetchDescriptor<Routine>()).map { routine in
            RoutineDTO(
                id: routine.id,
                name: routine.name,
                notes: routine.notes,
                createdAt: routine.createdAt,
                lastPerformedAt: routine.lastPerformedAt
            )
        }

        backup.routineExercises = try context.fetch(FetchDescriptor<RoutineExercise>()).compactMap { entry in
            // A RoutineExercise with no parent routine is orphaned data that
            // cannot be re-imported meaningfully; skip it rather than crash.
            guard let routineID = entry.routine?.id else { return nil }
            return RoutineExerciseDTO(
                id: entry.id,
                routineID: routineID,
                exerciseID: entry.exercise?.id,
                order: entry.order,
                targetSets: entry.targetSets,
                notes: entry.notes,
                supersetGroup: entry.supersetGroup
            )
        }

        backup.workouts = try context.fetch(FetchDescriptor<Workout>()).map { workout in
            WorkoutDTO(
                id: workout.id,
                name: workout.name,
                startedAt: workout.startedAt,
                finishedAt: workout.finishedAt,
                notes: workout.notes,
                dayKey: workout.dayKey,
                sourceRoutineID: workout.sourceRoutine?.id
            )
        }

        backup.workoutExercises = try context.fetch(FetchDescriptor<WorkoutExercise>()).compactMap { entry in
            guard let workoutID = entry.workout?.id else { return nil }
            return WorkoutExerciseDTO(
                id: entry.id,
                workoutID: workoutID,
                exerciseID: entry.exercise?.id,
                order: entry.order,
                notes: entry.notes,
                supersetGroup: entry.supersetGroup
            )
        }

        backup.setEntries = try context.fetch(FetchDescriptor<SetEntry>()).compactMap { set in
            guard let workoutExerciseID = set.workoutExercise?.id else { return nil }
            return SetEntryDTO(
                id: set.id,
                workoutExerciseID: workoutExerciseID,
                order: set.order,
                weightKG: set.weightKG,
                reps: set.reps,
                isCompleted: set.isCompleted,
                isWarmup: set.isWarmup,
                isDropSet: set.isDropSet,
                rpe: set.rpe,
                completedAt: set.completedAt
            )
        }

        backup.diaryEntries = try context.fetch(FetchDescriptor<DiaryEntry>()).map { entry in
            DiaryEntryDTO(
                id: entry.id,
                dayKey: entry.dayKey,
                loggedAt: entry.loggedAt,
                mealRaw: entry.mealRaw,
                foodName: entry.foodName,
                brandName: entry.brandName,
                quantity: entry.quantity,
                servingLabel: entry.servingLabel,
                servingGramWeight: entry.servingGramWeight,
                nutrients: entry.nutrients,
                foodID: entry.food?.id
            )
        }

        backup.savedMeals = try context.fetch(FetchDescriptor<SavedMeal>()).map { meal in
            SavedMealDTO(
                id: meal.id,
                name: meal.name,
                createdAt: meal.createdAt,
                lastUsedAt: meal.lastUsedAt,
                useCount: meal.useCount,
                defaultMealRaw: meal.defaultMealRaw,
                items: meal.items
            )
        }

        backup.waterEntries = try context.fetch(FetchDescriptor<WaterEntry>()).map { entry in
            WaterEntryDTO(
                id: entry.id,
                loggedAt: entry.loggedAt,
                dayKey: entry.dayKey,
                volumeML: entry.volumeML,
                presetLabel: entry.presetLabel
            )
        }

        backup.cardioEntries = try context.fetch(FetchDescriptor<CardioEntry>()).map { entry in
            CardioEntryDTO(
                id: entry.id,
                performedAt: entry.performedAt,
                dayKey: entry.dayKey,
                exerciseName: entry.exerciseName,
                durationSeconds: entry.durationSeconds,
                distanceKM: entry.distanceKM,
                calories: entry.calories,
                notes: entry.notes,
                exerciseID: entry.exercise?.id
            )
        }

        backup.bodyMeasurements = try context.fetch(FetchDescriptor<BodyMeasurement>()).map { measurement in
            BodyMeasurementDTO(
                id: measurement.id,
                recordedAt: measurement.recordedAt,
                dayKey: measurement.dayKey,
                typeRaw: measurement.typeRaw,
                value: measurement.value,
                notes: measurement.notes
            )
        }

        if let settings = try context.fetch(FetchDescriptor<UserSettings>()).first {
            backup.userSettings = UserSettingsDTO(
                id: settings.id,
                dailyKcalGoal: settings.dailyKcalGoal,
                dailyProteinGoalG: settings.dailyProteinGoalG,
                dailyCarbsGoalG: settings.dailyCarbsGoalG,
                dailyFatGoalG: settings.dailyFatGoalG,
                dailyWaterGoalML: settings.dailyWaterGoalML,
                waterPresets: settings.waterPresets,
                weightUnitRaw: settings.weightUnitRaw,
                volumeUnitRaw: settings.volumeUnitRaw,
                restTimerSeconds: settings.restTimerSeconds,
                autoStartRestTimer: settings.autoStartRestTimer,
                restTimerNotifications: settings.restTimerNotifications,
                oneRepMaxFormulaRaw: settings.oneRepMaxFormulaRaw,
                keepScreenAwakeDuringWorkout: settings.keepScreenAwakeDuringWorkout,
                openFoodFactsContact: settings.openFoodFactsContact,
                heightCM: settings.heightCM,
                birthYear: settings.birthYear,
                sexRaw: settings.sexRaw,
                activityLevelRaw: settings.activityLevelRaw,
                weightGoalRaw: settings.weightGoalRaw,
                weeklyRateKG: settings.weeklyRateKG,
                proteinGPerKG: settings.proteinGPerKG,
                goalWeightKG: settings.goalWeightKG,
                barbellWeightKG: settings.barbellWeightKG,
                setEffortDisplayRaw: settings.setEffortDisplayRaw,
                createdAt: settings.createdAt
            )
        }

        return backup
    }

    /// Encode a backup to JSON data.
    static func encode(_ backup: TallyBackup) throws -> Data {
        try BackupCoding.makeEncoder().encode(backup)
    }

    /// Write a fresh export to `Tally-Backup-yyyy-MM-dd.json` inside
    /// `FileManager.default.temporaryDirectory`, ready to hand to `ShareLink`.
    static func writeExportFile(from context: ModelContext, calendar: Calendar = .current) throws -> URL {
        let backup = try makeBackup(from: context)
        let data = try encode(backup)
        let dayKey = DayKey.make(from: backup.exportedAt, calendar: calendar)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tally-Backup-\(dayKey)")
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
