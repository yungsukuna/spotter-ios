import Foundation
import SwiftData

/// App-wide preferences and daily goals.
///
/// This is a singleton row. Use ``UserSettings/current(in:)`` to fetch it —
/// that helper creates the row on first access, so no caller has to handle the
/// "no settings yet" case.
@Model
final class UserSettings {
    var id: UUID = UUID()

    // MARK: - Nutrition goals

    var dailyKcalGoal: Double = 2000
    var dailyProteinGoalG: Double = 150
    var dailyCarbsGoalG: Double = 200
    var dailyFatGoalG: Double = 67

    // MARK: - Water goals

    var dailyWaterGoalML: Double = 2500
    /// Quick-add buttons on the water screen.
    var waterPresets: [WaterPreset] = WaterPreset.defaults

    // MARK: - Units
    //
    // Data is always stored metric. These only affect display and input.

    /// Raw value of ``WeightUnit``.
    var weightUnitRaw: String = WeightUnit.kilograms.rawValue
    /// Raw value of ``VolumeUnit``.
    var volumeUnitRaw: String = VolumeUnit.millilitres.rawValue

    // MARK: - Workout preferences

    /// Default rest timer length, in seconds.
    var restTimerSeconds: Int = 90
    /// Whether finishing a set starts the rest timer automatically.
    var autoStartRestTimer: Bool = true
    /// Post a local notification when the rest timer expires, so it still fires
    /// with the screen locked.
    var restTimerNotifications: Bool = true
    /// Raw value of ``OneRepMaxFormula``.
    var oneRepMaxFormulaRaw: String = OneRepMaxFormula.epley.rawValue
    /// Keep the screen awake during an active workout.
    var keepScreenAwakeDuringWorkout: Bool = true

    // MARK: - Food data

    /// Contact string sent in the Open Food Facts `User-Agent` header. The API
    /// requires apps to identify themselves; see `OpenFoodFactsClient`.
    var openFoodFactsContact: String = ""

    var createdAt: Date = Date()

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }

    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
        set { weightUnitRaw = newValue.rawValue }
    }

    var volumeUnit: VolumeUnit {
        get { VolumeUnit(rawValue: volumeUnitRaw) ?? .millilitres }
        set { volumeUnitRaw = newValue.rawValue }
    }

    var oneRepMaxFormula: OneRepMaxFormula {
        get { OneRepMaxFormula(rawValue: oneRepMaxFormulaRaw) ?? .epley }
        set { oneRepMaxFormulaRaw = newValue.rawValue }
    }

    /// Macro goals as a nutrition panel, for comparing against day totals.
    var nutritionGoal: Nutrients {
        Nutrients(
            kcal: dailyKcalGoal,
            proteinG: dailyProteinGoalG,
            carbsG: dailyCarbsGoalG,
            fatG: dailyFatGoalG
        )
    }

    /// Fetch the singleton, creating it on first access.
    ///
    /// Safe to call from anywhere with a context; it never returns nil and
    /// never creates a second row.
    static func current(in context: ModelContext) -> UserSettings {
        var descriptor = FetchDescriptor<UserSettings>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let settings = UserSettings()
        context.insert(settings)
        return settings
    }
}
