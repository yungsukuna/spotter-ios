import Foundation
import SwiftData

/// The built-in exercise library, seeded on first launch.
///
/// A workout tracker that opens with an empty exercise list is unusable on day
/// one, so the app ships with the movements most lifters actually log. The user
/// can add their own on top; seeding never touches custom exercises.
enum ExerciseLibrary {

    /// A seed definition. Plain values so the list below stays readable and can
    /// be tested without a SwiftData container.
    struct Seed: Hashable, Sendable {
        var name: String
        var equipment: Equipment
        var muscleGroup: MuscleGroup
        var isCardio: Bool = false
    }

    /// Insert any missing built-in exercises.
    ///
    /// Idempotent and safe to run on every launch: it matches on name, so
    /// re-running adds nothing, and a later app version can extend ``seeds``
    /// and have the new movements appear without disturbing anything the user
    /// has logged or customised.
    ///
    /// Matching on name rather than on a stable seed ID is a deliberate
    /// trade-off. It means renaming a built-in exercise in a future version
    /// would reinsert it under the new name rather than migrating the old row —
    /// acceptable, because the alternative is a stable-ID column that has to be
    /// kept correct forever, and renames here should be vanishingly rare.
    @discardableResult
    static func seedIfNeeded(in context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingNames = Set(existing.map { $0.name.lowercased() })

        var inserted = 0
        for seed in seeds where !existingNames.contains(seed.name.lowercased()) {
            context.insert(
                Exercise(
                    name: seed.name,
                    equipment: seed.equipment,
                    muscleGroup: seed.muscleGroup,
                    isCustom: false,
                    isCardio: seed.isCardio
                )
            )
            inserted += 1
        }

        if inserted > 0 {
            try? context.save()
        }
        return inserted
    }

