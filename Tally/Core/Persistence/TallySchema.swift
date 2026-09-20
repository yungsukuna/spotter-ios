import Foundation
import SwiftData

/// The SwiftData schema and container setup.
///
/// Every `@Model` type in the app must be listed in ``models``. A type left out
/// will compile fine and then fail at runtime the first time it is inserted,
/// with an error that does not obviously point at this file — so when adding a
/// model, add it here in the same commit.
enum TallySchema {

    static let models: [any PersistentModel.Type] = [
        // Nutrition
        FoodItem.self,
        DiaryEntry.self,
        // Water
        WaterEntry.self,
        // Training
        Exercise.self,
        Workout.self,
        WorkoutExercise.self,
        SetEntry.self,
        Routine.self,
        RoutineExercise.self,
        CardioEntry.self,
        BodyMeasurement.self,
        // Preferences
        UserSettings.self,
    ]

    static var schema: Schema { Schema(models) }

    /// The app's on-disk container.
    ///
    /// CloudKit sync is deliberately off. Turning it on later is a one-line
    /// change here (`cloudKitDatabase: .private("iCloud.com.yungsukuna.tally")`)
    /// plus the iCloud capability, but it also imposes constraints the schema
    /// must already satisfy — every attribute optional or defaulted, and no
    /// `@Attribute(.unique)`. The first is already true throughout; the second
    /// is not, because `FoodItem.barcode` is unique, so enabling sync means
    /// replacing that with an explicit dedupe on insert.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An in-memory container for tests and SwiftUI previews.
    ///
    /// Trapping on failure is correct here: an in-memory container cannot fail
    /// for an environmental reason, so a throw means the schema itself is
    /// malformed, and every test would fail anyway.
    @MainActor
    static func previewContainer(seeded: Bool = true) -> ModelContainer {
        do {
            let container = try makeContainer(inMemory: true)
            if seeded {
                ExerciseLibrary.seedIfNeeded(in: container.mainContext)
            }
            return container
        } catch {
            fatalError("Failed to build in-memory ModelContainer: \(error)")
        }
    }
}
