import Foundation
import SwiftData

/// A movement that can be logged, e.g. "Barbell Bench Press".
///
/// The app ships with a seeded library (see `ExerciseLibrary`) and the user can
/// add their own. Custom and built-in exercises are the same type — `isCustom`
/// only controls whether the library seeder is allowed to touch it on upgrade.
@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""

    /// Raw value of ``Equipment`` — see the note in `Enums.swift`.
    var equipmentRaw: String = Equipment.other.rawValue
    /// Raw value of ``MuscleGroup``.
    var muscleGroupRaw: String = MuscleGroup.fullBody.rawValue

    var isCustom: Bool = false
    var notes: String?
    var createdAt: Date = Date()

    /// Hidden from the picker without destroying history. Built-in exercises
    /// cannot be deleted outright, because doing so would orphan past sets;
    /// archiving is the safe equivalent.
    var isArchived: Bool = false

    /// A cardio exercise logs duration/distance instead of sets and reps.
    var isCardio: Bool = false

    /// Per-exercise rest timer override, in seconds. Nil means "use
    /// `UserSettings.restTimerSeconds`"; 0 means "no rest timer".
    var restTimerSeconds: Int?

    /// Every logged instance of this exercise, across all workouts. Nullify
    /// rather than cascade: removing an exercise must never silently delete
    /// training history.
    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var workoutEntries: [WorkoutExercise] = []

    /// Every cardio session logged against this exercise. Nullify rather than
    /// cascade, for the same reason as ``workoutEntries``. CloudKit requires
    /// every relationship to declare an inverse; this is that inverse for
    /// `CardioEntry.exercise`.
    @Relationship(deleteRule: .nullify, inverse: \CardioEntry.exercise)
    var cardioEntries: [CardioEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        equipment: Equipment = .other,
        muscleGroup: MuscleGroup = .fullBody,
        isCustom: Bool = false,
        isCardio: Bool = false,
        notes: String? = nil,
        restTimerSeconds: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.equipmentRaw = equipment.rawValue
        self.muscleGroupRaw = muscleGroup.rawValue
        self.isCustom = isCustom
        self.isCardio = isCardio
        self.notes = notes
        self.restTimerSeconds = restTimerSeconds
        self.createdAt = createdAt
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
        set { muscleGroupRaw = newValue.rawValue }
    }
}

/// A cardio session, logged as duration / distance / calories.
///
/// RepCount keeps cardio deliberately lightweight — it is a strength app with a
/// basic cardio log attached, not a running tracker — and this matches that.
@Model
final class CardioEntry {
    var id: UUID = UUID()
    var performedAt: Date = Date()
    var dayKey: String = ""
    var exerciseName: String = ""
    var durationSeconds: Double = 0
    var distanceKM: Double?
    var calories: Double?
    var notes: String?

    var exercise: Exercise?

    init(
        id: UUID = UUID(),
        performedAt: Date = Date(),
        exerciseName: String,
        durationSeconds: Double,
        distanceKM: Double? = nil,
        calories: Double? = nil,
        notes: String? = nil,
        exercise: Exercise? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.performedAt = performedAt
        self.dayKey = DayKey.make(from: performedAt, calendar: calendar)
        self.exerciseName = exerciseName
        self.durationSeconds = durationSeconds
        self.distanceKM = distanceKM
        self.calories = calories
        self.notes = notes
        self.exercise = exercise
    }
}

/// A body measurement taken on a date.
///
/// Stored canonically: body weight in kg, circumferences in cm, body fat in
/// percent. See ``MeasurementType/storedUnit``.
@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var recordedAt: Date = Date()
    var dayKey: String = ""
    /// Raw value of ``MeasurementType``.
    var typeRaw: String = MeasurementType.bodyWeight.rawValue
    var value: Double = 0
    var notes: String?

    init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        type: MeasurementType,
        value: Double,
        notes: String? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.dayKey = DayKey.make(from: recordedAt, calendar: calendar)
        self.typeRaw = type.rawValue
        self.value = value
        self.notes = notes
    }

    var type: MeasurementType {
        get { MeasurementType(rawValue: typeRaw) ?? .bodyWeight }
        set { typeRaw = newValue.rawValue }
    }
}