    /// The built-in movements, grouped roughly by muscle group.
    static let seeds: [Seed] = [
        // MARK: Chest
        Seed(name: "Barbell Bench Press", equipment: .barbell, muscleGroup: .chest),
        Seed(name: "Incline Barbell Bench Press", equipment: .barbell, muscleGroup: .chest),
        Seed(name: "Dumbbell Bench Press", equipment: .dumbbell, muscleGroup: .chest),
        Seed(name: "Incline Dumbbell Bench Press", equipment: .dumbbell, muscleGroup: .chest),
        Seed(name: "Dumbbell Fly", equipment: .dumbbell, muscleGroup: .chest),
        Seed(name: "Cable Fly", equipment: .cable, muscleGroup: .chest),
        Seed(name: "Chest Press Machine", equipment: .machine, muscleGroup: .chest),
        Seed(name: "Push-Up", equipment: .bodyweight, muscleGroup: .chest),
        Seed(name: "Dip", equipment: .bodyweight, muscleGroup: .chest),

        // MARK: Back
        Seed(name: "Deadlift", equipment: .barbell, muscleGroup: .back),
        Seed(name: "Romanian Deadlift", equipment: .barbell, muscleGroup: .hamstrings),
        Seed(name: "Barbell Row", equipment: .barbell, muscleGroup: .back),
        Seed(name: "Pendlay Row", equipment: .barbell, muscleGroup: .back),
        Seed(name: "Dumbbell Row", equipment: .dumbbell, muscleGroup: .back),
        Seed(name: "Pull-Up", equipment: .bodyweight, muscleGroup: .back),
        Seed(name: "Chin-Up", equipment: .bodyweight, muscleGroup: .back),
        Seed(name: "Lat Pulldown", equipment: .cable, muscleGroup: .back),
        Seed(name: "Seated Cable Row", equipment: .cable, muscleGroup: .back),
        Seed(name: "T-Bar Row", equipment: .machine, muscleGroup: .back),
        Seed(name: "Face Pull", equipment: .cable, muscleGroup: .shoulders),
        Seed(name: "Back Extension", equipment: .bodyweight, muscleGroup: .back),

        // MARK: Shoulders
        Seed(name: "Overhead Press", equipment: .barbell, muscleGroup: .shoulders),
        Seed(name: "Seated Dumbbell Shoulder Press", equipment: .dumbbell, muscleGroup: .shoulders),
        Seed(name: "Arnold Press", equipment: .dumbbell, muscleGroup: .shoulders),
        Seed(name: "Lateral Raise", equipment: .dumbbell, muscleGroup: .shoulders),
        Seed(name: "Rear Delt Fly", equipment: .dumbbell, muscleGroup: .shoulders),
        Seed(name: "Upright Row", equipment: .barbell, muscleGroup: .shoulders),
        Seed(name: "Shrug", equipment: .dumbbell, muscleGroup: .shoulders),

        // MARK: Arms
        Seed(name: "Barbell Curl", equipment: .barbell, muscleGroup: .biceps),
        Seed(name: "Dumbbell Curl", equipment: .dumbbell, muscleGroup: .biceps),
        Seed(name: "Hammer Curl", equipment: .dumbbell, muscleGroup: .biceps),
        Seed(name: "Preacher Curl", equipment: .barbell, muscleGroup: .biceps),
        Seed(name: "Cable Curl", equipment: .cable, muscleGroup: .biceps),
        Seed(name: "Close-Grip Bench Press", equipment: .barbell, muscleGroup: .triceps),
        Seed(name: "Tricep Pushdown", equipment: .cable, muscleGroup: .triceps),
        Seed(name: "Overhead Tricep Extension", equipment: .dumbbell, muscleGroup: .triceps),
        Seed(name: "Skull Crusher", equipment: .barbell, muscleGroup: .triceps),
        Seed(name: "Wrist Curl", equipment: .dumbbell, muscleGroup: .forearms),

        // MARK: Legs
        Seed(name: "Back Squat", equipment: .barbell, muscleGroup: .quads),
        Seed(name: "Front Squat", equipment: .barbell, muscleGroup: .quads),
        Seed(name: "Leg Press", equipment: .machine, muscleGroup: .quads),
        Seed(name: "Bulgarian Split Squat", equipment: .dumbbell, muscleGroup: .quads),
        Seed(name: "Walking Lunge", equipment: .dumbbell, muscleGroup: .quads),
        Seed(name: "Leg Extension", equipment: .machine, muscleGroup: .quads),
        Seed(name: "Leg Curl", equipment: .machine, muscleGroup: .hamstrings),
        Seed(name: "Good Morning", equipment: .barbell, muscleGroup: .hamstrings),
        Seed(name: "Hip Thrust", equipment: .barbell, muscleGroup: .glutes),
        Seed(name: "Glute Bridge", equipment: .bodyweight, muscleGroup: .glutes),
        Seed(name: "Standing Calf Raise", equipment: .machine, muscleGroup: .calves),
        Seed(name: "Seated Calf Raise", equipment: .machine, muscleGroup: .calves),

        // MARK: Core
        Seed(name: "Plank", equipment: .bodyweight, muscleGroup: .core),
        Seed(name: "Hanging Leg Raise", equipment: .bodyweight, muscleGroup: .core),
        Seed(name: "Cable Crunch", equipment: .cable, muscleGroup: .core),
        Seed(name: "Russian Twist", equipment: .other, muscleGroup: .core),
        Seed(name: "Ab Wheel Rollout", equipment: .other, muscleGroup: .core),

        // MARK: Full body
        Seed(name: "Clean and Press", equipment: .barbell, muscleGroup: .fullBody),
        Seed(name: "Power Clean", equipment: .barbell, muscleGroup: .fullBody),
        Seed(name: "Kettlebell Swing", equipment: .kettlebell, muscleGroup: .fullBody),
        Seed(name: "Farmer's Walk", equipment: .dumbbell, muscleGroup: .fullBody),
        Seed(name: "Burpee", equipment: .bodyweight, muscleGroup: .fullBody),

        // MARK: Cardio
        Seed(name: "Treadmill", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Running", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Cycling", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Rowing Machine", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Elliptical", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Stair Climber", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Swimming", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
        Seed(name: "Jump Rope", equipment: .cardio, muscleGroup: .cardio, isCardio: true),
    ]
}
