import Foundation
import SwiftData
import Testing

@testable import Spotter

/// Typed-accessor coverage for the Phase 2 schema step: the new optional
/// `UserSettings` fields and the new enums in `Enums.swift`. Mirrors
/// `SettingsPersistenceTests`.
@MainActor
@Suite("Settings enums and goal-calculator fields")
struct SettingsEnumsTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try SpotterSchema.makeContainer(inMemory: true))
    }

    @Test("Goal calculator inputs are nil by default and persist once set")
    func goalCalculatorInputsPersist() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)

        #expect(settings.heightCM == nil)
        #expect(settings.birthYear == nil)
        #expect(settings.sex == nil)
        #expect(settings.activityLevel == nil)
        #expect(settings.weightGoal == nil)
        #expect(settings.weeklyRateKG == nil)
        #expect(settings.proteinGPerKG == nil)
        #expect(settings.goalWeightKG == nil)
        #expect(settings.barbellWeightKG == nil)

        settings.heightCM = 180
        settings.birthYear = 1994
        settings.sex = .female
        settings.activityLevel = .moderate
        settings.weightGoal = .lose
        settings.weeklyRateKG = 0.5
        settings.proteinGPerKG = 1.8
        settings.goalWeightKG = 70
        settings.barbellWeightKG = 20
        try context.save()

        let refetched = UserSettings.current(in: context)
        #expect(refetched.heightCM == 180)
        #expect(refetched.birthYear == 1994)
        #expect(refetched.sex == .female)
        #expect(refetched.activityLevel == .moderate)
        #expect(refetched.weightGoal == .lose)
        #expect(refetched.weeklyRateKG == 0.5)
        #expect(refetched.proteinGPerKG == 1.8)
        #expect(refetched.goalWeightKG == 70)
        #expect(refetched.barbellWeightKG == 20)
    }

    @Test("A goal-calculator field can be cleared back to nil")
    func goalCalculatorFieldClears() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)
        settings.sex = .male
        try context.save()
        #expect(UserSettings.current(in: context).sex == .male)

        settings.sex = nil
        try context.save()
        #expect(UserSettings.current(in: context).sex == nil)
    }

    @Test("setEffortDisplay defaults to off and round-trips once set")
    func setEffortDisplayDefaultsToOff() throws {
        let context = try makeContext()
        let settings = UserSettings.current(in: context)

        #expect(settings.setEffortDisplayRaw == nil)
        #expect(settings.setEffortDisplay == .off)

        settings.setEffortDisplay = .rpe
        try context.save()

        let refetched = UserSettings.current(in: context)
        #expect(refetched.setEffortDisplay == .rpe)
        #expect(refetched.setEffortDisplayRaw == SetEffortDisplay.rpe.rawValue)
    }

    @Test("ActivityLevel multipliers match the Mifflin–St Jeor activity factors")
    func activityLevelMultipliers() {
        #expect(ActivityLevel.sedentary.multiplier == 1.2)
        #expect(ActivityLevel.light.multiplier == 1.375)
        #expect(ActivityLevel.moderate.multiplier == 1.55)
        #expect(ActivityLevel.veryActive.multiplier == 1.725)
        #expect(ActivityLevel.extraActive.multiplier == 1.9)
    }

    @Test("Every new enum case has a non-empty display name")
    func displayNamesAreNonEmpty() {
        for value in BiologicalSex.allCases {
            #expect(!value.displayName.isEmpty)
        }
        for value in ActivityLevel.allCases {
            #expect(!value.displayName.isEmpty)
            #expect(!value.detail.isEmpty)
        }
        for value in WeightGoal.allCases {
            #expect(!value.displayName.isEmpty)
        }
        for value in SetEffortDisplay.allCases {
            #expect(!value.displayName.isEmpty)
        }
    }

    @Test("Exercise.restTimerSeconds is nil by default and can be overridden or disabled")
    func exerciseRestTimerOverride() throws {
        let context = try makeContext()

        let exercise = Exercise(name: "Overridden Lift")
        context.insert(exercise)
        try context.save()
        #expect(exercise.restTimerSeconds == nil)

        exercise.restTimerSeconds = 0 // explicit "off", distinct from nil ("use default")
        try context.save()

        let refetched = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(refetched.restTimerSeconds == 0)
    }
}
