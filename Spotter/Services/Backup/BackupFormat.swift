import Foundation

/// The versioned JSON backup format.
///
/// This is deliberately a set of plain `Codable` DTOs, kept separate from the
/// `@Model` types in `Core/Models/`. A model refactor there (renaming a
/// property, changing a type) must not silently change what an old backup
/// file means — the DTOs are the wire format and are only ever translated
/// to and from models explicitly, in `BackupExporter` and `BackupImporter`.
///
/// Relationships are stored as UUID references (`...ID` fields) rather than
/// nested objects, matching how the models themselves are structured as a
/// flat graph of entities linked by `id`.
enum BackupFormat {
    /// The current format version this build writes and the highest version
    /// it can read. A backup with a higher `formatVersion` was made by a
    /// newer build of the app and must be rejected rather than partially
    /// imported.
    static let supportedVersion = 1
}

/// Top-level container for one exported backup file.
struct SpotterBackup: Codable, Sendable {
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String

    var exercises: [ExerciseDTO] = []
    var foodItems: [FoodItemDTO] = []
    var routines: [RoutineDTO] = []
    var routineExercises: [RoutineExerciseDTO] = []
    var workouts: [WorkoutDTO] = []
    var workoutExercises: [WorkoutExerciseDTO] = []
    var setEntries: [SetEntryDTO] = []
    var diaryEntries: [DiaryEntryDTO] = []
    var savedMeals: [SavedMealDTO] = []
    var waterEntries: [WaterEntryDTO] = []
    var cardioEntries: [CardioEntryDTO] = []
    var bodyMeasurements: [BodyMeasurementDTO] = []
    var userSettings: UserSettingsDTO?
}

// MARK: - Training

struct ExerciseDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var equipmentRaw: String
    var muscleGroupRaw: String
    var isCustom: Bool
    var notes: String?
    var createdAt: Date
    var isArchived: Bool
    var isCardio: Bool
    var restTimerSeconds: Int?
}

struct RoutineDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var lastPerformedAt: Date?
}

struct RoutineExerciseDTO: Codable, Sendable {
    var id: UUID
    var routineID: UUID
    var exerciseID: UUID?
    var order: Int
    var targetSets: Int
    var notes: String?
    var supersetGroup: Int?
}

struct WorkoutDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    var notes: String?
    var dayKey: String
    var sourceRoutineID: UUID?
}

struct WorkoutExerciseDTO: Codable, Sendable {
    var id: UUID
    var workoutID: UUID
    var exerciseID: UUID?
    var order: Int
    var notes: String?
    var supersetGroup: Int?
}

struct SetEntryDTO: Codable, Sendable {
    var id: UUID
    var workoutExerciseID: UUID
    var order: Int
    var weightKG: Double
    var reps: Int
    var isCompleted: Bool
    var isWarmup: Bool
    var isDropSet: Bool
    var rpe: Double?
    var completedAt: Date?
}

struct CardioEntryDTO: Codable, Sendable {
    var id: UUID
    var performedAt: Date
    var dayKey: String
    var exerciseName: String
    var durationSeconds: Double
    var distanceKM: Double?
    var calories: Double?
    var notes: String?
    var exerciseID: UUID?
}

struct BodyMeasurementDTO: Codable, Sendable {
    var id: UUID
    var recordedAt: Date
    var dayKey: String
    var typeRaw: String
    var value: Double
    var notes: String?
}

// MARK: - Nutrition

struct FoodItemDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var sourceRaw: String
    var nutrientsPer100g: Nutrients
    var servings: [ServingSize]
    var isCustom: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
}

struct DiaryEntryDTO: Codable, Sendable {
    var id: UUID
    /// Exported and imported verbatim — never recomputed from `loggedAt`.
    /// Re-deriving it on a phone in a different time zone would silently
    /// move entries to other days.
    var dayKey: String
    var loggedAt: Date
    var mealRaw: String
    var foodName: String
    var brandName: String?
    var quantity: Double
    var servingLabel: String
    var servingGramWeight: Double
    var nutrients: Nutrients
    var foodID: UUID?
}

struct SavedMealDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var defaultMealRaw: String?
    var items: [SavedMealItem]
}

// MARK: - Water

struct WaterEntryDTO: Codable, Sendable {
    var id: UUID
    var loggedAt: Date
    var dayKey: String
    var volumeML: Double
    var presetLabel: String?
}

// MARK: - Preferences

struct UserSettingsDTO: Codable, Sendable {
    var id: UUID
    var dailyKcalGoal: Double
    var dailyProteinGoalG: Double
    var dailyCarbsGoalG: Double
    var dailyFatGoalG: Double
    var dailyWaterGoalML: Double
    var waterPresets: [WaterPreset]
    var weightUnitRaw: String
    var volumeUnitRaw: String
    var restTimerSeconds: Int
    var autoStartRestTimer: Bool
    var restTimerNotifications: Bool
    var oneRepMaxFormulaRaw: String
    var keepScreenAwakeDuringWorkout: Bool
    var openFoodFactsContact: String
    var heightCM: Double?
    var birthYear: Int?
    var sexRaw: String?
    var activityLevelRaw: String?
    var weightGoalRaw: String?
    var weeklyRateKG: Double?
    var proteinGPerKG: Double?
    var goalWeightKG: Double?
    var barbellWeightKG: Double?
    var setEffortDisplayRaw: String?
    var createdAt: Date
}

// MARK: - Errors

enum BackupError: Error, LocalizedError, Sendable {
    /// The file's `formatVersion` is higher than this build understands.
    case unsupportedVersion(found: Int, supported: Int)
    case decodingFailed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let found, let supported):
            return "This backup file (format \(found)) was made by a newer version of Spotter. This version supports up to format \(supported)."
        case .decodingFailed:
            return "This file doesn't look like a Spotter backup."
        case .fileReadFailed:
            return "Couldn't read that file."
        }
    }
}

// MARK: - Coding helpers

enum BackupCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
