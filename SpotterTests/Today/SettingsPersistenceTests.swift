import Foundation
import SwiftData
import Testing

@testable import Spotter

/// Settings screen behaviour that goes through the singleton row: editing
/// goals and water presets, both of which the Settings screen mutates
/// directly on the `UserSettings` object.
@MainActor
@Suite("Settings persistence")
struct SettingsPersistenceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @Test("Edited goals persist across fetches of the singleton")
    func goalsPersist() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)
        settings.dailyKcalGoal = 2600
        settings.dailyProteinGoalG = 180
        settings.dailyWaterGoalML = 3000
        try context.save()

        let refetched = UserSettings.current(in: context)
        #expect(refetched.dailyKcalGoal == 2600)
        #expect(refetched.dailyProteinGoalG == 180)
        #expect(refetched.dailyWaterGoalML == 3000)
    }

    @Test("Adding a water preset persists and keeps the defaults")
    func addingWaterPresetPersists() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)
        let startingCount = settings.waterPresets.count

        settings.waterPresets.append(WaterPreset(label: "Sports Bottle", volumeML: 1000, symbolName: "waterbottle"))
        try context.save()

        let refetched = UserSettings.current(in: context)
        #expect(refetched.waterPresets.count == startingCount + 1)
        #expect(refetched.waterPresets.contains { $0.label == "Sports Bottle" && $0.volumeML == 1000 })
    }

    @Test("Removing a water preset persists")
    func removingWaterPresetPersists() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)
        settings.waterPresets.removeAll { $0.label == "Glass" }
        try context.save()

        let refetched = UserSettings.current(in: context)
        #expect(!refetched.waterPresets.contains { $0.label == "Glass" })
    }

    @Test("Unit preference changes are stored and read back through the typed accessor")
    func unitPreferencePersists() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)
        settings.volumeUnit = .fluidOunces
        settings.weightUnit = .pounds
        try context.save()

        let refetched = UserSettings.current(in: context)
        #expect(refetched.volumeUnit == .fluidOunces)
        #expect(refetched.weightUnit == .pounds)
    }
}
